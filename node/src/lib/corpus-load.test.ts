import { test } from "node:test";
import assert from "node:assert/strict";
import { demoCorpus, seededDb } from "./sqlite-fixture.ts";

const tables = [
  "source", "observation", "pending_reference", "hub", "hub_asset",
  "role", "task_template", "feed_state", "unlock_attempt",
];

test("migration creates the plan section 5 tables", () => {
  const db = seededDb();
  const names = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all().map((r) => r.name);
  for (const t of tables) assert.ok(names.includes(t), t);
});

test("seed loads every hub, asset, role and task template of the fixture", () => {
  const db = seededDb();
  const count = (table: string) => (db.prepare(`SELECT count(*) AS n FROM ${table}`).get() as { n: number }).n;
  assert.deepEqual(
    { hub: count("hub"), hub_asset: count("hub_asset"), role: count("role"), task_template: count("task_template") },
    {
      hub: demoCorpus.hubs.length,
      hub_asset: demoCorpus.assets.length,
      role: demoCorpus.roles.length,
      task_template: demoCorpus.task_templates.length,
    },
  );
});

test("migration rejects rows that break the schema constraints", () => {
  const db = seededDb();
  db.exec("INSERT INTO source (id, name, cadence_seconds) VALUES ('s1', 'Fictional feed', 300)");
  const obs = "INSERT INTO observation (source_id, cap_identifier, msg_type, cap_json, sent_at, observed_at, fetched_at)";
  db.exec(`${obs} VALUES ('s1', 'cap-1', 'alert', '{}', 't', 't', 't')`);
  const invalid = {
    "asset sensitivity outside public/restricted":
      "INSERT INTO hub_asset (id, hub_id, kind, name, sensitivity) VALUES ('x', 'hub-ferncliff', 'k', 'n', 'secret')",
    "second message with the same source and CAP identifier": `${obs} VALUES ('s1', 'cap-1', 'alert', '{}', 't', 't', 't')`,
    "message type outside alert/update/cancel": `${obs} VALUES ('s1', 'cap-2', 'ack', '{}', 't', 't', 't')`,
    "feed state outside running/paused": "INSERT INTO feed_state (source_id, state, changed_at) VALUES ('s1', 'stopped', 't')",
  };
  for (const [name, sql] of Object.entries(invalid)) assert.throws(() => db.exec(sql), /constraint/i, name);
});

test("seed stores each fixture hub's lat and lon", () => {
  const rows = seededDb().prepare("SELECT id, lat, lon FROM hub ORDER BY id").all();
  const expected = demoCorpus.hubs.map(({ id, lat, lon }) => ({ id, lat, lon })).sort((a, b) => a.id.localeCompare(b.id));
  assert.deepEqual(rows.map((r) => ({ ...r })), expected);
});
