import { test } from "node:test";
import assert from "node:assert/strict";
import { normalise, toUtc } from "./cap.ts";

const source = { id: "s-a", name: "s-a", cadence_seconds: 300, tier: "P1" as const };
const item = (extra: Record<string, unknown>) =>
  ({ identifier: "A", sent: "2026-11-26T10:00:00Z", hazard: "flood", headline: "A headline", ...extra });

// Each is shaped like an ISO time with a zone but names no real instant; Date.parse would roll it over.
const impossible = [
  "2026-04-31T10:00:00Z", "2026-06-31T10:00:00Z", "2026-09-31T10:00:00Z", "2026-11-31T10:00:00Z",
  "2026-02-30T10:00:00Z", "2026-02-29T10:00:00Z", "2100-02-29T10:00:00Z", "2026-01-32T10:00:00Z",
  "2026-00-10T10:00:00Z", "2026-13-10T10:00:00Z", "2026-01-00T10:00:00Z",
  "2026-11-26T24:00:00Z", "2026-11-26T10:60:00Z", "2026-11-26T10:00:60Z",
  "2026-11-26T10:00:00+25:00", "2026-11-26T10:00:00+24:00", "2026-11-26T10:00:00-05:60",
];

test("a time naming an impossible calendar date, clock time or offset is refused", () => {
  for (const t of impossible) assert.throws(() => toUtc(t), /CAP: bad time/, t);
});

test("the normaliser refuses an impossible sent or expires time instead of rolling it over", () => {
  for (const t of impossible) {
    assert.throws(() => normalise(item({ sent: t }), source), /CAP: bad time/, `sent ${t}`);
    assert.throws(() => normalise(item({ expires: t }), source), /CAP: bad time/, `expires ${t}`);
  }
});

test("every real CAP time form is still accepted and converted to UTC", () => {
  const valid: [string, string][] = [
    ["2028-02-29T10:00:00Z", "2028-02-29T10:00:00.000Z"],
    ["2000-02-29T00:00:00Z", "2000-02-29T00:00:00.000Z"],
    ["2026-01-31T23:59:59Z", "2026-01-31T23:59:59.000Z"],
    ["2026-04-30T00:00:00Z", "2026-04-30T00:00:00.000Z"],
    ["2026-12-31T23:59:59.999Z", "2026-12-31T23:59:59.999Z"],
    ["2026-11-26T10:00:00.5Z", "2026-11-26T10:00:00.500Z"],
    ["2026-11-26T23:00:00+13:00", "2026-11-26T10:00:00.000Z"],
    ["2026-11-26T05:00:00-05:00", "2026-11-26T10:00:00.000Z"],
    ["2026-11-26T10:00:00+00:00", "2026-11-26T10:00:00.000Z"],
    ["2026-11-26T10:00:00-00:00", "2026-11-26T10:00:00.000Z"],
    ["2026-11-27T09:59:00+23:59", "2026-11-26T10:00:00.000Z"],
    ["2026-03-01T00:30:00+01:00", "2026-02-28T23:30:00.000Z"],
  ];
  for (const [t, utc] of valid) assert.equal(toUtc(t), utc, t);
  assert.equal(normalise(item({ sent: "2028-02-29T10:00:00Z", expires: "2028-02-29T11:00:00+01:00" }), source).expires,
    "2028-02-29T10:00:00.000Z");
});
