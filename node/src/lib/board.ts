// Home hub board. Plain TS (no JSX) so `node --test` can render it; src/app/page.tsx reads D1 and renders it.
import { createElement as h, type ReactElement } from "react";
import type { SqlDb } from "./corpus.ts";

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
