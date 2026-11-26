// Bindings this node reads through `import { env } from "cloudflare:workers"` (see wrangler.jsonc).
declare module "cloudflare:workers" {
  export const env: { DB: import("../lib/corpus.ts").SqlDb };
}
