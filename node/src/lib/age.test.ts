import { test } from "node:test";
import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { ageLabel, factAge } from "./age.ts";
import { env } from "./app-loader.ts";
import { normalise } from "./cap.ts";
import { asD1, seededDb } from "./sqlite-fixture.ts";
import { createStore } from "../server/store.ts";

const { default: HomePage } = await import("../app/page.tsx");

const cursor = "2026-11-26T12:00:00.000Z";
const secondsBefore = (s: number) => new Date(Date.parse(cursor) - s * 1000).toISOString();

test("cadence 300 s: a fact fetched 899 s before the cursor is fresh, 900 s is fresh, 901 s is stale", () => {
  const ages = [899, 900, 901].map((s) => factAge(secondsBefore(s + 60), secondsBefore(s), 300, cursor));
  assert.deepEqual(ages, [
    { ageSeconds: 959, fetchAgeSeconds: 899, stale: false },
    { ageSeconds: 960, fetchAgeSeconds: 900, stale: false },
    { ageSeconds: 961, fetchAgeSeconds: 901, stale: true },
  ]);
});

test("age labels read minutes and seconds, hours and minutes, and a time after the cursor", () => {
  assert.deepEqual([ageLabel(899), ageLabel(7260), ageLabel(-5)], ["14m 59s ago", "2h 1m ago", "after the cursor"]);
});

test("the board shows each fact's age at the cursor with its feed's last fetch, and a paused feed tile with that time", async () => {
  const db = asD1(seededDb());
  const store = createStore(db);
  const source = { id: "fict-river-watch", name: "Fictional river watch", cadence_seconds: 300, tier: "P1" as const };
  await store.addSource(source);
  const item = (identifier: string, sent: number) => normalise({ identifier, sent: secondsBefore(sent), hazard: "flood", headline: `Fictional: ${identifier}` }, source);
  await store.ingest(item("a1", 1800), secondsBefore(901));
  await store.ingest(item("a2", 2400), secondsBefore(1000));
  await store.setFeedState(source.id, "paused", secondsBefore(60));
  env.DB = db;
  const html = renderToStaticMarkup(await HomePage({ searchParams: Promise.resolve({ at: cursor }) }));
  const text = (li: string) => li.replace(/<[^>]+>/g, "");
  const tile = text(/<li[^>]*data-feed="fict-river-watch"[^>]*>.*?<\/li>/.exec(html)?.[0] ?? "");
  const facts = [...html.matchAll(/<li[^>]*data-fact[^>]*>.*?<\/li>/g)].map(([li]) => text(li)).sort();
  const fact = (f: string) => [/\d+m \d+s ago\. Feed/.exec(f)?.[0], f.includes("last fetched 2026-11-26T11:44:59.000Z"), f.includes("stale")];
  assert.deepEqual(
    [tile.includes("paused"), tile.includes("2026-11-26T11:44:59.000Z"), facts.map(fact)],
    [true, true, [["30m 0s ago. Feed", true, true], ["40m 0s ago. Feed", true, true]]],
  );
});
