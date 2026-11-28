// Builds the node into its own directory (the gate suite builds dist/ at the same time), then reads the
// board and the print page under the built Worker (wrangler dev) and under vite dev, each on a working
// local D1 and on one whose observation table is gone.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createHmac, randomBytes } from "node:crypto";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { seedSql, type Corpus } from "../src/lib/corpus.ts";

const root = fileURLToPath(new URL("..", import.meta.url));
const bin = (p: string) => join(root, "node_modules", p);
const state = mkdtempSync(join(tmpdir(), "chord-print-"));
const out = join(state, "dist");
const code = randomBytes(9).toString("hex");
const secret = randomBytes(32).toString("hex");
const corpus: Corpus = JSON.parse(readFileSync(join(root, "fixtures/demo-corpus.json"), "utf8"));
const RESTRICTED = corpus.assets.filter((a) => a.sensitivity === "restricted").map((a) => a.name);
const AT = "2026-11-26T10:30:00Z";
const SENT = "2026-11-26T10:00:00.000Z"; // fixtures/feeds/01-flood-warning.json, the one fact active at AT
const BANNER = "Store error";
const POSTURE_WORD = /\b(green|watch|act|respond)\b/i;
const configs: string[] = [];
const servers: ChildProcess[] = [];

const freePort = () =>
  new Promise<number>((resolve) => {
    const s = createServer().listen(0, "127.0.0.1", () => {
      const { port } = s.address() as { port: number };
      s.close(() => resolve(port));
    });
  });
const run = (script: string, ...args: string[]) =>
  execFileSync(process.execPath, [bin(script), ...args], { cwd: root, stdio: "inherit", timeout: 600_000, env: { ...process.env, CI: "1" } });

// A vite config in the gitignored .wrangler/ that imports the repository config and changes only `extra`.
function config(name: string, lines: string[]): string {
  const file = join(root, ".wrangler", `print-${name}-${process.pid}.config.mjs`);
  mkdirSync(join(root, ".wrangler"), { recursive: true });
  writeFileSync(file, [`import { defineConfig } from "vite";`, `import { cloudflare } from "@cloudflare/vite-plugin";`, `import app from "../vite.config.ts";`, ...lines].join("\n"));
  configs.push(file);
  return file;
}

// A fresh local D1, migrated and seeded once; each server gets a copy of it.
const migrated = join(state, "migrated");
function freshDb(): void {
  mkdirSync(migrated);
  writeFileSync(join(state, "seed.sql"), seedSql(corpus));
  run("wrangler/bin/wrangler.js", "d1", "migrations", "apply", "DB", "--local", "--persist-to", migrated);
  run("wrangler/bin/wrangler.js", "d1", "execute", "DB", "--local", "--persist-to", migrated, `--file=${join(state, "seed.sql")}`);
}

// A copy of the migrated D1; `broken` drops the observation and unlock_attempt tables from its SQLite file, so
// no fact and no coordinator session can be read.
function copyDb(name: string, broken: boolean): string {
  const dir = join(state, name);
  cpSync(migrated, dir, { recursive: true });
  if (broken) {
    const files = join(dir, "v3", "d1", "miniflare-D1DatabaseObject");
    const db = new DatabaseSync(join(files, readdirSync(files).find((f) => f.endsWith(".sqlite"))!));
    db.exec("DROP TABLE pending_reference; DROP TABLE observation; DROP TABLE unlock_attempt;");
    db.close();
  }
  return dir;
}

async function serve(args: (port: number) => Promise<string[]>): Promise<string> {
  const port = await freePort();
  const child = spawn(process.execPath, await args(port), { cwd: root, stdio: "inherit", env: { ...process.env, CI: "1" } });
  servers.push(child);
  const url = `http://127.0.0.1:${port}`;
  for (const deadline = Date.now() + 300_000; ; await new Promise((r) => setTimeout(r, 1000))) {
    if (Date.now() > deadline) throw new Error(`${url} was not ready within 300 s`);
    if (child.exitCode !== null) throw new Error(`the server for ${url} exited with code ${child.exitCode}`);
    if (await fetch(url + "/").then((r) => r.ok, () => false)) return url;
  }
}

