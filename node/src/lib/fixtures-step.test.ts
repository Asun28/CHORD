import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { env } from "./app-loader.ts";
import { asD1, seededDb } from "./sqlite-fixture.ts";
import { createStore } from "../server/store.ts";

const { POST } = await import("../app/api/fixtures/step/route.ts");
const { POST: unlock } = await import("../app/api/unlock/route.ts");
const code = randomBytes(9).toString("hex");
let cookie = "";
const post = (route: (r: Request) => Promise<Response>, body = "") =>
  route(new Request("http://localhost/api/x", { method: "POST", body, headers: { origin: "http://localhost", cookie, "content-type": "application/x-www-form-urlencoded" } }));
const step = () => post(POST);
// The node's D1 has migrations 0001 and 0002; seededDb applies 0001 only.
const clientKeys = readFileSync(new URL("../../migrations/0002_unlock_client.sql", import.meta.url), "utf8");
const migratedDb = () => {
  const db = seededDb();
  db.exec(clientKeys);
  return asD1(db);
};

// A fresh seeded DB and a coordinator session on it: the step route refuses requests without one.
async function unlocked(): Promise<void> {
  Object.assign(env, { DB: migratedDb(), SESSION_SECRET: randomBytes(32).toString("hex"), HUB_COORDINATOR_CODE: code });
  cookie = "";
  cookie = ((await post(unlock, `code=${code}`)).headers.get("set-cookie") ?? "").split(";")[0];
}

test("POST /api/fixtures/step applies the next fixture file per call and returns the new cursor", async () => {
  await unlocked();
  const store = createStore(env.DB!);
  const steps = [];
  for (let i = 0; i < 3; i++) {
    const res = await step();
    steps.push([res.status, await res.json(), (await store.activeAt("2026-11-26T12:00:00Z")).map((o) => o.identifier).sort()]);
  }
  assert.deepEqual(steps, [
    [200, { cursor: 1 }, ["frw-0001"]],
    [200, { cursor: 2 }, ["frw-0002"]],
    [200, { cursor: 2 }, ["frw-0002"]],
  ]);
});

test("two overlapping POST /api/fixtures/step calls each apply one fixture file", async () => {
  await unlocked();
  const store = createStore(env.DB!);
  const bodies = await Promise.all([step(), step()].map(async (r) => (await (await r).json()) as { cursor: number }));
  const active = (await store.activeAt("2026-11-26T12:00:00Z")).map((o) => o.identifier);
  assert.deepEqual([bodies.map((b) => b.cursor).sort(), await store.fixtureCursor(), active], [[1, 2], 2, ["frw-0002"]]);
});

test("a stale step cannot move the fixture cursor back or skip a file", async () => {
  await unlocked();
  const store = createStore(env.DB!);
  const skipped = await store.advanceFixtureCursor(1);
  await step();
  await step();
  const stale = await store.advanceFixtureCursor(0);
  assert.deepEqual([skipped, stale, await store.fixtureCursor()], [false, false, 2]);
});
