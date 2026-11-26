import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const pkg = JSON.parse(readFileSync(new URL("../../package.json", import.meta.url), "utf8"));
const versionOf = (name: string): string => pkg.dependencies?.[name] ?? pkg.devDependencies?.[name];

test("next, vinext, vite and wrangler are pinned to exact versions", () => {
  for (const name of ["next", "vinext", "vite", "wrangler"]) {
    assert.match(versionOf(name) ?? "missing", /^\d+\.\d+\.\d+$/, name);
  }
});

test("package defines dev, build, check, db:migrate and db:seed", () => {
  for (const name of ["dev", "build", "check", "db:migrate", "db:seed"]) {
    assert.equal(typeof pkg.scripts?.[name], "string", name);
  }
});

test("check runs the typecheck, the lint and the src/lib tests", () => {
  for (const step of ["tsc --noEmit", "eslint", "node --test src/lib"]) {
    assert.ok(pkg.scripts?.check?.includes(step), step);
  }
});
