import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { normalise } from "../lib/cap.ts";
import { asD1 } from "../lib/sqlite-fixture.ts";
import { createStore } from "./store.ts";

const migration = readFileSync(new URL("../../migrations/0001_init.sql", import.meta.url), "utf8");
const sources = ["s-a", "s-b"].map((id) => ({ id, name: id, cadence_seconds: 300, tier: "P1" as const }));

function openStore(file: string, fresh: boolean) {
  const db = new DatabaseSync(file);
  if (fresh) db.exec(migration);
  return { db, store: createStore(asD1(db)) };
}

async function newStore() {
  const { db, store } = openStore(join(mkdtempSync(join(tmpdir(), "chord-store-")), "d1.sqlite"), true);
  for (const s of sources) await store.addSource(s);
  return { db, store };
}

const t0 = "2026-11-26T10:00:00.000Z";
const t1 = "2026-11-26T10:30:00.000Z";
const before = (t: string) => new Date(Date.parse(t) - 1000).toISOString();
const msg = (identifier: string, extra: Record<string, unknown> = {}, source = sources[0]) =>
  normalise({ identifier, sent: t0, hazard: "flood", headline: `${identifier} headline`, ...extra }, source);

async function ids(store: ReturnType<typeof createStore>, at: string): Promise<string[]> {
  return (await store.activeAt(at)).map((o) => `${o.source}/${o.identifier}`).sort();
}

test("the same message fetched twice is stored once and the re-fetch changes nothing", async () => {
  const { store } = await newStore();
  const stored = [await store.ingest(msg("A"), "2026-11-26T23:00:00+13:00"), await store.ingest(msg("A", { headline: "changed" }), t1)];
  const active = await store.activeAt(t1);
  assert.deepEqual([stored, active.map((o) => [o.identifier, o.headline, o.fetchedAt])], [[true, false], [["A", "A headline", t0]]]);
});

test("a re-fetch of a cancelled message does not reactivate it", async () => {
  const { store } = await newStore();
  await store.ingest(msg("A"), t0);
  await store.ingest(msg("C", { msgType: "cancel", sent: t1, references: ["A"] }), t1);
  await store.ingest(msg("A"), t1);
  assert.deepEqual(await ids(store, t1), ["s-a/C"]);
});

test("a Cancel at t1 hides the original from t1 on, and a read 1s earlier still shows it", async () => {
  const { store } = await newStore();
  await store.ingest(msg("A"), t0);
  await store.ingest(msg("C", { msgType: "cancel", sent: t1, references: ["A"] }), t1);
  assert.deepEqual([await ids(store, before(t1)), await ids(store, t1)], [["s-a/A"], ["s-a/C"]]);
});

test("an Update supersedes the message it references from its sent time", async () => {
  const { store } = await newStore();
  await store.ingest(msg("A"), t0);
  await store.ingest(msg("U", { msgType: "update", sent: t1, references: ["A"] }), t1);
  assert.deepEqual([await ids(store, before(t1)), await ids(store, t1)], [["s-a/A"], ["s-a/U"]]);
});

test("an Update arriving before its target supersedes the target once the target is stored", async () => {
  const { store } = await newStore();
  await store.ingest(msg("U", { msgType: "update", sent: t1, references: ["A"] }), t0);
  await store.ingest(msg("A"), t1);
  assert.deepEqual([await ids(store, before(t1)), await ids(store, t1)], [["s-a/A"], ["s-a/U"]]);
});

test("a reference from another source supersedes nothing, before or after the target arrives", async () => {
  const { store } = await newStore();
  await store.ingest(msg("X", { msgType: "cancel", sent: t1, references: ["A"] }, sources[1]), t0);
  await store.ingest(msg("A"), t0);
  await store.ingest(msg("Y", { msgType: "cancel", sent: t1, references: ["A"] }, sources[1]), t1);
  assert.deepEqual(await ids(store, t1), ["s-a/A", "s-b/X", "s-b/Y"]);
});

test("a message is active from its sent time until it expires", async () => {
  const { store } = await newStore();
  await store.ingest(msg("A", { expires: t1 }), t0);
  const reads = [await ids(store, before(t0)), await ids(store, t0), await ids(store, before(t1)), await ids(store, t1)];
  assert.deepEqual(reads, [[], ["s-a/A"], ["s-a/A"], []]);
});

test("a read at a cursor that is not an ISO time with a zone is refused", async () => {
  const { store } = await newStore();
  for (const cursor of ["yesterday", "2026-11-26T10:00:00"]) await assert.rejects(store.activeAt(cursor), /time/, cursor);
});

test("the normaliser refuses a message it cannot parse", () => {
  const bad: Record<string, Record<string, unknown>> = {
    "no identifier": { identifier: "" }, "numeric identifier": { identifier: 7 }, "unknown msgType": { msgType: "ack" },
    "sent without zone": { sent: "2026-11-26T10:00:00" }, "impossible date": { sent: "2026-13-45T10:00:00Z" },
    "unknown severity": { severity: "big" }, "blank hazard": { hazard: " " }, "area without polygon": { area: {} },
    "references not strings": { references: [1] }, "two-point polygon": { area: { polygon: [[1, 2], [3, 4]] } },
    "non-numeric point": { area: { polygon: [[1, 2], [3, "4"], [5, 6]] } }, "three-value point": { area: { polygon: [[1, 2, 0], [3, 4], [5, 6]] } },
  };
  for (const [name, extra] of Object.entries(bad)) assert.throws(() => msg("A", extra), /CAP/, name);
});

test("the normaliser converts an offset sent time to UTC", () => {
  assert.equal(msg("A", { sent: "2026-11-26T23:00:00+13:00" }).sent, t0);
});

test("a paused feed stays paused after the database file is closed and reopened, until resumed", async () => {
  const file = join(mkdtempSync(join(tmpdir(), "chord-pause-")), "d1.sqlite");
  const first = openStore(file, true);
  await first.store.addSource(sources[0]);
  const states = [await first.store.feedState("s-a")];
  await first.store.setFeedState("s-a", "paused", t0);
  first.db.close();
  const second = openStore(file, false);
  states.push(await second.store.feedState("s-a"));
  await second.store.setFeedState("s-a", "running", t1);
  states.push(await second.store.feedState("s-a"));
  second.db.close();
  assert.deepEqual(states, ["running", "paused", "running"]);
});
