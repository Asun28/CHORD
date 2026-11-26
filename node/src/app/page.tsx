import { env } from "cloudflare:workers";
import { HomeBoard, readHomeBoard } from "@/lib/board.ts";

export const dynamic = "force-dynamic";

export default async function Home() {
  return <HomeBoard board={await readHomeBoard(env.DB)} />;
}
