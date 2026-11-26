# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` above is the single source of truth for project rules and conventions.
Edit it there, not here. This file adds commands and architecture notes.

## Commands

```bash
npm run dev                  # http://localhost:3000
npm run build                # must pass before claiming done
npm start                    # serve the production build
npm run lint                 # eslint (flat config, no args - lints the whole repo)
npx eslint src/app/page.tsx  # lint one file
npx tsc --noEmit             # typecheck only; `next build` also does this
```

No test runner is installed. There is no `npm test`. Verification is
`npm run build` + `npm run lint` + clicking through the demo path.

## Architecture

Fresh Next.js 16 App Router scaffold. The only route is `/` (`src/app/page.tsx`);
`src/components/` and `src/lib/` do not exist yet - create them when needed.

- **Generated route types.** `layout.tsx` uses `LayoutProps<"/">`, a global type Next
  emits into `.next/types` per route. Pages get `PageProps<"/route">` the same way.
  After adding a route, run `next dev` or `next build` once or TypeScript will not
  know the type exists.
- **Tailwind v4, no config file.** Wired through `@tailwindcss/postcss` in
  `postcss.config.mjs`; there is no `tailwind.config.*`. Theme tokens are declared
  in `src/app/globals.css` under `@theme inline` and consumed as utilities
  (`--color-background` -> `bg-background`).
- **Fonts.** `next/font/google` loads Geist in `layout.tsx` and exposes it as the
  CSS vars `--font-geist-sans` / `--font-geist-mono`, mapped to `--font-sans` /
  `--font-mono` in `globals.css`. Note `globals.css` still sets `body { font-family:
  Arial, ... }` from the scaffold, so components need an explicit `font-sans` to get
  Geist. Fix the body rule rather than sprinkling the utility everywhere.
- **Dark mode** is `prefers-color-scheme` only - `:root` vars are swapped in a media
  query. No theme toggle, no `class` strategy.
- **Secrets.** `.env.example` lists `ANTHROPIC_API_KEY` (server-only). Read it in
  route handlers or server components; never a `NEXT_PUBLIC_*` name.

## Next.js 16 API verification

This Next version postdates model training data. Bundled docs ship in the repo -
read them before using a remembered API:

```
node_modules/next/dist/docs/01-app/          App Router (routing, data, APIs)
node_modules/next/dist/docs/03-architecture/
node_modules/next/dist/docs/index.md
```

`next dev` rewrites the `nextjs-agent-rules` block at the top of `AGENTS.md`.
Commit that change alongside your work instead of reverting it.

## Demo work

`docs/DEMO-SCRIPT.md` is the runbook (pitch, 3-minute step table, known-good
inputs, pre-flight checklist) and is still a blank template. Keep it current as
features land - it defines what "the happy path" means for the ship-the-demo-first
rule in `AGENTS.md`.
