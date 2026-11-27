// D1 store: one row per (source, CAP identifier), supersede from the referencing message's sent time,
// reads at a replay cursor, persisted feed pause (plan sections 4.5 and 5).
import type { SqlDb } from "../lib/corpus.ts";
import { toUtc } from "../lib/cap.ts";
import type { CapAlert, FeedSource, Observation, ObservationReader } from "../lib/contracts.ts";

export type FeedState = "running" | "paused";

const SUPERSEDE = "UPDATE observation SET superseded_by = ?, superseded_at = ? WHERE";

export function createStore(db: SqlDb) {
  const run = (sql: string, ...values: unknown[]) => db.prepare(sql).bind(...values).run();
  const store = {
    async addSource(s: FeedSource): Promise<void> {
      await run("INSERT OR IGNORE INTO source (id, name, cadence_seconds) VALUES (?, ?, ?)", s.id, s.name, s.cadence_seconds);
    },

    // Returns false for a re-fetch of a known (source, identifier): the stored row is left as it is,
    // so a cancelled message is never reactivated (fixes DomainModels.swift:254).
    async ingest(a: CapAlert, fetchedAt: string): Promise<boolean> {
      const { meta } = await run(
        `INSERT INTO observation (source_id, cap_identifier, msg_type, cap_json, sent_at, observed_at, fetched_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (source_id, cap_identifier) DO NOTHING`,
        a.source, a.identifier, a.msgType, JSON.stringify(a), a.sent, a.sent, toUtc(fetchedAt), a.expires,
      );
      if (meta.changes === 0) return false;
      const id = meta.last_row_id;
      for (const ref of a.references) {
        const hit = await run(`${SUPERSEDE} source_id = ? AND cap_identifier = ?`, id, a.sent, a.source, ref);
        if (hit.meta.changes === 0) {
          await run(
            "INSERT INTO pending_reference (source_id, target_identifier, referencing_id, sent_at) VALUES (?, ?, ?, ?)",
            a.source, ref, id, a.sent,
          );
        }
      }
      const held = "FROM pending_reference WHERE source_id = ? AND target_identifier = ?";
      const { results } = await db.prepare(`SELECT referencing_id, sent_at ${held}`).bind(a.source, a.identifier)
        .all<{ referencing_id: number; sent_at: string }>();
      for (const p of results) await run(`${SUPERSEDE} id = ?`, p.referencing_id, p.sent_at, id);
      await run(`DELETE ${held}`, a.source, a.identifier);
      return true;
    },

    // Messages active at the cursor, from stored times only (fixes ObservationStore.swift:46).
    async activeAt(cursor: string): Promise<Observation[]> {
      const t = toUtc(cursor);
      const { results } = await db
        .prepare(
          `SELECT cap_json, fetched_at FROM observation WHERE observed_at <= ?
           AND (superseded_at IS NULL OR superseded_at > ?) AND (expires_at IS NULL OR expires_at > ?)`,
        )
        .bind(t, t, t)
        .all<{ cap_json: string; fetched_at: string }>();
      return results.map((r) => ({ ...(JSON.parse(r.cap_json) as CapAlert), fetchedAt: r.fetched_at }));
    },

    async setFeedState(sourceId: string, state: FeedState, at: string): Promise<void> {
      await run(
        `INSERT INTO feed_state (source_id, state, changed_at) VALUES (?, ?, ?)
         ON CONFLICT (source_id) DO UPDATE SET state = excluded.state, changed_at = excluded.changed_at`,
        sourceId, state, toUtc(at),
      );
    },

    async feedState(sourceId: string): Promise<FeedState> {
      const row = await db.prepare("SELECT state FROM feed_state WHERE source_id = ?").bind(sourceId).first<{ state: FeedState }>();
      return row?.state ?? "running";
    },

    async fixtureCursor(): Promise<number> {
      const row = await db.prepare("SELECT position FROM fixture_cursor WHERE id = 1").bind().first<{ position: number }>();
      return row?.position ?? 0;
    },

    async setFixtureCursor(position: number): Promise<void> {
      await run("INSERT INTO fixture_cursor (id, position) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET position = excluded.position", position);
    },
  };
  return store satisfies ObservationReader;
}
