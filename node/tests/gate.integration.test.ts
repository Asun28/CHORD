// Builds the node, runs it under wrangler dev on a fresh local D1, and drives it with two cookie jars;
// then checks the proxy rules (contacts 404, private cache) under vite dev as well.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
// vite dev takes its config from a file; this copy (in the gitignored .wrangler/) adds only a separate
// persisted D1 for the test.
const devConfig = join(root, ".wrangler", `gate-vite-${process.pid}.config.mjs`);
const servers: ChildProcess[] = [];
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

// A fresh local D1 in its own directory under `state`, migrated (0001, 0002) and seeded.
function freshDb(name: string): string {
  const dir = join(state, name);
  mkdirSync(dir);
  writeFileSync(join(dir, "seed.sql"), seedSql(JSON.parse(readFileSync(join(root, "fixtures/demo-corpus.json"), "utf8"))));
  run("wrangler/bin/wrangler.js", "d1", "migrations", "apply", "DB", "--local", "--persist-to", dir);
  run("wrangler/bin/wrangler.js", "d1", "execute", "DB", "--local", "--persist-to", dir, `--file=${join(dir, "seed.sql")}`);
  return dir;
}

// Starts a server process, waits until GET / answers 200, and returns its base URL.
async function serve(args: (port: number) => Promise<string[]>): Promise<string> {
  const port = await freePort();
  const child = spawn(process.execPath, await args(port), { cwd: root, stdio: "inherit", env: { ...process.env, CI: "1" } });
  servers.push(child);
  const url = `http://127.0.0.1:${port}`;
  for (const deadline = Date.now() + 300_000; ; await new Promise((r) => setTimeout(r, 1000))) {
    if (Date.now() > deadline) throw new Error(`${url} was not ready within 300 s`);
    if (await fetch(url + "/").then((r) => r.ok, () => false)) return url;
  }
}

const worker = (dir: string, ...vars: string[]) => async (port: number) => [
  bin("wrangler/bin/wrangler.js"), "dev", "--config", "dist/server/wrangler.json", "--persist-to", dir,
  "--ip", "127.0.0.1", "--port", String(port), "--inspector-port", String(await freePort()), "--show-interactive-dev-session=false",
  "--var", `SESSION_SECRET:${randomBytes(32).toString("hex")}`, "--var", `HUB_COORDINATOR_CODE:${code}`,
  ...vars.flatMap((v) => ["--var", v]),
];

before(async () => {
  run("vite/bin/vite.js", "build");
  base = await serve(worker(freshDb("worker")));
});

after(() => {
  for (const child of servers) {
    if (child.pid === undefined) continue;
    if (process.platform === "win32") execFileSync("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore" });
    else child.kill("SIGKILL");
  }
  rmSync(state, { recursive: true, force: true, maxRetries: 5, retryDelay: 1000 });
  rmSync(devConfig, { force: true });
});

