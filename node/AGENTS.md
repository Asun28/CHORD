<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# CHORD web hub node (from the CHRD scaffold)

Next.js 16 App Router on vinext + Cloudflare Workers + D1, React 19, TypeScript, Tailwind v4, npm.

## Rules

- **Ship the demo path first.** Everything on the runbook's happy path works before
  anything else gets built. No auth, no persistence, no admin screens unless the
  demo shows them.
- **Ask before adding a dependency.** The stack above covers most of it. Name the
  need and the lighter alternative first.
- **Secrets stay server-side.** Read keys from `process.env` in route handlers or
  server components only. `NEXT_PUBLIC_*` is public - it ships in the browser bundle.
  Never write a real key into a file; `.env.example` holds empty placeholders.
- **This Next.js is newer than your training data.** Check
  `node_modules/next/dist/docs/` before using an API you remember rather than verified.
- **Verify before claiming done.** `npm run build` must pass. Say plainly when
  something is untested.

## Conventions

- Routes in `src/app/<segment>/page.tsx`; HTTP handlers in `src/app/api/<name>/route.ts`.
- Shared UI in `src/components/`, non-UI logic in `src/lib/`. Create them when needed.
- Server Components by default. Add `"use client"` only for state, effects, or events.
- Tailwind utilities inline. Theme tokens live in `src/app/globals.css`.
- Import via the `@/*` alias, not long relative paths.