const worker = (dir: string) => async (port: number) => [
  bin("wrangler/bin/wrangler.js"), "dev", "--config", join(out, "server", "wrangler.json"), "--persist-to", dir,
  "--ip", "127.0.0.1", "--port", String(port), "--inspector-port", String(await freePort()), "--show-interactive-dev-session=false",
  "--var", `SESSION_SECRET:${secret}`, "--var", `HUB_COORDINATOR_CODE:${code}`,
];

// vite dev with the repository config, its D1 persisted in `dir`, the session vars set, its own deps cache
// and no inspector port, so it can run beside the gate suite's vite dev.
const dev = (name: string, dir: string) => async (port: number) => {
  const file = config(`dev-${name}`, [
    `const persisted = cloudflare({ viteEnvironment: { name: "rsc", childEnvironments: ["ssr"] }, persistState: { path: ${JSON.stringify(dir)} }, inspectorPort: false,`,
    `  config: { vars: { SESSION_SECRET: ${JSON.stringify(secret)}, HUB_COORDINATOR_CODE: ${JSON.stringify(code)} } } });`,
    `const isCloudflare = (p) => [p].flat(Infinity).some((q) => q && String(q.name).startsWith("vite-plugin-cloudflare"));`,
    `export default defineConfig({ ...app, root: ${JSON.stringify(root)}, cacheDir: ${JSON.stringify(join(state, `vite-${name}`))}, plugins: [...app.plugins.filter((p) => !isCloudflare(p)), persisted] });`,
  ]);
  return [bin("vite/bin/vite.js"), "dev", "--config", file, "--host", "127.0.0.1", "--port", String(port), "--strictPort"];
};

const runtimes: Record<"worker" | "vite dev", { good: string; broken: string }> = {
  worker: { good: "", broken: "" },
  "vite dev": { good: "", broken: "" },
};

before(async () => {
  run("vite/bin/vite.js", "build", "--config", config("build", [`export default defineConfig({ ...app, root: ${JSON.stringify(root)}, build: { outDir: ${JSON.stringify(out)} } });`]));
  freshDb();
  const dbs = ["worker", "worker-broken", "dev", "dev-broken"].map((n) => copyDb(n, n.endsWith("broken")));
  [runtimes.worker.good, runtimes.worker.broken, runtimes["vite dev"].good, runtimes["vite dev"].broken] = await Promise.all([
    serve(worker(dbs[0])), serve(worker(dbs[1])), serve(dev("good", dbs[2])), serve(dev("broken", dbs[3])),
  ]);
});

after(() => {
  // A server that already exited is skipped, and a failed taskkill does not stop the loop, so every other server is stopped.
  for (const child of servers) {
    if (child.pid === undefined || child.exitCode !== null) continue;
    if (process.platform === "win32") spawnSync("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore" });
    else child.kill("SIGKILL");
  }
  for (const file of configs) rmSync(file, { force: true });
  rmSync(state, { recursive: true, force: true, maxRetries: 5, retryDelay: 1000 });
});

const get = async (url: string, cookie = "") => (await fetch(url, { headers: cookie ? { cookie } : {} })).text();
const post = (base: string, path: string, cookie: string, body = "") =>
  fetch(base + path, { method: "POST", redirect: "manual", body, headers: { origin: base, cookie, "content-type": "application/x-www-form-urlencoded" } });
// The markup a reader sees: scripts (the RSC payload) and styles removed.
const visible = (html: string) => html.replace(/<script\b[\s\S]*?<\/script>/g, "").replace(/<style\b[\s\S]*?<\/style>/g, "");
const count = (html: string, pattern: RegExp) => (visible(html).match(pattern) ?? []).length;
// A session cookie for unlock_attempt row `id`, signed as server/session.ts signs it.
const sessionCookie = (id: number, expires: number) =>
  `chord_session=${id}.${expires}.${createHmac("sha256", secret).update(`${id}.${expires}`).digest("base64url")}`;

