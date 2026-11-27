import { test } from "node:test";
import assert from "node:assert/strict";
import { env } from "./app-loader.ts";
import { asD1, seededDb } from "./sqlite-fixture.ts";
import { createStore } from "../server/store.ts";

const { POST } = await import("../app/api/fixtures/step/route.ts");

test("POST /api/fixtures/step applies the next fixture file per call and returns the new cursor", async () => {
  env.DB = asD1(seededDb());
  const store = createStore(env.DB);
  const steps = [];
  for (let i = 0; i < 3; i++) {
    const res = await POST();
    steps.push([res.status, await res.json(), (await store.activeAt("2026-11-26T12:00:00Z")).map((o) => o.identifier).sort()]);
  }
  assert.deepEqual(steps, [
    [200, { cursor: 1 }, ["frw-0001"]],
    [200, { cursor: 2 }, ["frw-0002"]],
    [200, { cursor: 2 }, ["frw-0002"]],
  ]);
});
