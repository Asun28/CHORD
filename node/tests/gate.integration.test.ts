// Builds the node, runs it under wrangler dev on a fresh local D1, and drives it with two cookie jars.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { seedSql } from "../src/lib/corpus.ts";

const root = fileURLToPath(new URL("..", import.meta.url));
const bin = (p: string) => join(root, "node_modules", p);
const state = mkdtempSync(join(tmpdir(), "chord-gate-"));
const code = randomBytes(9).toString("hex");
const KEYS = "Key holder Odile Marrow, Larkspur Lane";
const OXYGEN = "Oxygen user at 7 Quarry Steps (Teodor Pike)";
let server: ChildProcess | undefined;
let base = "";

const freePort = () =>
  new Promise<number>((resolve) => {
    const s = createServer().listen(0, "127.0.0.1", () => {
      const { port } = s.address() as { port: number };
      s.close(() => resolve(port));
    });
  });
const run = (script: string, ...args: string[]) =>
  execFileSync(process.execPath, [bin(script), ...args], { cwd: root, stdio: "inherit", timeout: 600_000, env: { ...process.env, CI: "1" } });

before(async () => {
  run("vite/bin/vite.js", "build");
  writeFileSync(join(state, "seed.sql"), seedSql(JSON.parse(readFileSync(join(root, "fixtures/demo-corpus.json"), "utf8"))));
  run("wrangler/bin/wrangler.js", "d1", "migrations", "apply", "DB", "--local", "--persist-to", state);
  run("wrangler/bin/wrangler.js", "d1", "execute", "DB", "--local", "--persist-to", state, `--file=${join(state, "seed.sql")}`);
  const [port, inspector] = [await freePort(), await freePort()];
  base = `http://127.0.0.1:${port}`;
  server = spawn(process.execPath, [
    bin("wrangler/bin/wrangler.js"), "dev", "--config", "dist/server/wrangler.json", "--persist-to", state,
    "--ip", "127.0.0.1", "--port", String(port), "--inspector-port", String(inspector), "--show-interactive-dev-session=false",
    "--var", `SESSION_SECRET:${randomBytes(32).toString("hex")}`, "--var", `HUB_COORDINATOR_CODE:${code}`,
  ], { cwd: root, stdio: "inherit", env: { ...process.env, CI: "1" } });
  for (const deadline = Date.now() + 300_000; ; await new Promise((r) => setTimeout(r, 1000))) {
    if (Date.now() > deadline) throw new Error("wrangler dev was not ready within 300 s");
    if (await fetch(base + "/").then((r) => r.ok, () => false)) break;
  }
});

after(() => {
  if (server?.pid !== undefined) {
    if (process.platform === "win32") execFileSync("taskkill", ["/pid", String(server.pid), "/T", "/F"], { stdio: "ignore" });
    else server.kill("SIGKILL");
  }
  rmSync(state, { recursive: true, force: true, maxRetries: 5, retryDelay: 1000 });
});

type Jar = { cookie: string };
const seen: Response[] = [];
async function call(path: string, jar: Jar | null, method = "GET", origin: string | null = base, body = "") {
  const headers: Record<string, string> = jar?.cookie ? { cookie: jar.cookie } : {};
  if (method === "POST") Object.assign(headers, { "content-type": "application/x-www-form-urlencoded" }, origin ? { origin } : {});
  const res = await fetch(base + path, { method, headers, redirect: "manual", body: method === "POST" ? body : undefined });
  const set = res.headers.get("set-cookie");
  if (jar && set) jar.cookie = set.split(";")[0].endsWith("=") ? "" : set.split(";")[0];
  seen.push(res);
  return { status: res.status, text: await res.text() };
}

const A: Jar = { cookie: "" };
const B: Jar = { cookie: "" };
const AT = "?at=2026-11-26T12:00:00Z";
const GETS = ["/", `/hub/hub-ferncliff${AT}`, `/hub/hub-larkhollow${AT}`, `/hub/hub-ferncliff/print${AT}`, `/hub/hub-larkhollow/print${AT}`];

