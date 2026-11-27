// POST /api/feeds/[id]/pause and /api/feeds/[id]/resume (coordinator): persists the feed state.
import { env } from "cloudflare:workers";
import { createStore } from "@/server/store.ts";
import { NO_STORE, refuse, reply } from "@/server/session.ts";

const STATES = { pause: "paused", resume: "running" } as const;

export async function POST(request: Request, { params }: { params: Promise<{ id: string; action: string }> }): Promise<Response> {
  const refused = await refuse(request, true);
  if (refused) return refused;
  const { id, action } = await params;
  const state = Object.hasOwn(STATES, action) ? STATES[action as keyof typeof STATES] : null;
  const known = await env.DB.prepare("SELECT 1 AS known FROM source WHERE id = ?").bind(id).first();
  if (!state || !known) return reply(404);
  await createStore(env.DB).setFeedState(id, state, new Date().toISOString());
  return Response.json({ id, state }, { headers: NO_STORE });
}
