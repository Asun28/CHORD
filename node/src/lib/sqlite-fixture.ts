// Test support: the D1 migration and seed run against in-memory node:sqlite.
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import type { Corpus, SqlDb } from "./corpus.ts";
import { seedSql } from "./corpus.ts";

export const demoCorpus: Corpus = JSON.parse(
  readFileSync(new URL("../../fixtures/demo-corpus.json", import.meta.url), "utf8"),
);

export function seededDb(corpus: Corpus = demoCorpus): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../../migrations/0001_init.sql", import.meta.url), "utf8"));
  db.exec(seedSql(corpus));
  return db;
}

// The subset of the D1 API the node uses, over node:sqlite.
export function asD1(db: DatabaseSync): SqlDb {
  return {
    prepare: (sql) => ({
      bind: (...values) => ({
        first: async () => (db.prepare(sql).get(...(values as never[])) ?? null) as never,
        all: async () => ({ results: db.prepare(sql).all(...(values as never[])) as never[] }),
        run: async () => {
          const r = db.prepare(sql).run(...(values as never[]));
          return { meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
        },
      }),
    }),
  };
}
