import { test } from "node:test";
import assert from "node:assert/strict";
import type { Corpus } from "./corpus.ts";
import { demoCorpus } from "./sqlite-fixture.ts";

// The eight hub roles named in the planning corpus (ingest_wremo.py ROLES).
const roleCodes = [
  "hub_supervisor", "information_coord", "public_information", "reception",
  "needs_and_offers", "community_space", "communications", "facility_maintenance",
];

type Kind = "string" | "rank" | "sensitivity";
const required: Record<"hubs" | "assets" | "roles" | "task_templates", Record<string, Kind>> = {
  hubs: { id: "string", name: "string", suburb: "string", address: "string" },
  assets: { id: "string", hub_id: "string", kind: "string", name: "string", sensitivity: "sensitivity" },
  roles: { code: "string", name: "string", description: "string", priority_rank: "rank", source_ref: "string" },
  task_templates: { id: "string", role_code: "string", phase: "string", text: "string", source_ref: "string" },
};

function fits(kind: Kind, v: unknown): boolean {
  if (kind === "rank") return Number.isInteger(v) && (v as number) >= 1;
  if (kind === "sensitivity") return v === "public" || v === "restricted";
  return typeof v === "string" && v.trim().length > 0;
}

// Every required field that is missing or of the wrong type, as "<collection>[<i>].<field>".
function shapeErrors(corpus: Corpus): string[] {
  const errors: string[] = [];
  for (const [collection, fields] of Object.entries(required)) {
    const rows = (corpus as unknown as Record<string, Record<string, unknown>[]>)[collection];
    if (!Array.isArray(rows) || rows.length === 0) errors.push(`${collection} is not a non-empty array`);
    else rows.forEach((row, i) => {
      for (const [field, kind] of Object.entries(fields)) if (!fits(kind, row[field])) errors.push(`${collection}[${i}].${field}`);
    });
  }
  return errors;
}

test("demo corpus is flagged fictional at the top level", () => {
  assert.equal(demoCorpus.fictional, true);
});

test("demo corpus has at least one restricted asset", () => {
  assert.ok(demoCorpus.assets.some((a) => a.sensitivity === "restricted"));
});

test("demo corpus holds the 8 role codes", () => {
  assert.equal(new Set(demoCorpus.roles.map((r) => r.code)).size, 8);
});

test("demo corpus holds exactly the 8 hub role codes", () => {
  assert.deepEqual(demoCorpus.roles.map((r) => r.code).sort(), [...roleCodes].sort());
});

test("every task template names one of the 8 role codes", () => {
  for (const t of demoCorpus.task_templates) assert.ok(roleCodes.includes(t.role_code), t.id);
});

test("every hub, asset, role and task template has its required fields with the required types", () => {
  assert.deepEqual(shapeErrors(demoCorpus), []);
});

test("the shape check reports a malformed required field in each collection", () => {
  const broken: Corpus = {
    ...demoCorpus,
    hubs: [{ ...demoCorpus.hubs[0], name: 7 as never }],
    assets: [{ ...demoCorpus.assets[0], sensitivity: "secret" as never }],
    roles: [{ ...demoCorpus.roles[0], priority_rank: "1" as never }],
    task_templates: [{ ...demoCorpus.task_templates[0], source_ref: undefined as never }],
  };
  assert.deepEqual(shapeErrors(broken), [
    "hubs[0].name", "assets[0].sensitivity", "roles[0].priority_rank", "task_templates[0].source_ref",
  ]);
});

test("the shape check reports a missing or empty collection", () => {
  assert.deepEqual(shapeErrors({ ...demoCorpus, hubs: undefined as never, roles: [] }), [
    "hubs is not a non-empty array", "roles is not a non-empty array",
  ]);
});

test("every task template has a source_ref", () => {
  assert.ok(demoCorpus.task_templates.length > 0);
  for (const t of demoCorpus.task_templates) assert.ok(t.source_ref.trim().length > 0, t.id);
});

test("the home hub is one of the hubs", () => {
  assert.ok(demoCorpus.hubs.some((h) => h.id === demoCorpus.home_hub_id));
});
