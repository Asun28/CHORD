// GET /hub/[id]?at= : one hub's board in the request's view mode at the replay cursor.
import { env } from "cloudflare:workers";
import { notFound } from "next/navigation";
import { HubBoard } from "@/lib/board.ts";
import { asksForContacts, cursorOf, readHubView } from "@/lib/view-model.ts";
import { requestViewMode } from "@/server/session.ts";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function HubPage({ params, searchParams }: Props) {
  const query = await searchParams;
  const cursor = cursorOf(query);
  if (asksForContacts(query) || cursor === null) notFound();
  const view = await readHubView(env.DB, (await params).id, requestViewMode, cursor);
  if (!view) notFound();
  return <HubBoard view={view} />;
}
