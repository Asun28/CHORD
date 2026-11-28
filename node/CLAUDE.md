# CLAUDE.md

@AGENTS.md

`AGENTS.md` above holds the rules carried over from the CHRD scaffold. This
file adds commands and architecture notes for the CHORD web hub node.

## Commands

```bash
npm run dev          # vite dev (vinext + Cloudflare plugin, local D1)
npm run build        # vite build, must pass
npm run start        # wrangler dev on the built Worker, local D1
npm run check        # tsc --noEmit, eslint --max-warnings 0, node --test src/lib/*.test.ts src/server/*.test.ts
npm run test:integration  # node --test tests/*.integration.test.ts; starts and stops its own built Workers and vite dev
npm run db:migrate   # apply migrations/ to local D1
npm run db:seed      # load fixtures/demo-corpus.json into local D1 (once per fresh D1)
```

## Architecture

Next.js 16 App Router code run by vinext on Vite, deployed shape is a
Cloudflare Worker (`wrangler.jsonc`, entry `src/worker.ts`). Runtime decision
and receipts: `SPIKE.md`.

- `src/lib/`: plain TypeScript with no Cloudflare import, tested by `node --test`
  with type stripping (imports use `.ts` extensions; no JSX in `src/lib`).
- `src/app/`: pages. Bindings come from `import { env } from "cloudflare:workers"`,
  typed in `src/server/cloudflare-workers.d.ts`.
- `migrations/`: D1 schema, applied in order: `0001_init.sql` (frozen),
  `0002_unlock_client.sql` (unlock client key), `0003_hub_location.sql` (hub
  lat and lon). `fixtures/demo-corpus.json`: invented places and people,
  flagged `"fictional": true`; the board labels it.
- `scripts/hall-check.ps1`: hall check; `-Offline` refuses while DNS resolves
  (see README.md).
- Scheduled handler: invoked manually (`wrangler dev --test-scheduled`, then
  `GET /cdn-cgi/handler/scheduled?cron=...`); local cron does not run on its own.
- Fonts are system fonts: the hall laptop may have no network.
- Bundled Next docs: `node_modules/next/dist/docs/`. vinext reimplements the
  Next API on Vite; check `vinext check` output before relying on an API.
