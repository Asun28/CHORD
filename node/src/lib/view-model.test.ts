import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const src = new URL("../", import.meta.url);
// Every source file but this one, whose patterns would match themselves.
const files = (readdirSync(src, { recursive: true }) as string[])
  .map((f) => f.replaceAll("\\", "/"))
  .filter((f) => /\.tsx?$/.test(f) && f !== "lib/view-model.test.ts");
const text = (f: string) => readFileSync(new URL(f, src), "utf8");

test("the unlock code is read from env HUB_COORDINATOR_CODE and no code literal is in node/src", () => {
  const readers = files.filter((f) => /\.HUB_COORDINATOR_CODE\b/.test(text(f)));
  const literals = files.filter((f) => /hub\s*kit|HUB_COORDINATOR_CODE\s*[:=]\s*["'`]/i.test(text(f)));
  assert.deepEqual([readers, literals], [["server/session.ts"], []]);
});

test(".env.example lists HUB_COORDINATOR_CODE, SESSION_SECRET and TRUST_CF_CONNECTING_IP with empty values", () => {
  const lines = readFileSync(new URL("../../.env.example", import.meta.url), "utf8").split(/\r?\n/).filter((l) => /^\w+=/.test(l));
  assert.deepEqual(lines.sort(), ["HUB_COORDINATOR_CODE=", "SESSION_SECRET=", "TRUST_CF_CONNECTING_IP="]);
});

test("the home page module rendered outside a request shows public assets and no restricted asset", async () => {
  const { env } = await import("./app-loader.ts");
  const { asD1, seededDb } = await import("./sqlite-fixture.ts");
  const { renderToStaticMarkup } = await import("react-dom/server");
  const { default: HomePage } = await import("../app/page.tsx");
  env.DB = asD1(seededDb());
  const html = renderToStaticMarkup(await HomePage());
  assert.deepEqual([html.includes("Rainwater tank behind the hall"), html.includes("Key holder Odile Marrow")], [true, false]);
});
