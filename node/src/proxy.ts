// Request proxy, run before routing: any request with a contacts parameter gets 404 (R5), whatever the
// path; every other response but hashed static chunks gets Cache-Control: private, no-store, because
// pages, RSC payloads and API replies depend on the coordinator session (acceptance 5).
import { NextResponse, type NextRequest } from "next/server";

const NO_STORE = "private, no-store";

export function proxy(request: NextRequest): NextResponse {
  if (request.nextUrl.searchParams.has("contacts")) {
    return new NextResponse(null, { status: 404, headers: { "Cache-Control": NO_STORE } });
  }
  const response = NextResponse.next();
  if (!request.nextUrl.pathname.startsWith("/_next/static/")) response.headers.set("Cache-Control", NO_STORE);
  return response;
}
