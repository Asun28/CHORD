// Hub view model (plan 4.5): restricted rows are removed by ViewMode before render. Plain TS (no JSX).
import { createElement as h, type ReactElement } from "react";
import type { Board } from "./board.ts";
import type { ViewMode } from "./contracts.ts";
import type { Asset, SqlDb } from "./corpus.ts";

type AssetRow = Pick<Asset, "name" | "sensitivity">;
export interface HubView { board: Board; assets: AssetRow[] }

// A row is shown when it is public, or restricted and the view is coordinator; any other value is removed.
export function visibleAssets(rows: AssetRow[], mode: ViewMode): AssetRow[] {
  return rows.filter((r) => r.sensitivity === "public" || (mode === "coordinator" && r.sensitivity === "restricted"));
}

// The hub with that id, or the home hub when hubId is null; null when there is no such hub.
export async function readHubView(db: SqlDb, hubId: string | null, mode: ViewMode): Promise<HubView | null> {
  const hub = await db
    .prepare("SELECT id, name, fictional FROM hub WHERE (? IS NULL AND is_home = 1) OR id = ?")
    .bind(hubId, hubId)
    .first<{ id: string; name: string; fictional: number }>();
  if (!hub) return null;
  const { results } = await db.prepare("SELECT name, sensitivity FROM hub_asset WHERE hub_id = ? ORDER BY id").bind(hub.id).all<AssetRow>();
  return { board: { hubName: hub.name, fictional: hub.fictional === 1 }, assets: visibleAssets(results, mode) };
}

// Pages answer 404 to any contacts parameter: the node has no contacts view (R5).
export function asksForContacts(searchParams: Record<string, unknown> | undefined): boolean {
  return searchParams !== undefined && "contacts" in searchParams;
}

export function AssetList({ assets }: { assets: AssetRow[] }): ReactElement {
  return h("ul", { className: "list-disc px-12" }, assets.map((a) => h("li", { key: a.name }, a.name)));
}
