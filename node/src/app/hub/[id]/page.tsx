// GET /hub/[id]?at= : one hub's board in the request's view mode. The `at` cursor is read by T1-NODE-HALL-PRINT.
import { env } from "cloudflare:workers";
import { notFound } from "next/navigation";
import { HomeBoard } from "@/lib/board.ts";
import { AssetList, asksForContacts, readHubView } from "@/lib/view-model.ts";
import { requestViewMode } from "@/server/session.ts";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function HubPage({ params, searchParams }: Props) {
  if (asksForContacts(await searchParams)) notFound();
  const view = await readHubView(env.DB, (await params).id, await requestViewMode());
  if (!view) notFound();
  return (
    <>
      <HomeBoard board={view.board} />
      <AssetList assets={view.assets} />
    </>
  );
}
