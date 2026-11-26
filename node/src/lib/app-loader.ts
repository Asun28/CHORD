// Test support: lets `node --test` import src/app pages. Resolves `cloudflare:workers` to this module
// (tests set `env.DB`), resolves the `@/` alias to src/, and compiles .tsx with TypeScript.
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";
import { fileURLToPath } from "node:url";
import ts from "typescript";
import type { SqlDb } from "./corpus.ts";

export const env: { DB?: SqlDb } = {};

const src = new URL("../", import.meta.url);

registerHooks({
  resolve(specifier, context, next) {
    if (specifier === "cloudflare:workers") return { url: import.meta.url, shortCircuit: true };
    if (specifier.startsWith("@/")) return next(new URL(specifier.slice(2), src).href, context);
    return next(specifier, context);
  },
  load(url, context, next) {
    if (!url.startsWith("file:") || !url.endsWith(".tsx")) return next(url, context);
    const { outputText } = ts.transpileModule(readFileSync(fileURLToPath(url), "utf8"), {
      compilerOptions: { jsx: ts.JsxEmit.ReactJSX, module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
    });
    return { format: "module", source: outputText, shortCircuit: true };
  },
});