type Jar = { cookie: string };
const seen: Response[] = [];
async function call(path: string, jar: Jar | null, method = "GET", origin: string | null = base, body = "", extra: Record<string, string> = {}) {
  const headers: Record<string, string> = { ...extra, ...(jar?.cookie ? { cookie: jar.cookie } : {}) };
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

// An RSC request: vinext first answers 307 to add its `_rsc` cache-busting query (a redirect with no
// view content), then serves the Flight payload, which goes into `seen` for the cache check.
async function rsc(url: string, jar: Jar): Promise<{ status: number; text: string }> {
  const res = await fetch(url, { headers: { RSC: "1", ...(jar.cookie ? { cookie: jar.cookie } : {}) } });
  seen.push(res);
  return { status: res.status, text: await res.text() };
}

test("an RSC request for the home page carries the coordinator view only for A", async () => {
  const [forA, forB] = [await rsc(base + "/", A), await rsc(base + "/", B)];
  assert.deepEqual([forA.status, forA.text.includes(KEYS), forB.status, forB.text.includes(KEYS)], [200, true, 200, false]);
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
  const paths = ["/api/ask", "/api/v1/hub/ask", "/?contacts=1", "/?contacts=yes", `/hub/hub-ferncliff?contacts=1`, "/api/v1/hub/needs-offers?contacts=1",
    "/seed", "/seed.json", "/api/v1/seed", "/demo-seed-data-v0.3.json", "/favicon.ico?contacts=1", "/no-such-path?contacts=1"];
  const statuses = [];
  for (const p of paths) statuses.push((await call(p, A)).status);
  const posts = ["/api/unlock", "/api/lock", "/api/feeds/fict-river-watch/pause", "/api/feeds/fict-river-watch/resume", "/api/fixtures/step"];
  for (const p of posts) {
    for (const method of ["GET", "POST", "PUT", "DELETE"]) statuses.push((await call(`${p}?contacts=1`, { ...A }, method, base, `code=${code}`)).status);
  }
  assert.deepEqual(statuses, [...paths, ...posts.flatMap((p) => [p, p, p, p])].map(() => 404));
});

test("POST /api/lock ends A's session", async () => {
  const old = { ...A };
  const locked = await call("/api/lock", A, "POST");
  assert.deepEqual([locked.status, A.cookie, (await call("/", old)).text.includes(KEYS)], [303, "", false]);
});

test("responses that vary by view send Cache-Control: private, no-store and no response sends Access-Control-Allow-Origin", () => {
  const varying = seen.filter((r) => r.status !== 404);
  const missing = varying.filter((r) => !/\bprivate\b/.test(r.headers.get("cache-control") ?? "") || !/\bno-store\b/.test(r.headers.get("cache-control") ?? ""));
  const cors = seen.filter((r) => r.headers.has("access-control-allow-origin"));
  assert.deepEqual([varying.length > 20, missing.map((r) => `${r.status} ${r.url}`), cors.length], [true, [], 0]);
});

const unlockAs = (url: string, ip: string, c: string) =>
  fetch(`${url}/api/unlock`, {
    method: "POST", redirect: "manual", body: `code=${c}`,
    headers: { origin: url, "content-type": "application/x-www-form-urlencoded", "cf-connecting-ip": ip },
  }).then((r) => r.status);

test("without TRUST_CF_CONNECTING_IP, a caller rotating CF-Connecting-IP gets 429 on its sixth failure", async () => {
  const statuses = [];
  for (let i = 0; i < 6; i++) statuses.push(await unlockAs(base, `203.0.113.${i}`, "wrong"));
  assert.deepEqual(statuses, [401, 401, 401, 401, 401, 429]);
});

test("with TRUST_CF_CONNECTING_IP set, client A's failures do not block client B", async () => {
  const trusted = await serve(worker(freshDb("trusted"), "TRUST_CF_CONNECTING_IP:1"));
  const statuses = [];
  for (let i = 0; i < 6; i++) statuses.push(await unlockAs(trusted, "203.0.113.1", "wrong"));
  statuses.push(await unlockAs(trusted, "203.0.113.2", code), await unlockAs(trusted, "203.0.113.1", code));
  assert.deepEqual(statuses, [401, 401, 401, 401, 401, 429, 303, 429]);
});

// Requests from the node's own origin (by IP and by name) and a foreign origin to a page, an RSC request,
// an API route (GET and a CORS preflight) and a metadata file; returns each response that carries
// Access-Control-Allow-Origin, and the statuses, which show every request reached the server.
async function corsProbe(url: string): Promise<{ withAcao: string[]; statuses: number[] }> {
  const origins = [url, url.replace("127.0.0.1", "localhost"), "http://evil.example"];
  const requests: [string, RequestInit][] = [
    ["/", {}],
    ["/", { headers: { RSC: "1" } }],
    ["/api/unlock", {}],
    ["/api/unlock", { method: "OPTIONS", headers: { "Access-Control-Request-Method": "POST" } }],
    ["/favicon.ico", {}],
  ];
  const withAcao = [];
  const statuses = [];
  for (const origin of origins) {
    for (const [path, init] of requests) {
      const res = await fetch(url + path, { ...init, headers: { ...(init.headers as Record<string, string>), origin } });
      await res.arrayBuffer();
      statuses.push(res.status);
      if (res.headers.has("access-control-allow-origin")) withAcao.push(`${init.method ?? "GET"} ${path} from ${origin}`);
    }
  }
  return { withAcao, statuses };
}

// Page, RSC, API GET (405), preflight (405) and favicon, for each of the three origins.
const PROBE_STATUSES = [200, 200, 405, 405, 200, 200, 200, 405, 405, 200, 200, 200, 405, 405, 200];

test("the built Worker sends no Access-Control-Allow-Origin to its own or a foreign origin", async () => {
  assert.deepEqual(await corsProbe(base), { withAcao: [], statuses: PROBE_STATUSES });
});

describe("vite dev", () => {
  let dev = "";
  before(async () => {
    const dir = freshDb("dev");
    // The repository config with one change: the Cloudflare plugin persists D1 in `dir`. Its server
    // settings and every other plugin (the no-CORS hook included) are taken from it unchanged.
    writeFileSync(devConfig, [
      `import { defineConfig } from "vite";`,
      `import { cloudflare } from "@cloudflare/vite-plugin";`,
      `import app from "../vite.config.ts";`,
      `const persisted = cloudflare({ viteEnvironment: { name: "rsc", childEnvironments: ["ssr"] }, persistState: { path: ${JSON.stringify(dir)} } });`,
      `const isCloudflare = (p) => [p].flat(Infinity).some((q) => q && String(q.name).startsWith("vite-plugin-cloudflare"));`,
      `export default defineConfig({ ...app, root: ${JSON.stringify(root)}, plugins: [...app.plugins.filter((p) => !isCloudflare(p)), persisted] });`,
    ].join("\n"));
    dev = await serve(async (port) => [bin("vite/bin/vite.js"), "dev", "--config", devConfig, "--host", "127.0.0.1", "--port", String(port), "--strictPort"]);
  });

  test("pages and an RSC request send Cache-Control: private, no-store", async () => {
    const urls = [`${dev}/`, `${dev}/hub/hub-ferncliff${AT}`];
    const res = await Promise.all([...urls.map((u) => fetch(u)), fetch(urls[0], { headers: { RSC: "1" } })]);
    const cache = (r: Response) => [r.status, r.headers.get("cache-control")];
    assert.deepEqual(res.map(cache).map(([s, c]) => [s, /\bprivate\b/.test(String(c)) && /\bno-store\b/.test(String(c))]), [[200, true], [200, true], [200, true]]);
  });

  test("vite dev sends no Access-Control-Allow-Origin to its own or a foreign origin", async () => {
    // vinext's dev origin check answers 403 to the foreign origin before any route runs.
    assert.deepEqual(await corsProbe(dev), { withAcao: [], statuses: [...PROBE_STATUSES.slice(0, 10), 403, 403, 403, 403, 403] });
  });

  test("any path with a contacts parameter returns 404", async () => {
    const paths = ["/?contacts=1", "/favicon.ico?contacts=1", "/no-such-path?contacts=1", "/hub/hub-ferncliff?contacts=1", "/api/unlock?contacts=1", "/api/fixtures/step?contacts=1"];
    const statuses = [];
    for (const p of paths) {
      for (const method of ["GET", "POST"]) statuses.push((await fetch(dev + p, { method, headers: { origin: dev } })).status);
    }
    assert.deepEqual(statuses, paths.flatMap(() => [404, 404]));
  });
});
