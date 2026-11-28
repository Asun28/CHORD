// Hub view model (plan 4.5): restricted rows are removed by ViewMode before render; a store that cannot
// be read gives the error state, never a posture. Plain TS (no JSX).
import { createElement as h, type ReactElement } from "react";
import { factAge, type FactAge } from "./age.ts";
import type { Board } from "./board.ts";
import { toUtc } from "./cap.ts";
import type { Posture, ViewMode } from "./contracts.ts";
import type { Asset, Role, SqlDb, TaskTemplate } from "./corpus.ts";
import { hubPosture } from "./rules.ts";
import { createStore, type FeedState } from "../server/store.ts";

type AssetRow = Pick<Asset, "name" | "sensitivity">;
export interface Fact { key: string; headline: string; source: string; observedAt: string; lastFetch: string; age: FactAge }
export interface Feed { id: string; name: string; cadence: number; state: FeedState; lastFetch: string | null }
export interface HubView {
  board: Board; assets: AssetRow[]; cursor: string; posture: Exclude<Posture, "error">; facts: Fact[]; feeds: Feed[];
  roles: Pick<Role, "code" | "name" | "description">[]; tasks: Pick<TaskTemplate, "id" | "role_code" | "phase" | "text">[];
}
export type HubRead = HubView | { error: true };

// A row is shown when it is public, or restricted and the view is coordinator; any other value is removed.
export function visibleAssets(rows: AssetRow[], mode: ViewMode): AssetRow[] {
  return rows.filter((r) => r.sensitivity === "public" || (mode === "coordinator" && r.sensitivity === "restricted"));
}

// The replay cursor from `at` (now when absent); null when `at` names no real instant.
export function cursorOf(query: Record<string, unknown> | undefined): string | null {
  if (query?.at === undefined) return new Date().toISOString();
  try {
    return toUtc(query.at);
  } catch {
    return null;
  }
}

const FEEDS = `SELECT s.id, s.name, s.cadence_seconds AS cadence, COALESCE(f.state, 'running') AS state,
  (SELECT max(o.fetched_at) FROM observation o WHERE o.source_id = s.id) AS lastFetch
  FROM source s LEFT JOIN feed_state f ON f.source_id = s.id ORDER BY s.id`;

async function read(db: SqlDb, hubId: string | null, mode: ViewMode, cursor: string): Promise<HubView | null> {
  const all = <T>(sql: string, ...values: unknown[]) => db.prepare(sql).bind(...values).all<T>().then((r) => r.results);
  const hub = await db
    .prepare("SELECT id, name, fictional, lat, lon FROM hub WHERE (? IS NULL AND is_home = 1) OR id = ?")
    .bind(hubId, hubId)
    .first<{ id: string; name: string; fictional: number; lat: number | null; lon: number | null }>();
  if (!hub) return null;
  if (hub.lat === null || hub.lon === null) throw new Error(`hub ${hub.id} has no coordinates`);
  const assets = await all<AssetRow>("SELECT name, sensitivity FROM hub_asset WHERE hub_id = ? ORDER BY id", hub.id);
  const feeds = await all<Feed>(FEEDS);
  const active = await createStore(db).activeAt(cursor);
  const { posture } = await hubPosture({ activeAt: async () => active }, { id: hub.id, lat: hub.lat, lon: hub.lon }, cursor);
  if (posture === "error") throw new Error("posture could not be read");
  const facts = active.map((o) => {
    const feed = feeds.find((f) => f.id === o.source)!;
    const lastFetch = feed.lastFetch as string; // the latest fetch of a feed that has this fact
    return { key: `${o.source}/${o.identifier}`, headline: o.headline, source: feed.name, observedAt: o.sent, lastFetch, age: factAge(o.sent, lastFetch, feed.cadence, cursor) };
  });
  return {
    board: { hubName: hub.name, fictional: hub.fictional === 1 }, assets: visibleAssets(assets, mode), cursor, posture, facts, feeds,
    roles: await all("SELECT code, name, description FROM role ORDER BY priority_rank"),
    tasks: await all("SELECT id, role_code, phase, text FROM task_template ORDER BY id"),
  };
}

// The hub with that id, or the home hub when hubId is null; null when there is no such hub; the error
// state when any read fails.
export async function readHubView(db: SqlDb, hubId: string | null, mode: ViewMode, cursor: string): Promise<HubRead | null> {
  try {
    return await read(db, hubId, mode, cursor);
  } catch {
    return { error: true };
  }
}

// Pages answer 404 to any contacts parameter: the node has no contacts view (R5).
export function asksForContacts(searchParams: Record<string, unknown> | undefined): boolean {
  return searchParams !== undefined && "contacts" in searchParams;
}

export function AssetList({ assets }: { assets: AssetRow[] }): ReactElement {
  return h("ul", { className: "list-disc px-12" }, assets.map((a) => h("li", { key: a.name }, a.name)));
}
