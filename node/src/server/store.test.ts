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

test("a cursor, fetch time or feed-state time naming an impossible date is refused, not rolled over", async () => {
  const { store } = await newStore();
  for (const t of ["2026-02-30T10:00:00Z", "2026-02-29T10:00:00Z", "2026-04-31T10:00:00Z", "2026-11-26T24:00:00Z"]) {
    await assert.rejects(store.activeAt(t), /CAP: bad time/, `cursor ${t}`);
    await assert.rejects(store.ingest(msg(`A-${t}`), t), /CAP: bad time/, `fetchedAt ${t}`);
    await assert.rejects(store.setFeedState("s-a", "paused", t), /CAP: bad time/, `feed state ${t}`);
  }
  assert.deepEqual([await ids(store, "2028-02-29T10:00:00Z"), await store.feedState("s-a")], [[], "running"]);
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

const t10 = "2026-11-26T10:00:00.000Z";
const t11 = "2026-11-26T11:00:00.000Z";
const t12 = "2026-11-26T12:00:00.000Z";
const chain = {
  A: msg("A", { sent: t10 }),
  U: msg("U", { msgType: "update", sent: t11, references: ["A"] }),
  C: msg("C", { msgType: "cancel", sent: t12, references: ["A", "U"] }),
};
const orders = ["AUC", "ACU", "UAC", "UCA", "CAU", "CUA"];

test("a message is superseded from the earliest Update or Cancel that references it, in every arrival order", async () => {
  const reads: Record<string, string[][]> = {};
  for (const order of orders) {
    const { store } = await newStore();
    for (const key of order) await store.ingest(chain[key as keyof typeof chain], t12);
    reads[order] = [await ids(store, before(t11)), await ids(store, t11), await ids(store, before(t12)), await ids(store, t12)];
  }
  const expected = [["s-a/A"], ["s-a/U"], ["s-a/U"], ["s-a/C"]];
  assert.deepEqual(reads, Object.fromEntries(orders.map((o) => [o, expected])));
});

test("an Alert that carries references supersedes nothing, before or after its target arrives", async () => {
  const alertB = msg("B", { sent: t1, references: ["A"] });
  const reads = [];
  for (const first of [true, false]) {
    const { store } = await newStore();
    if (first) await store.ingest(alertB, t0);
    await store.ingest(msg("A"), t0);
    if (!first) await store.ingest(alertB, t1);
    reads.push(await ids(store, t1));
  }
  assert.deepEqual(reads, [["s-a/A", "s-a/B"], ["s-a/A", "s-a/B"]]);
});

// A database whose `failAt`-th prepared statement after `arm` throws, until `disarm`: the D1 boundary failing mid-ingest.
function failingStore(failAt: number) {
  const db = new DatabaseSync(join(mkdtempSync(join(tmpdir(), "chord-fail-")), "d1.sqlite"));
  db.exec(migration);
  let prepared = -1;
  const failing = new Proxy(db, {
    get(target, key) {
      if (key === "prepare") {
        return (sql: string) => {
          if (prepared >= 0 && ++prepared === failAt) throw new Error("injected D1 failure");
          return target.prepare(sql);
        };
      }
      const value = Reflect.get(target, key) as unknown;
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  return { store: createStore(asD1(failing)), arm: () => { prepared = 0; }, disarm: () => { prepared = -1; } };
}

test("an ingest that fails part way leaves a retry with the same final state as an ingest that never failed", async () => {
  const cancel = msg("C", { msgType: "cancel", sent: t1, references: ["A"] });
  const scenarios: Record<string, [ReturnType<typeof msg>, ReturnType<typeof msg>]> = {
    "target first": [msg("A"), cancel],
    "cancel first": [cancel, msg("A")],
  };
  const finals: Record<string, string[][]> = {};
  for (const [name, [first, second]] of Object.entries(scenarios)) {
    for (let failAt = 1; failAt <= 6; failAt++) {
      const { store, arm, disarm } = failingStore(failAt);
      for (const s of sources) await store.addSource(s);
      await store.ingest(first, t0);
      arm();
      await store.ingest(second, t1).catch(() => false);
      disarm();
      await store.ingest(second, t1);
      finals[`${name} / statement ${failAt} fails`] = [await ids(store, before(t1)), await ids(store, t1)];
    }
  }
  const expected = Object.fromEntries(Object.keys(finals).map((k) => [k, [["s-a/A"], ["s-a/C"]]]));
  assert.deepEqual(finals, expected);
});
