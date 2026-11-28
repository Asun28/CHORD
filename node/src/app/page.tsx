import { env } from "cloudflare:workers";
import { HubBoard } from "@/lib/board.ts";
import { asksForContacts, cursorOf, readHubView } from "@/lib/view-model.ts";
import { requestViewMode } from "@/server/session.ts";

export const dynamic = "force-dynamic";

type Props = { searchParams?: Promise<Record<string, string | string[] | undefined>> };

// GET /?at= : the home hub's board at the replay cursor (now when `at` is absent).
export default async function Home({ searchParams }: Props = {}) {
  const query = await searchParams;
  const cursor = cursorOf(query);
  if (asksForContacts(query) || cursor === null) (await import("next/navigation")).notFound();
  const view = await readHubView(env.DB, null, await requestViewMode(), cursor!);
  if (!view) throw new Error("No home hub in D1: run npm run db:migrate and npm run db:seed");
  return <HubBoard view={view} />;
}
