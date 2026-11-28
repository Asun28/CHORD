import { test } from "node:test";
import assert from "node:assert/strict";
import type { Corpus } from "./corpus.ts";
import { demoCorpus } from "./sqlite-fixture.ts";
import { normalise } from "./cap.ts";
import { hubPosture } from "./rules.ts";
import floodWarning from "../../fixtures/feeds/01-flood-warning.json" with { type: "json" };

// The eight hub roles named in the planning corpus (ingest_wremo.py ROLES).
const roleCodes = [
  "hub_supervisor", "information_coord", "public_information", "reception",
  "needs_and_offers", "community_space", "communications", "facility_maintenance",
];

type Kind = "string" | "rank" | "sensitivity" | "lat" | "lon";
const required: Record<"hubs" | "assets" | "roles" | "task_templates", Record<string, Kind>> = {
  hubs: { id: "string", name: "string", suburb: "string", address: "string", lat: "lat", lon: "lon" },
  assets: { id: "string", hub_id: "string", kind: "string", name: "string", sensitivity: "sensitivity" },
  roles: { code: "string", name: "string", description: "string", priority_rank: "rank", source_ref: "string" },
  task_templates: { id: "string", role_code: "string", phase: "string", text: "string", source_ref: "string" },
};

function fits(kind: Kind, v: unknown): boolean {
  if (kind === "rank") return Number.isInteger(v) && (v as number) >= 1;
  if (kind === "lat") return typeof v === "number" && v >= -90 && v <= 90;
  if (kind === "lon") return typeof v === "number" && v >= -180 && v <= 180;
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

test("the shape check reports a hub coordinate that is missing or outside its range", () => {
  const [hub] = demoCorpus.hubs;
  const broken: Corpus = { ...demoCorpus, hubs: [{ ...hub, lat: undefined as never }, { ...hub, lat: -90.5 }, { ...hub, lon: 180.5 }] };
  assert.deepEqual(shapeErrors(broken), ["hubs[0].lat", "hubs[1].lat", "hubs[2].lon"]);
});

test("the flood warning fixture covers at least one hub and misses at least one", async () => {
  const warning = { ...normalise(floodWarning.items[0], floodWarning.source as never), fetchedAt: floodWarning.items[0].sent };
  const reader = { activeAt: async () => [warning] };
  const postures = await Promise.all(demoCorpus.hubs.map(async (hub) => (await hubPosture(reader, hub, warning.sent)).posture));
  assert.deepEqual([postures.includes("act"), postures.includes("green")], [true, true]);
});
