# Runtime spike: vinext on Windows

Run on 2026-11-27, Windows 11 Pro 10.0.26200, Node 22.23.1, npm 11.14.1.
Versions: next 16.4.6, vinext 1.4.7, vite 8.4.0, wrangler 4.168.0,
@cloudflare/vite-plugin 1.70.2, react 19.3.1. Local only: no Cloudflare
account, no remote D1.

| Check | Command | Result |
|---|---|---|
| Build | `npm run build` (`vite build`) | Pass, exit 0. Route table: `ƒ /` dynamic. |
| D1 migration and seed | `npm run db:migrate`, `npm run db:seed` | Pass. 1 migration applied to local D1; `SELECT count(*) FROM hub` returns 3. |
| D1 binding read, built Worker | `npm run start` (wrangler dev on `dist/server/wrangler.json`), `GET /` | Pass. 200, page shows "St Brigid's Hall, Ferncliff" and "Fictional demo data" read from local D1 through `import { env } from "cloudflare:workers"`. |
| D1 binding read, dev server | `vite dev`, `GET /` | Pass. Same strings. |
| Set-Cookie with HttpOnly | Temporary route handler returning `Set-Cookie: spike=1; HttpOnly; SameSite=Strict; Path=/`, removed after the spike | Pass on the built Worker and on `vite dev`; the header arrives unchanged. |
| Scheduled invocation | `wrangler dev --config dist/server/wrangler.json --persist-to .wrangler/state --test-scheduled`, then `GET /cdn-cgi/handler/scheduled?cron=*/5+*+*+*+*` | Pass. 200; Worker log `scheduled cron="*/5 * * * *" hubs=3` (the handler reads D1). |

Findings:
- `GET /__scheduled` returns 404 on wrangler 4.168.0. The working routes are
  `/cdn-cgi/handler/scheduled` (with `--test-scheduled`) and
  `POST /cdn-cgi/local/explorer/api/local/scheduled?worker=chord-node`
  with body `{"cron":"..."}`; both ran the handler.
- The scheduled handler needs a custom Worker entry (`src/worker.ts`) that
  re-exports vinext's `fetch`; `wrangler.jsonc` `main` points to it.
- `npm run start` passes `--persist-to .wrangler/state` so it reads the
  local D1 that `db:migrate` and `db:seed` wrote.
- The `vite dev` rows ran before next moved from 16.3.0 to 16.4.6; the
  build, built-Worker, cookie and scheduled rows were rerun on 16.4.6.
- `node --test src/lib` (a directory argument) fails on Node 22.23.1 with
  MODULE_NOT_FOUND; `check` uses `node --test src/lib/*.test.ts`.
- `next/font/google` was removed from the layout: it fetches fonts over the
  network, which the hall laptop may not have.
- next is pinned to 16.4.6, not 16.3.x: `npm audit` reports a critical
  advisory for next 16.0.0 to 16.4.4. Remaining: 4 moderate advisories via
  vinext -> @vercel/og -> satori -> fflate (OG image generation, unused here).

Decision: **vinext**. Every check passed on this machine; OpenNext is not needed.
