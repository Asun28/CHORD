import type { HubLocation, ObservationReader, Situation } from "./contracts.ts";

export async function hubPosture(reader: ObservationReader, hub: HubLocation, cursor: string): Promise<Situation> {
  return { hubId: hub.id, cursor, posture: "green" };
}
