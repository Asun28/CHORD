import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";

const src = new URL("../", import.meta.url);
const files = (readdirSync(src, { recursive: true }) as string[]).filter((f) => /\.tsx?$/.test(f));
const text = (f: string) => readFileSync(new URL(f.replaceAll("\\", "/"), src), "utf8");

test("the unlock code is read from env HUB_COORDINATOR_CODE and no code literal is in node/src", () => {
  const readers = files.filter((f) => /\.HUB_COORDINATOR_CODE\b/.test(text(f)));
  const literals = files.filter((f) => /hub\s*kit|HUB_COORDINATOR_CODE\s*[:=]\s*["'`]/i.test(text(f)));
  assert.deepEqual([readers.map((f) => f.replaceAll("\\", "/")), literals], [["server/session.ts"], []]);
});

test(".env.example lists HUB_COORDINATOR_CODE and SESSION_SECRET with empty values", () => {
  const lines = readFileSync(new URL("../../.env.example", import.meta.url), "utf8").split(/\r?\n/).filter((l) => /^\w+=/.test(l));
  assert.deepEqual(lines.sort(), ["HUB_COORDINATOR_CODE=", "SESSION_SECRET="]);
});
