import { test } from "node:test";
import assert from "node:assert/strict";
import type { Area, Observation, ObservationReader } from "./contracts.ts";
import { hubPosture } from "./rules.ts";

const hub = { id: "hub-ferncliff", lat: -41.29, lon: 174.78 };
const around: Area = { polygon: [[174.7, -41.35], [174.85, -41.35], [174.85, -41.2], [174.7, -41.2]] };
const elsewhere: Area = { polygon: [[175.5, -40.5], [175.6, -40.5], [175.6, -40.4]] };
const cursor = "2026-11-26T12:00:00.000Z";

let n = 0;
function obs(o: Partial<Observation>): Observation {
  return {
    source: "s-a", identifier: `id-${n++}`, msgType: "alert", sent: "2026-11-26T10:00:00.000Z",
    expires: null, references: [], hazard: "flood", severity: "moderate", tier: "P2", headline: "h",
    area: around, fetchedAt: cursor, ...o,
  };
}
const minutes = (m: number) => new Date(Date.parse("2026-11-26T10:00:00.000Z") + m * 60_000).toISOString();
const reader = (list: Observation[]): ObservationReader => ({ activeAt: async () => list });
const posture = async (list: Observation[]) => (await hubPosture(reader(list), hub, cursor)).posture;

test("a lone P2 report keeps the hub green", async () => {
  assert.equal(await posture([obs({})]), "green");
});

test("two P2 sources, same hazard, overlapping area, 59 or 60 minutes apart give watch", async () => {
  const got = [await posture([obs({}), obs({ source: "s-b", sent: minutes(59) })])];
  got.push(await posture([obs({ source: "s-b", sent: minutes(60) }), obs({})]));
  assert.deepEqual(got, ["watch", "watch"]);
});

test("two P2 sources 61 minutes apart stay green", async () => {
  assert.equal(await posture([obs({}), obs({ source: "s-b", sent: minutes(61) })]), "green");
});

test("two P2 sources with different hazard types stay green", async () => {
  assert.equal(await posture([obs({}), obs({ source: "s-b", hazard: "wind", sent: minutes(5) })]), "green");
});

test("two P2 reports from the same source stay green", async () => {
  assert.equal(await posture([obs({}), obs({ sent: minutes(5) })]), "green");
});

test("a second P2 source whose area misses the hub does not corroborate", async () => {
  assert.equal(await posture([obs({}), obs({ source: "s-b", area: elsewhere, sent: minutes(5) })]), "green");
});

test("P3 reports never raise posture, even from many sources", async () => {
  const p3 = ["s-a", "s-b", "s-c"].map((source) => obs({ source, tier: "P3", severity: "extreme" }));
  assert.equal(await posture(p3), "green");
});

test("P0/P1 reports raise by severity: severe respond, moderate act, minor watch", async () => {
  const got = [];
  for (const severity of ["severe", "moderate", "minor"] as const) got.push(await posture([obs({ tier: "P1", severity })]));
  assert.deepEqual(got, ["respond", "act", "watch"]);
});

test("a P1 alert without geometry matches no hub", async () => {
  assert.equal(await posture([obs({ tier: "P0", severity: "extreme", area: null })]), "green");
});

test("a P1 alert whose polygon misses the hub keeps it green", async () => {
  assert.equal(await posture([obs({ tier: "P1", area: elsewhere })]), "green");
});

test("a Cancel message does not raise posture", async () => {
  assert.equal(await posture([obs({ tier: "P1", msgType: "cancel" })]), "green");
});

test("a store read that throws gives posture error, never green", async () => {
  const failing: ObservationReader = { activeAt: async () => { throw new Error("D1 unavailable"); } };
  assert.equal((await hubPosture(failing, hub, cursor)).posture, "error");
});

test("the situation reads the store at the requested cursor", async () => {
  let asked = "";
  await hubPosture({ activeAt: async (c) => { asked = c; return []; } }, hub, cursor);
  assert.equal(asked, cursor);
});
