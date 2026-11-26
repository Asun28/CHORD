// Writes the fictional corpus as SQL for `wrangler d1 execute --local` (npm run db:seed).
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { seedSql, type Corpus } from "../src/lib/corpus.ts";

const corpus: Corpus = JSON.parse(readFileSync("fixtures/demo-corpus.json", "utf8"));
mkdirSync(".wrangler", { recursive: true });
writeFileSync(".wrangler/seed.sql", seedSql(corpus) + "\n");
