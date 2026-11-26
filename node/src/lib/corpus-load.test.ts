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