for (const [name, base] of Object.entries(runtimes)) {
  test(`${name}: with the observation table gone, the board and the print page show the error banner and no posture`, async () => {
    const pages = await Promise.all(["/", `/hub/hub-ferncliff?at=${AT}`, `/hub/hub-ferncliff/print?at=${AT}`].map((p) => get(base.broken + p)));
    const control = visible(await get(`${base.good}/hub/hub-ferncliff?at=${AT}`));
    assert.deepEqual(
      [pages.map((html) => [html.includes(BANNER), POSTURE_WORD.exec(visible(html))?.[0] ?? null]), POSTURE_WORD.test(control)],
      [pages.map(() => [true, null]), true],
    );
  });

  test(`${name}: a signed-in request with the store unreadable gets the error banner and no posture on the board pages`, async () => {
    const unlocked = await post(base.good, "/api/unlock", "", `code=${code}`);
    const real = (unlocked.headers.get("set-cookie") ?? "").split(";")[0];
    const [id, expires] = real.replace("chord_session=", "").split(".").map(Number);
    const cookie = sessionCookie(1, Date.now() + 600_000);
    const pages = await Promise.all(["/", `/hub/hub-ferncliff?at=${AT}`].map(async (p) => {
      const res = await fetch(base.broken + p, { headers: { cookie } });
      const html = await res.text();
      return [res.status, html.includes(BANNER), POSTURE_WORD.exec(visible(html))?.[0] ?? null];
    }));
    assert.deepEqual([sessionCookie(id, expires) === real, pages], [true, [[200, true, null], [200, true, null]]]);
  });

  test(`${name}: a cursor that names no real instant gets 404 on the board and the print page`, async () => {
    const paths = ["/?at=2026-02-30T10:00:00Z", "/hub/hub-ferncliff?at=2026-11-26T24:00:00Z", "/hub/hub-ferncliff/print?at=2026-11-26T10:00:00"];
    const statuses = await Promise.all(paths.map(async (p) => (await fetch(base.good + p)).status));
    assert.deepEqual(statuses, [404, 404, 404]);
  });

  test(`${name}: print pages for a coordinator and a public session hold no restricted name, one timestamp per fact, the render time and @page A4`, async () => {
    const unlocked = await post(base.good, "/api/unlock", "", `code=${code}`);
    const coordinator = (unlocked.headers.get("set-cookie") ?? "").split(";")[0];
    const stepped = await post(base.good, "/api/fixtures/step", coordinator);
    const sessionLive = (await get(`${base.good}/hub/hub-larkhollow?at=${AT}`, coordinator)).includes("Oxygen user at 7 Quarry Steps");
    const started = Date.now();
    const prints = [];
    for (const cookie of [coordinator, ""]) {
      for (const hub of corpus.hubs) prints.push({ hub: hub.id, html: await get(`${base.good}/hub/${hub.id}/print?at=${AT}`, cookie) });
    }
    const ended = Date.now();
    const rendered = (html: string) => Date.parse(/<time[^>]*data-rendered[^>]*dateTime="([^"]+)"/i.exec(html)?.[1] ?? "");
    const ferncliff = prints[0].html;
    assert.deepEqual(
      [
        unlocked.status, stepped.status, sessionLive,
        prints.filter(({ html }) => RESTRICTED.some((n) => html.includes(n))).map((p) => p.hub),
        prints.filter(({ html }) => !(rendered(html) >= started - 1000 && rendered(html) <= ended + 1000)).map((p) => p.hub),
        prints.filter(({ html }) => count(html, /data-fact=""/g) !== count(html, /data-observed=""/g)).map((p) => p.hub),
        prints.filter(({ html }) => !/@page\s*\{\s*size:\s*A4\b/.test(html)).map((p) => p.hub),
        [count(ferncliff, /data-fact=""/g), visible(ferncliff).includes(`dateTime="${SENT}"`) || visible(ferncliff).includes(`datetime="${SENT}"`)],
        [/data-posture="(\w+)"/.exec(ferncliff)?.[1], /data-posture="(\w+)"/.exec(prints.find((p) => p.hub === "hub-larkhollow")!.html)?.[1]],
        ferncliff.includes("Rainwater tank behind the hall"),
      ],
      [303, 200, true, [], [], [], [], [1, true], ["act", "green"], true],
    );
  });
}
