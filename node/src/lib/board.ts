import { createElement as h, type ReactElement } from "react";
import type { SqlDb } from "./corpus.ts";

export interface Board { hubName: string; fictional: boolean }

export async function readHomeBoard(db: SqlDb): Promise<Board> {
  void db;
  return { hubName: "", fictional: false };
}

export function HomeBoard({ board }: { board: Board }): ReactElement {
  void board;
  return h("main");
}
