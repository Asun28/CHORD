// Coordinator session (plan 4.5): unlock with env HUB_COORDINATOR_CODE, a cookie signed with
// HMAC-SHA256 under env SESSION_SECRET and valid 30 minutes, lock, an unlock attempt limit and the
// same-origin rule. The cookie names the unlock_attempt row of its unlock; lock deletes that row, so
// a replayed cookie is dead after lock. Anything that does not verify gives the public view.
import { env } from "cloudflare:workers";
import type { ViewMode } from "../lib/contracts.ts";

const COOKIE = "chord_session";
const SESSION_MS = 30 * 60_000;
const WINDOW_MS = 15 * 60_000;
const MAX_FAILURES = 5;
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

// The unlock_attempt id the cookie names, when its signature verifies (constant time, through
// WebCrypto) and it has not expired; null for a missing, malformed, tampered or expired cookie.
async function signedId(cookieHeader: string | null): Promise<number | null> {
  const value = /(?:^|;\s*)chord_session=([^;]*)/.exec(cookieHeader ?? "")?.[1];
  const parts = /^(\d{1,15})\.(\d{13})\.([A-Za-z0-9_-]{43})$/.exec(value ?? "");
  const k = await key();
  if (!parts || !k) return null;
  const sig = Uint8Array.from(atob(parts[3].replaceAll("-", "+").replaceAll("_", "/") + "="), (c) => c.charCodeAt(0));
  const valid = await crypto.subtle.verify("HMAC", k, sig, bytes(`${parts[1]}.${parts[2]}`));
  return valid && Date.now() < Number(parts[2]) ? Number(parts[1]) : null;
}

export async function viewMode(cookieHeader: string | null): Promise<ViewMode> {
  const id = await signedId(cookieHeader);
  if (id === null) return "public";
  const row = await env.DB.prepare("SELECT 1 AS live FROM unlock_attempt WHERE id = ? AND succeeded = 1").bind(id).first();
  return row ? "coordinator" : "public";
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

// 403 unless the request's Origin is this node's own origin (a missing Origin included), then 401
// when a coordinator session is needed and absent; null when the request may proceed.
export async function refuse(request: Request, needsSession: boolean): Promise<Response | null> {
  if (request.headers.get("origin") !== new URL(request.url).origin) return reply(403);
  if (needsSession && (await viewMode(request.headers.get("cookie"))) !== "coordinator") return reply(401);
  return null;
}

// Each attempt reserves a failed row in one conditional INSERT, so overlapping requests cannot pass
// the limit; the limit is node-wide (unlock_attempt has no client column), so no request header can
// move a client into a fresh bucket. A right code turns its row into the session's row.
export async function unlock(request: Request): Promise<Response> {
  const refused = await refuse(request, false);
  if (refused) return refused;
  const k = await key();
  if (!k || !vars.HUB_COORDINATOR_CODE) return reply(503);
  const posted = await request.formData().then((f) => f.get("code"), () => null);
  if (typeof posted !== "string") return reply(400);
  const now = Date.now();
  const { meta } = await env.DB.prepare(
    `INSERT INTO unlock_attempt (attempted_at, succeeded) SELECT ?, 0
     WHERE (SELECT count(*) FROM unlock_attempt WHERE succeeded = 0 AND attempted_at > ?) < ?`,
  ).bind(iso(now), iso(now - WINDOW_MS), MAX_FAILURES).run();
  if (meta.changes === 0) return reply(429);
  const expected = await crypto.subtle.sign("HMAC", k, bytes(vars.HUB_COORDINATOR_CODE));
  if (!(await crypto.subtle.verify("HMAC", k, expected, bytes(posted)))) return reply(401);
  await env.DB.prepare("UPDATE unlock_attempt SET succeeded = 1 WHERE id = ?").bind(meta.last_row_id).run();
  const body = `${meta.last_row_id}.${now + SESSION_MS}`;
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", k, bytes(body)))));
  const value = `${body}.${sig.replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "")}`;
  return reply(303, { Location: "/", "Set-Cookie": cookie(request, value, SESSION_MS / 1000) });
}

export async function lock(request: Request): Promise<Response> {
  const refused = await refuse(request, false);
  if (refused) return refused;
  const id = await signedId(request.headers.get("cookie"));
  if (id !== null) await env.DB.prepare("DELETE FROM unlock_attempt WHERE id = ? AND succeeded = 1").bind(id).run();
  return reply(303, { Location: "/", "Set-Cookie": cookie(request, "", 0) });
}
