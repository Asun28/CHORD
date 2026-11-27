// Test support: the D1 migration and seed run against in-memory node:sqlite.
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import type { Corpus, SqlDb, SqlRunResult, SqlStatement } from "./corpus.ts";
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

// The subset of the D1 API the node uses, over node:sqlite. `batch` runs synchronously between
// BEGIN and COMMIT, so no other call interleaves with it, and rolls back on the first failure.
export function asD1(db: DatabaseSync): SqlDb {
  const runners = new WeakMap<SqlStatement, () => SqlRunResult>();
  return {
    prepare: (sql) => ({
      bind: (...values) => {
        const runNow = (): SqlRunResult => {
          const r = db.prepare(sql).run(...(values as never[]));
          return { meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
        };
        const statement: SqlStatement = {
          first: async () => (db.prepare(sql).get(...(values as never[])) ?? null) as never,
          all: async () => ({ results: db.prepare(sql).all(...(values as never[])) as never[] }),
          run: async () => runNow(),
        };
        runners.set(statement, runNow);
        return statement;
      },
    }),
    batch: async (statements) => {
      db.exec("BEGIN");
      try {
        const results = statements.map((s) => runners.get(s)!());
        db.exec("COMMIT");
        return results;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
  };
}
