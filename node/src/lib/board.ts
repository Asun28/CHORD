// Hub board and print sheet. Plain TS (no JSX) so `node --test` can render them; the pages read D1 and render them.
import { createElement as h, type ReactElement } from "react";
import { ageLabel } from "./age.ts";
import type { SqlDb } from "./corpus.ts";
import { AssetList, type Feed, type HubRead, type HubView } from "./view-model.ts";

export interface Board {
  hubName: string;
  fictional: boolean;
}

export async function readHomeBoard(db: SqlDb): Promise<Board> {
  const hub = await db
    .prepare("SELECT name, fictional FROM hub WHERE is_home = 1")
    .bind()
    .first<{ name: string; fictional: number }>();
  if (!hub) throw new Error("No home hub in D1: run npm run db:migrate and npm run db:seed");
  return { hubName: hub.name, fictional: hub.fictional === 1 };
}

export function HomeBoard({ board }: { board: Board }): ReactElement {
  return h(
    "main",
    { className: "flex flex-col gap-4 p-8" },
    board.fictional &&
      h("p", { className: "w-fit rounded bg-amber-200 px-2 py-1 text-sm font-semibold text-black" }, "Fictional demo data"),
    h("h1", { className: "text-3xl font-semibold" }, board.hubName),
  );
}

const POSTURE_CLASS = { green: "bg-green-700 text-white", watch: "bg-yellow-300 text-black", act: "bg-orange-500 text-black", respond: "bg-red-700 text-white" };
const time = (iso: string, mark: string) => h("time", { [`data-${mark}`]: "", dateTime: iso }, iso);

// R2: shown in place of the board when the store cannot be read; it names no posture.
export function ErrorBanner(): ReactElement {
  return h("p", { role: "alert", className: "m-8 rounded border-2 border-red-700 p-4 font-semibold" },
    "Store error: this node cannot read its data, so the board shows no posture. Check the local D1 and restart the node.");
}

function PostureBadge({ view }: { view: HubView }): ReactElement {
  return h("p", { "data-posture": view.posture, className: `w-fit rounded px-3 py-1 text-xl font-bold ${POSTURE_CLASS[view.posture]}` },
    `Posture: ${view.posture.toUpperCase()} at ${view.cursor}`);
}

// R1: each fact with its observation age at the cursor and its feed's last fetch time; stale when the observation is older than 3 cadences.
function Facts({ view }: { view: HubView }): ReactElement {
  if (view.facts.length === 0) return h("p", null, `No active messages at ${view.cursor}.`);
  return h("ul", { className: "flex flex-col gap-1" }, view.facts.map((f) =>
    h("li", { key: f.key, "data-fact": "" }, `${f.headline} (${f.source}). Observed `, time(f.observedAt, "observed"),
      `, ${ageLabel(f.age.ageSeconds)}. Feed last fetched `, time(f.lastFetch, "fetched"), `, ${ageLabel(f.age.fetchAgeSeconds)}.`,
      f.age.stale && h("strong", { className: "text-orange-700" }, " Marked stale: older than 3 feed cadences."))));
}

function Feeds({ feeds }: { feeds: Feed[] }): ReactElement {
  return h("ul", { className: "flex flex-wrap gap-2" }, feeds.map((f) =>
    h("li", { key: f.id, "data-feed": f.id, "data-state": f.state, className: "rounded border px-2 py-1" },
      `${f.name}: ${f.state}, last fetch `, f.lastFetch ? time(f.lastFetch, "fetched") : "never")));
}

export function HubBoard({ view }: { view: HubRead }): ReactElement {
  if ("error" in view) return ErrorBanner();
  return h("div", { className: "flex flex-col gap-4 px-8" }, HomeBoard({ board: view.board }), h(PostureBadge, { view }),
    h(Facts, { view }), h(Feeds, { feeds: view.feeds }), h(AssetList, { assets: view.assets }));
}

// R3: one A4 page; the caller passes a public view, so no restricted asset can be printed.
export function PrintSheet({ view, renderedAt }: { view: HubRead; renderedAt: string }): ReactElement {
  const rendered = h("p", null, "Rendered ", time(renderedAt, "rendered"));
  const page = h("style", null, "@page { size: A4; margin: 12mm } body { background: #fff; color: #000; font-size: 10pt }");
  if ("error" in view) return h("main", null, page, ErrorBanner(), rendered);
  return h("main", { className: "flex flex-col gap-2 p-2" }, page, h("h1", { className: "text-xl font-semibold" }, view.board.hubName),
    view.board.fictional && h("p", null, "Fictional demo data"), h(PostureBadge, { view }), h(Facts, { view }),
    h("h2", { className: "font-semibold" }, "Roles"), h("ul", null, view.roles.map((r) => h("li", { key: r.code }, `${r.name}: ${r.description}`))),
    h("h2", { className: "font-semibold" }, "Tasks"), h("ul", null, view.tasks.map((t) => h("li", { key: t.id }, `${t.phase}, ${t.role_code}: ${t.text}`))),
    h("h2", { className: "font-semibold" }, "Assets"), h(AssetList, { assets: view.assets }), rendered);
}
