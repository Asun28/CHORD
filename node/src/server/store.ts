// D1 store: one row per (source, CAP identifier), supersede from the referencing message's sent time,
// reads at a replay cursor, persisted feed pause (plan sections 4.5 and 5).
import type { SqlDb } from "../lib/corpus.ts";
import { toUtc } from "../lib/cap.ts";
import type { CapAlert, FeedSource, Observation, ObservationReader } from "../lib/contracts.ts";

export type FeedState = "running" | "paused";

// Records the references of the stored message (source, identifier), read from its stored row so a
// re-fetch adds nothing. Only an Update or Cancel supersedes; an Alert's references are ignored.
const RECORD_REFERENCES = `INSERT OR IGNORE INTO pending_reference (source_id, target_identifier, referencing_id, sent_at)
  SELECT o.source_id, r.value, o.id, o.sent_at FROM observation o, json_each(o.cap_json, '$.references') r
  WHERE o.source_id = ? AND o.cap_identifier = ? AND o.msg_type IN ('update', 'cancel')`;

// Sets the supersession of the stored message and of every message it references to the earliest
// referencing message (sent time, then source, then identifier), whatever order they arrived in.
const EARLIEST = `FROM pending_reference p JOIN observation r ON r.id = p.referencing_id
  WHERE p.source_id = observation.source_id AND p.target_identifier = observation.cap_identifier
  ORDER BY r.sent_at, r.source_id, r.cap_identifier LIMIT 1`;
const RESOLVE_SUPERSESSION = `UPDATE observation
  SET superseded_by = (SELECT r.id ${EARLIEST}), superseded_at = (SELECT r.sent_at ${EARLIEST})
  WHERE source_id = ? AND (cap_identifier = ? OR cap_identifier IN (
    SELECT p.target_identifier FROM pending_reference p JOIN observation m ON m.id = p.referencing_id
    WHERE m.source_id = ? AND m.cap_identifier = ?))`;

export function createStore(db: SqlDb) {
  const statement = (sql: string, ...values: unknown[]) => db.prepare(sql).bind(...values);
  const run = (sql: string, ...values: unknown[]) => statement(sql, ...values).run();
  const store = {
    async addSource(s: FeedSource): Promise<void> {
      await run("INSERT OR IGNORE INTO source (id, name, cadence_seconds) VALUES (?, ?, ?)", s.id, s.name, s.cadence_seconds);
    },

    // Returns false for a re-fetch of a known (source, identifier): the stored row is left as it is,
    // so a cancelled message is never reactivated (fixes DomainModels.swift:254). The insert and its
    // reference effects commit as one batch, and each effect is derived from stored rows, so a retry
    // after a failure, or a re-fetch, ends in the same state.
    async ingest(a: CapAlert, fetchedAt: string): Promise<boolean> {
      const [inserted] = await db.batch([
        statement(
          `INSERT INTO observation (source_id, cap_identifier, msg_type, cap_json, sent_at, observed_at, fetched_at, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (source_id, cap_identifier) DO NOTHING`,
          a.source, a.identifier, a.msgType, JSON.stringify(a), a.sent, a.sent, toUtc(fetchedAt), a.expires,
        ),
        statement(RECORD_REFERENCES, a.source, a.identifier),
        statement(RESOLVE_SUPERSESSION, a.source, a.identifier, a.source, a.identifier),
      ]);
      return inserted.meta.changes > 0;
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

    // Moves the replay cursor from `from` to from + 1 only while it is still at `from`: false when
    // another step moved it first, so a stale step never moves it back or skips a file.
    async advanceFixtureCursor(from: number): Promise<boolean> {
      const { meta } = await run(
        `INSERT INTO fixture_cursor (id, position) SELECT 1, ? WHERE ? = 0 OR EXISTS (SELECT 1 FROM fixture_cursor)
         ON CONFLICT (id) DO UPDATE SET position = excluded.position WHERE fixture_cursor.position = ?`,
        from + 1, from, from,
      );
      return meta.changes > 0;
    },
  };
  return store satisfies ObservationReader;
}
