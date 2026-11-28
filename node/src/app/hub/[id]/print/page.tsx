// GET /hub/[id]/print?at= : the hub on one A4 page. Always the public view (R3): a printed sheet leaves
// the hall, so no restricted asset is printed in any session, the coordinator's included.
import { env } from "cloudflare:workers";
import { notFound } from "next/navigation";
import { PrintSheet } from "@/lib/board.ts";
import { asksForContacts, cursorOf, readHubView } from "@/lib/view-model.ts";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function PrintPage({ params, searchParams }: Props) {
  const query = await searchParams;
  const cursor = cursorOf(query);
  if (asksForContacts(query) || cursor === null) notFound();
  const view = await readHubView(env.DB, (await params).id, async () => "public", cursor);
  if (!view) notFound();
  return <PrintSheet view={view} renderedAt={new Date().toISOString()} />;
}
