import { env } from "cloudflare:workers";
import { HomeBoard } from "@/lib/board.ts";
import { AssetList, asksForContacts, readHubView } from "@/lib/view-model.ts";
import { requestViewMode } from "@/server/session.ts";

export const dynamic = "force-dynamic";

type Props = { searchParams?: Promise<Record<string, string | string[] | undefined>> };

export default async function Home({ searchParams }: Props = {}) {
  if (asksForContacts(await searchParams)) (await import("next/navigation")).notFound();
  const view = await readHubView(env.DB, null, await requestViewMode());
  if (!view) throw new Error("No home hub in D1: run npm run db:migrate and npm run db:seed");
  return (
    <>
      <HomeBoard board={view.board} />
      <AssetList assets={view.assets} />
    </>
  );
}
