import { test } from "node:test";
import assert from "node:assert/strict";
import { demoCorpus } from "./sqlite-fixture.ts";

test("demo corpus is flagged fictional at the top level", () => {
  assert.equal(demoCorpus.fictional, true);
});

test("demo corpus has at least one restricted asset", () => {
  assert.ok(demoCorpus.assets.some((a) => a.sensitivity === "restricted"));
});

test("demo corpus holds the 8 role codes", () => {
  assert.equal(new Set(demoCorpus.roles.map((r) => r.code)).size, 8);
});

test("every task template has a source_ref", () => {
  assert.ok(demoCorpus.task_templates.length > 0);
  for (const t of demoCorpus.task_templates) assert.ok(t.source_ref.trim().length > 0, t.id);
});

test("the home hub is one of the hubs", () => {
  assert.ok(demoCorpus.hubs.some((h) => h.id === demoCorpus.home_hub_id));
});
