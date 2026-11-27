// Coordinator session: not implemented yet (RED skeleton).
import type { ViewMode } from "../lib/contracts.ts";

export async function viewMode(cookieHeader: string | null): Promise<ViewMode> {
  void cookieHeader;
  return "public";
}

export async function unlock(request: Request): Promise<Response> {
  void request;
  return new Response(null, { status: 501 });
}

export const lock = unlock;