test("jar A unlocks and sees the restricted assets; jar B and every GET route stay public", async () => {
  const before = await Promise.all(GETS.map(async (p) => (await call(p, B)).text));
  const unlocked = await call("/api/unlock", A, "POST", base, `code=${code}`);
  const forA = await call("/", A);
  const forAHub = await call(`/hub/hub-larkhollow${AT}`, A);
  const after = await Promise.all(GETS.map(async (p) => (await call(p, B)).text));
  const tampered = { cookie: A.cookie.slice(0, -1) + (A.cookie.endsWith("A") ? "B" : "A") };
  const leaks = [...before, ...after, (await call("/", tampered)).text].filter((t) => t.includes(KEYS) || t.includes(OXYGEN));
  assert.deepEqual(
    [unlocked.status, forA.text.includes(KEYS), forAHub.text.includes(OXYGEN), (await call("/", B)).text.includes("Rainwater tank behind the hall"), leaks.length],
    [303, true, true, true, 0],
  );
});

test("a foreign or missing Origin gets 403 on every state-changing route, even with a session", async () => {
  const routes = ["/api/unlock", "/api/lock", "/api/feeds/fict-river-watch/pause", "/api/feeds/fict-river-watch/resume", "/api/fixtures/step"];
  const foreign = await Promise.all(routes.map(async (r) => (await call(r, { ...A }, "POST", "http://evil.example", `code=${code}`)).status));
  const missing = await Promise.all(routes.map(async (r) => (await call(r, { ...A }, "POST", null, `code=${code}`)).status));
  assert.deepEqual([foreign, missing], [routes.map(() => 403), routes.map(() => 403)]);
});

test("pause, resume and step without a session get 401; with a session they act", async () => {
  const paths = ["/api/fixtures/step", "/api/feeds/fict-river-watch/pause", "/api/feeds/fict-river-watch/resume"];
  const anonymous = [];
  for (const p of paths) anonymous.push((await call(p, B, "POST")).status);
  const acted = [];
  for (const p of paths) acted.push(await call(p, A, "POST"));
  const unknown = await call("/api/feeds/no-such-feed/pause", A, "POST");
  const badAction = await call("/api/feeds/fict-river-watch/delete", A, "POST");
  assert.deepEqual(
    [anonymous, acted.map((r) => [r.status, JSON.parse(r.text)]), unknown.status, badAction.status],
    [[401, 401, 401], [[200, { cursor: 1 }], [200, { id: "fict-river-watch", state: "paused" }], [200, { id: "fict-river-watch", state: "running" }]], 404, 404],
  );
});

test("Ask, contacts and raw seed paths return 404", async () => {
  const paths = ["/api/ask", "/api/v1/hub/ask", "/?contacts=1", "/?contacts=yes", `/hub/hub-ferncliff?contacts=1`, "/api/v1/hub/needs-offers?contacts=1", "/seed", "/seed.json", "/api/v1/seed", "/demo-seed-data-v0.3.json"];
  const statuses = [];
  for (const p of paths) statuses.push((await call(p, A)).status);
  assert.deepEqual(statuses, paths.map(() => 404));
});

test("POST /api/lock ends A's session", async () => {
  const old = { ...A };
  const locked = await call("/api/lock", A, "POST");
  assert.deepEqual([locked.status, A.cookie, (await call("/", old)).text.includes(KEYS)], [303, "", false]);
});

test("responses that vary by view send Cache-Control: private, no-store and no response sends Access-Control-Allow-Origin", () => {
  const varying = seen.filter((r) => r.status !== 404 && new URL(r.url).pathname !== "/favicon.ico");
  const missing = varying.filter((r) => !/\bprivate\b/.test(r.headers.get("cache-control") ?? "") || !/\bno-store\b/.test(r.headers.get("cache-control") ?? ""));
  const cors = seen.filter((r) => r.headers.has("access-control-allow-origin"));
  assert.deepEqual([varying.length > 20, missing.map((r) => `${r.status} ${r.url}`), cors.length], [true, [], 0]);
});
