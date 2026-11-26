// Worker entry: vinext serves requests; `scheduled` is invoked manually in this version
// (`wrangler dev --test-scheduled`, then GET /__scheduled). Local cron does not run on its own.
import vinext from "vinext/server/fetch-handler";
import type { SqlDb } from "./lib/corpus.ts";

const worker = {
  fetch: vinext.fetch,
  async scheduled(controller: { cron: string }, env: { DB: SqlDb }): Promise<void> {
    const row = await env.DB.prepare("SELECT count(*) AS hubs FROM hub").bind().first<{ hubs: number }>();
    console.log(`scheduled cron="${controller.cron}" hubs=${row?.hubs ?? 0}`);
  },
};

export default worker;
