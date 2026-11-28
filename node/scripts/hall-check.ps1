#Requires -Version 7.5
<#
.SYNOPSIS
  Hall acceptance (T1-NODE-HALL-PRINT R4): the node starts from an initialised local D1 with no network,
  serves the board, a replay step and unlock, and keeps a feed pause and the stepped observation across a
  restart.
.DESCRIPTION
  Run from any directory with the network adapter off:  pwsh node/scripts/hall-check.ps1 -Offline
  With -Offline the script refuses to run (exit 2) unless DNS resolution of a public host fails, both
  through the system resolver and straight to a public DNS server; after that check it makes no network
  request but to the node on 127.0.0.1. Without -Offline it runs the same checks online as a rehearsal,
  which is not an R4 receipt.
  It works on a copy of the local D1 (.wrangler/state, from npm run db:migrate and npm run db:seed), so
  the hall's own D1 is unchanged. Exit 0: every check passed; 1: a check failed; 2: refused.
#>
param([switch]$Offline, [int]$Port = 8799, [string]$PublicHost = "example.com")

$ErrorActionPreference = "Stop"
$node = Split-Path -Parent $PSScriptRoot
$started = $null

function Pass([string]$what) { Write-Host "ok   $what" }
function Check([bool]$ok, [string]$what) { if (-not $ok) { throw "check failed: $what" }; Pass $what }

# True when the host resolves through the system resolver or through 1.1.1.1 (bypassing the DNS cache).
function Resolves([string]$name) {
  if (-not (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) { return $true } # cannot tell: refuse
  foreach ($server in @($null, "1.1.1.1")) {
    $query = @{ Name = $name; DnsOnly = $true; QuickTimeout = $true; ErrorAction = "SilentlyContinue" }
    if ($server) { $query.Server = $server }
    if (Resolve-DnsName @query) { return $true }
  }
  return $false
}

if ($Offline) {
  if (Resolves $PublicHost) {
    Write-Host "REFUSED: DNS resolves $PublicHost, so this machine is online. Turn the network adapter off and run again with -Offline."
    exit 2
  }
  Pass "offline: DNS of $PublicHost fails"
} else {
  Write-Host "online rehearsal: not an R4 receipt (run with -Offline and the network adapter off for that)"
}

$source = Join-Path $node ".wrangler/state"
if (-not (Test-Path (Join-Path $source "v3/d1"))) {
  Write-Host "REFUSED: no local D1 in $source. While online run: npm --prefix node ci; npm --prefix node run db:migrate; npm --prefix node run db:seed"
  exit 2
}
$work = Join-Path ([IO.Path]::GetTempPath()) "chord-hall-$PID"
Copy-Item -Recurse $source (Join-Path $work "state")
$env:CI = "1"; $env:WRANGLER_SEND_METRICS = "false"
$code = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(9))
$secret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$base = "http://127.0.0.1:$Port"
$warning = Get-Content -Raw (Join-Path $node "fixtures/feeds/01-flood-warning.json") | ConvertFrom-Json -AsHashtable -DateKind String
$feed = $warning.source.id
$headline = $warning.items[0].headline
$at = $warning.items[0].sent

function Start-Node {
  if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { throw "port $Port is in use" }
  $nodeArgs = @("node_modules/wrangler/bin/wrangler.js", "dev", "--config", "dist/server/wrangler.json", "--persist-to", (Join-Path $work "state"),
    "--ip", "127.0.0.1", "--port", "$Port", "--inspector-port", "$($Port + 1)", "--show-interactive-dev-session=false",
    "--var", "SESSION_SECRET:$secret", "--var", "HUB_COORDINATOR_CODE:$code") | ForEach-Object { '"' + $_ + '"' }
  $script:started = Start-Process -FilePath (Get-Command node).Source -ArgumentList $nodeArgs -WorkingDirectory $node -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $work "node-$(Get-Date -Format HHmmssfff).log") -RedirectStandardError (Join-Path $work "node-err-$(Get-Date -Format HHmmssfff).log")
  for ($deadline = (Get-Date).AddSeconds(120); (Get-Date) -lt $deadline; Start-Sleep -Seconds 1) {
    if ($script:started.HasExited) { throw "the node exited with code $($script:started.ExitCode)" }
    try { if ((Invoke-WebRequest "$base/" -SkipHttpErrorCheck -TimeoutSec 5).StatusCode -eq 200) { Pass "node pid $($script:started.Id) serves GET / with 200"; return } } catch { }
  }
  throw "the node did not answer GET / within 120 s"
}

# Stops the tree of the process this script started, by its pid, and checks it is gone.
function Stop-Node {
  $p = $script:started
  if (-not $p) { return }
  $script:started = $null
  if (-not $p.HasExited) { taskkill /pid $p.Id /T /F | Out-Null }
  $p.WaitForExit(10000) | Out-Null
  if (-not $p.HasExited -or (Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)")) { throw "node pid $($p.Id) or a child is still running" }
  Pass "node pid $($p.Id) and its children stopped"
}

function Post([string]$path, [string]$cookie, [string]$body = "") {
  $headers = @{ Origin = $base }
  if ($cookie) { $headers.Cookie = $cookie }
  Invoke-WebRequest "$base$path" -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -MaximumRedirection 0 `
    -SkipHttpErrorCheck -Headers $headers -TimeoutSec 30 -ErrorAction SilentlyContinue # a 303 is an answer, not an error
}
function Board([string]$path) { (Invoke-WebRequest "$base$path" -SkipHttpErrorCheck -TimeoutSec 30).Content }
$pausedTile = "data-feed=`"$feed`" data-state=`"paused`""

$failed = $false
Push-Location $node
try {
  & (Get-Command node).Source node_modules/vite/bin/vite.js build --logLevel warn
  if ($LASTEXITCODE -ne 0) { throw "vite build exited $LASTEXITCODE" }
  Start-Node
  Check ((Board "/").Contains("data-posture=")) "the board shows a posture"
  $unlock = Post "/api/unlock" "" "code=$code"
  $cookie = "$($unlock.Headers['Set-Cookie'])".Split(";")[0]
  Check ($unlock.StatusCode -eq 303 -and $cookie.StartsWith("chord_session=")) "unlock with the test code answers 303 with a session cookie"
  $step = Post "/api/fixtures/step" $cookie
  Check ($step.StatusCode -eq 200) "replay step answers 200: $($step.Content)"
  Check ((Board "/?at=$at").Contains($headline)) "the board at $at shows the stepped observation"
  $pause = Post "/api/feeds/$feed/pause" $cookie
  Check ($pause.StatusCode -eq 200 -and (Board "/").Contains($pausedTile)) "feed $feed is paused"
  Stop-Node
  Start-Node
  Check ((Board "/").Contains($pausedTile)) "after the restart, feed $feed is still paused"
  Check ((Board "/?at=$at").Contains($headline)) "after the restart, the board at $at still shows the stepped observation"
} catch {
  Write-Host "FAIL: $_"
  $failed = $true
} finally {
  try { Stop-Node } catch { Write-Host "FAIL: $_"; $failed = $true }
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
  Pop-Location
}
if ($failed) { exit 1 }
Write-Host "PASS: hall check ($(if ($Offline) { 'offline' } else { 'online rehearsal' }))"
exit 0
