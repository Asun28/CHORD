import { beforeEach, mock, test } from "node:test";
import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import { env } from "../lib/app-loader.ts";
import { asD1, seededDb } from "../lib/sqlite-fixture.ts";
import { viewMode } from "./session.ts";

const { POST: unlockRoute } = await import("../app/api/unlock/route.ts");
const { POST: lockRoute } = await import("../app/api/lock/route.ts");

const t0 = Date.parse("2026-11-27T01:00:00.000Z");
const secret = randomBytes(32).toString("hex");
const code = randomBytes(9).toString("hex");
mock.timers.enable({ apis: ["Date"], now: t0 });

beforeEach(() => {
  mock.timers.setTime(t0);
  Object.assign(env, { DB: asD1(seededDb()), SESSION_SECRET: secret, HUB_COORDINATOR_CODE: code });
});

const post = (route: (r: Request) => Promise<Response>, body: string, host = "localhost", cookie = "") =>
  route(new Request(`http://${host}/api/x`, {
    method: "POST",
    headers: { origin: `http://${host}`, "content-type": "application/x-www-form-urlencoded", cookie },
    body,
  }));
const unlock = (c: string, host?: string) => post(unlockRoute, `code=${c}`, host);
const cookieOf = (res: Response) => (res.headers.get("set-cookie") ?? "").split(";")[0];
const at = (ms: number) => mock.timers.setTime(t0 + ms);

test("unlock sets an HttpOnly SameSite=Strict cookie valid 30 minutes, Secure unless the host is localhost", async () => {
  const local = await unlock(code);
  const remote = await unlock(code, "hub.example.org");
  assert.deepEqual(
    [local.status, local.headers.get("set-cookie")?.split("; ").slice(1), remote.headers.get("set-cookie")?.split("; ").slice(1)],
    [303, ["Path=/", "HttpOnly", "SameSite=Strict", "Max-Age=1800"], ["Path=/", "HttpOnly", "SameSite=Strict", "Max-Age=1800", "Secure"]],
  );
});

test("the cookie is signed with HMAC-SHA256 under SESSION_SECRET and expires 30 minutes after unlock", async () => {
  const [, id, exp, sig] = /^chord_session=(\d+)\.(\d+)\.(.+)$/.exec(cookieOf(await unlock(code)))!;
  const expected = createHmac("sha256", secret).update(`${id}.${exp}`).digest("base64url");
  assert.deepEqual([Number(exp), sig], [t0 + 30 * 60_000, expected]);
});

test("a valid cookie gives coordinator view; tampered, malformed or missing cookies give public view", async () => {
  const good = cookieOf(await unlock(code));
  const [, id, exp, sig] = /^chord_session=(\d+)\.(\d+)\.(.+)$/.exec(good)!;
  const flip = (s: string) => s.slice(0, -1) + (s.endsWith("A") ? "B" : "A");
  const bad = [
    `chord_session=${id}.${exp}.${flip(sig)}`,
    `chord_session=${id}.${Number(exp) + 60_000}.${sig}`,
    `chord_session=${Number(id) + 1}.${exp}.${sig}`,
    `chord_session=${id}.${exp}`,
    `chord_session=${id}.${exp}.${sig}.x`,
    "chord_session=%%%",
    "",
  ];
  const views = await Promise.all([good, ...bad].map((c) => viewMode(c)));
  assert.deepEqual(views, ["coordinator", ...bad.map(() => "public")]);
});

test("a cookie signed under another secret gives public view", async () => {
  const good = cookieOf(await unlock(code));
  Object.assign(env, { SESSION_SECRET: randomBytes(32).toString("hex") });
  assert.equal(await viewMode(good), "public");
});

test("the session is coordinator at 29m59s and public at 30m and at 30m + 1s", async () => {
  const cookie = cookieOf(await unlock(code));
  const views = [];
  for (const ms of [29 * 60_000 + 59_000, 30 * 60_000, 30 * 60_000 + 1000]) {
    at(ms);
    views.push(await viewMode(cookie));
  }
  assert.deepEqual(views, ["coordinator", "public", "public"]);
});

test("POST /api/lock clears the cookie and ends the session for a replayed cookie", async () => {
  const cookie = cookieOf(await unlock(code));
  const res = await post(lockRoute, "", "localhost", cookie);
  assert.deepEqual(
    [res.status, res.headers.get("set-cookie"), await viewMode(cookie)],
    [303, "chord_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0", "public"],
  );
});

test("unlock without SESSION_SECRET or HUB_COORDINATOR_CODE sets no cookie", async () => {
  const statuses = [];
  for (const unset of ["SESSION_SECRET", "HUB_COORDINATOR_CODE"]) {
    Object.assign(env, { SESSION_SECRET: secret, HUB_COORDINATOR_CODE: code, [unset]: "" });
    const res = await unlock(unset === "SESSION_SECRET" ? code : "");
    statuses.push([res.status, res.headers.get("set-cookie")]);
  }
  assert.deepEqual(statuses, [[503, null], [503, null]]);
});

test("the sixth wrong code in 15 minutes gets 429, and so does the right code until the window passes", async () => {
  const statuses = [];
  for (let i = 0; i < 6; i++) {
    at(i * 60_000);
    statuses.push((await unlock("wrong")).status);
  }
  at(14 * 60_000 + 59_000);
  statuses.push((await unlock(code)).status);
  at(15 * 60_000 + 1000);
  statuses.push((await unlock(code)).status);
  assert.deepEqual(statuses, [401, 401, 401, 401, 401, 429, 429, 303]);
});

test("overlapping wrong codes from one client get five 401 and then 429", async () => {
  const statuses = (await Promise.all(Array.from({ length: 8 }, () => unlock("wrong")))).map((r) => r.status);
  assert.deepEqual(statuses.sort(), [401, 401, 401, 401, 401, 429, 429, 429]);
});
