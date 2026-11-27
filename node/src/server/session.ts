// Coordinator session (plan 4.5): unlock with env HUB_COORDINATOR_CODE, a cookie signed with
// HMAC-SHA256 under env SESSION_SECRET and valid 30 minutes, lock, an unlock attempt limit and the
// same-origin rule. The cookie names the unlock_attempt row of its unlock and that row's time; lock
// marks the row LOCKED and never deletes it, so no row id is reused and a replayed cookie stays dead.
// Anything that does not verify gives the public view.
import { env } from "cloudflare:workers";
import type { ViewMode } from "../lib/contracts.ts";

const COOKIE = "chord_session";
const SESSION_MS = 30 * 60_000;
const WINDOW_MS = 15 * 60_000;
const MAX_FAILURES = 5; // per client in the window
const MAX_NODE_FAILURES = 50; // all clients together in the window
const NO_CLIENT_KEY = "no-cf-connecting-ip";
// unlock_attempt.succeeded: a wrong code, a live session, a session ended by lock.
const FAILED = 0, LIVE = 1, LOCKED = 2;
const vars = env as typeof env & { SESSION_SECRET?: string; HUB_COORDINATOR_CODE?: string };
const bytes = (s: string) => new TextEncoder().encode(s);
const iso = (ms: number) => new Date(ms).toISOString();
const LOCAL_HOSTS = ["localhost", "127.0.0.1", "[::1]"];

export const NO_STORE = { "Cache-Control": "private, no-store" };
export const reply = (status: number, extra: Record<string, string> = {}) =>
  new Response(null, { status, headers: { ...NO_STORE, ...extra } });

async function key(): Promise<CryptoKey | null> {
  if (!vars.SESSION_SECRET) return null;
  return crypto.subtle.importKey("raw", bytes(vars.SESSION_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

function cookie(request: Request, value: string, maxAge: number): string {
  const secure = LOCAL_HOSTS.includes(new URL(request.url).hostname) ? "" : "; Secure";
  return `${COOKIE}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${maxAge}${secure}`;
}

// The unlock_attempt row the cookie names (id and attempted_at), when its signature verifies (constant
// time, through WebCrypto) and it has not expired; null for a missing, malformed, tampered or expired cookie.
async function signedRow(cookieHeader: string | null): Promise<[number, string] | null> {
  const value = /(?:^|;\s*)chord_session=([^;]*)/.exec(cookieHeader ?? "")?.[1];
  const parts = /^(\d{1,15})\.(\d{13})\.([A-Za-z0-9_-]{43})$/.exec(value ?? "");
  const k = await key();
  if (!parts || !k) return null;
  const sig = Uint8Array.from(atob(parts[3].replaceAll("-", "+").replaceAll("_", "/") + "="), (c) => c.charCodeAt(0));
  const valid = await crypto.subtle.verify("HMAC", k, sig, bytes(`${parts[1]}.${parts[2]}`));
  return valid && Date.now() < Number(parts[2]) ? [Number(parts[1]), iso(Number(parts[2]) - SESSION_MS)] : null;
}

export async function viewMode(cookieHeader: string | null): Promise<ViewMode> {
  const row = await signedRow(cookieHeader);
  if (row === null) return "public";
  const live = await env.DB.prepare("SELECT 1 AS live FROM unlock_attempt WHERE id = ? AND attempted_at = ? AND succeeded = ?")
    .bind(...row, LIVE).first();
  return live ? "coordinator" : "public";
}

// View mode of the current page request; outside a request scope (a unit test rendering a page,
// where next/headers does not load) it is public.
export async function requestViewMode(): Promise<ViewMode> {
  let cookieHeader: string | null;
  try {
    const { headers } = await import("next/headers");
    cookieHeader = (await headers()).get("cookie");
  } catch {
    return "public";
  }
  return viewMode(cookieHeader);
}

// Any request with a contacts parameter gets 404 (R5): the node has no contacts view.
export const hasContactsParam = (request: Request) => new URL(request.url).searchParams.has("contacts");

// Every method but POST on the POST routes: 404 with a contacts parameter, else 405.
export async function otherMethod(request: Request): Promise<Response> {
  return hasContactsParam(request) ? reply(404) : reply(405, { Allow: "POST" });
}

// 404 for a contacts parameter, then 403 unless the request's Origin is this node's own origin (a missing Origin included), then 401
// when a coordinator session is needed and absent; null when the request may proceed.
export async function refuse(request: Request, needsSession: boolean): Promise<Response | null> {
  if (hasContactsParam(request)) return reply(404);
  if (request.headers.get("origin") !== new URL(request.url).origin) return reply(403);
  if (needsSession && (await viewMode(request.headers.get("cookie"))) !== "coordinator") return reply(401);
  return null;
}

// Records an attempt with its outcome only while the window holds fewer than MAX_FAILURES failures from
// this client and fewer than MAX_NODE_FAILURES from all clients, in one conditional INSERT, so overlapping
// requests cannot pass either limit. Returns the row id, or null when a limit refuses it. The client is
// CF-Connecting-IP, which Cloudflare sets; where a client can forge it (local wrangler dev), the node-wide
// ceiling still bounds guessing.
async function recordAttempt(now: number, client: string, outcome: typeof FAILED | typeof LIVE): Promise<number | null> {
  const since = iso(now - WINDOW_MS);
  const { meta } = await env.DB.prepare(
    `INSERT INTO unlock_attempt (attempted_at, succeeded, client_key) SELECT ?, ?, ?
     WHERE (SELECT count(*) FROM unlock_attempt WHERE succeeded = ? AND client_key = ? AND attempted_at > ?) < ?
       AND (SELECT count(*) FROM unlock_attempt WHERE succeeded = ? AND attempted_at > ?) < ?`,
  ).bind(iso(now), outcome, client, FAILED, client, since, MAX_FAILURES, FAILED, since, MAX_NODE_FAILURES).run();
  return meta.changes === 0 ? null : meta.last_row_id;
}

// The code is checked first (constant time), then its outcome is recorded under the limit: a right code
// is refused with 429 while either limit is reached, and is never counted as a failure.
export async function unlock(request: Request): Promise<Response> {
  const refused = await refuse(request, false);
  if (refused) return refused;
  const k = await key();
  if (!k || !vars.HUB_COORDINATOR_CODE) return reply(503);
  const posted = await request.formData().then((f) => f.get("code"), () => null);
  if (typeof posted !== "string") return reply(400);
  const expected = await crypto.subtle.sign("HMAC", k, bytes(vars.HUB_COORDINATOR_CODE));
  const right = await crypto.subtle.verify("HMAC", k, expected, bytes(posted));
  const now = Date.now();
  const id = await recordAttempt(now, request.headers.get("cf-connecting-ip") || NO_CLIENT_KEY, right ? LIVE : FAILED);
  if (id === null) return reply(429);
  if (!right) return reply(401);
  const body = `${id}.${now + SESSION_MS}`;
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", k, bytes(body)))));
  const value = `${body}.${sig.replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "")}`;
  return reply(303, { Location: "/", "Set-Cookie": cookie(request, value, SESSION_MS / 1000) });
}

export async function lock(request: Request): Promise<Response> {
  const refused = await refuse(request, false);
  if (refused) return refused;
  const row = await signedRow(request.headers.get("cookie"));
  if (row !== null) {
    await env.DB.prepare("UPDATE unlock_attempt SET succeeded = ? WHERE id = ? AND attempted_at = ? AND succeeded = ?")
      .bind(LOCKED, ...row, LIVE).run();
  }
  return reply(303, { Location: "/", "Set-Cookie": cookie(request, "", 0) });
}
