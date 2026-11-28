# CHORD hub node

The hub board for one community hall, run on a Windows laptop with no uplink. Commands, architecture
and the runtime decision: `CLAUDE.md` and `SPIKE.md` in this directory.

## Hall setup (while online)

Run these from the repository root once, while the laptop still has a network:

```powershell
npm --prefix node ci            # dependencies
npm --prefix node run db:migrate # create the local D1 (node/.wrangler/state)
npm --prefix node run db:seed    # load fixtures/demo-corpus.json; once per fresh D1
```

Then write `node/.env` (gitignored; see `node/.env.example`) with a `HUB_COORDINATOR_CODE` chosen for
the hall and a random `SESSION_SECRET`, and build and start the node:

```powershell
npm --prefix node run build
npm --prefix node run start      # wrangler dev on the built Worker, http://127.0.0.1:8787
```

Nothing after this point needs the network. `GET /` is the home hub board; `/hub/<id>` is any hub;
`?at=<ISO time>` sets the replay cursor; `/hub/<id>/print` is the one-page A4 print, which never shows a
restricted asset, whoever is signed in.

## Manual fixture step

The node does not poll feeds on its own. A coordinator applies the next file of `fixtures/feeds/` by
hand, from a PowerShell 7 prompt on the laptop:

```powershell
$base = "http://127.0.0.1:8787"
Invoke-WebRequest "$base/api/unlock" -Method Post -Body "code=<hall code>" -ContentType application/x-www-form-urlencoded `
  -Headers @{ Origin = $base } -MaximumRedirection 0 -SkipHttpErrorCheck -SessionVariable hall
Invoke-WebRequest "$base/api/fixtures/step" -Method Post -Headers @{ Origin = $base } -WebSession $hall
Invoke-WebRequest "$base/api/feeds/fict-river-watch/pause" -Method Post -Headers @{ Origin = $base } -WebSession $hall
Invoke-WebRequest "$base/api/lock" -Method Post -Headers @{ Origin = $base } -WebSession $hall
```

Each step answers `{"cursor": n}`, the number of files applied. Feed pause and observations are kept in
the local D1 across restarts.

## When the uplink fails

The node serves the board, the print view, replay steps and unlock from the laptop's local D1 with no
network. A client that reaches the board only through a cloud service (a cloud-hosted copy of the board,
a phone on mobile data) loses access when the hall's uplink fails; the board on the laptop keeps working.

## Hall check

`pwsh node/scripts/hall-check.ps1 -Offline`, with the network adapter off, builds the node, starts it on a
copy of the local D1, checks the board, unlocks with a test code, steps a fixture, pauses a feed, stops the
node by pid, restarts it and checks the pause and the stepped observation are still there. It refuses to
run (exit 2) while DNS of a public host resolves, exits 1 on any failed check, and leaves no process
running. Without `-Offline` it runs the same checks online as a rehearsal, which is not a receipt.
