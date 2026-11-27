// POST /api/fixtures/step: applies the next fixtures/feeds file and returns the new cursor.
// The coordinator session check is added by T1-NODE-VIEW-GATE.
import { env } from "cloudflare:workers";
import { normalise } from "@/lib/cap.ts";
import type { FeedSource } from "@/lib/contracts.ts";
import { createStore } from "@/server/store.ts";
import floodWarning from "../../../../../fixtures/feeds/01-flood-warning.json" with { type: "json" };
import floodCancel from "../../../../../fixtures/feeds/02-flood-cancel.json" with { type: "json" };

const files = [floodWarning, floodCancel] as { source: FeedSource; items: unknown[] }[];

export async function POST(): Promise<Response> {
  const store = createStore(env.DB);
  const cursor = await store.fixtureCursor();
  if (cursor >= files.length) return Response.json({ cursor });
  const { source, items } = files[cursor];
  const alerts = items.map((item) => normalise(item, source));
  await store.addSource(source);
  const fetchedAt = new Date().toISOString();
  for (const alert of alerts) await store.ingest(alert, fetchedAt);
  await store.setFixtureCursor(cursor + 1);
  return Response.json({ cursor: cursor + 1 });
}
