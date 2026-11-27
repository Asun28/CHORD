import type { SqlDb } from "../lib/corpus.ts";
import type { CapAlert, FeedSource, Observation } from "../lib/contracts.ts";

export type FeedState = "running" | "paused";

export function createStore(db: SqlDb) {
  void db;
  return {
    async addSource(source: FeedSource): Promise<void> { void source; },
    async ingest(alert: CapAlert, fetchedAt: string): Promise<boolean> { void alert; void fetchedAt; return true; },
    async activeAt(cursor: string): Promise<Observation[]> { void cursor; return []; },
    async setFeedState(sourceId: string, state: FeedState, at: string): Promise<void> { void sourceId; void state; void at; },
    async feedState(sourceId: string): Promise<FeedState> { void sourceId; return "running"; },
  };
}
