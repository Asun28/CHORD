// Posture rules (port of HubNode Rules/PostureEngine.swift and SpatialMatch.swift). Rules only: no model call.
import type { Area, HubLocation, Observation, ObservationReader, Posture, Situation } from "./contracts.ts";

const P2_WINDOW_MS = 60 * 60 * 1000;

// Ray casting; ring points are [lon, lat]. No geometry matches no hub (fixes SpatialMatch.swift:37).
function contains(area: Area | null, hub: HubLocation): boolean {
  if (!area) return false;
  let inside = false;
  const ring = area.polygon;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if (yi > hub.lat !== yj > hub.lat && hub.lon < ((xj - xi) * (hub.lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

// Two P2 reports corroborate when they come from different sources, name the same hazard and are sent
// within 60 minutes of each other; both already cover this hub, so their areas overlap (fixes PostureEngine.swift:136).
function corroborated(p2: Observation[]): boolean {
  return p2.some((a) =>
    p2.some((b) => a.source !== b.source && a.hazard === b.hazard && Math.abs(Date.parse(a.sent) - Date.parse(b.sent)) <= P2_WINDOW_MS),
  );
}

function posture(matched: Observation[]): Posture {
  const strong = matched.filter((o) => o.tier === "P0" || o.tier === "P1");
  if (strong.some((o) => o.severity === "severe" || o.severity === "extreme")) return "respond";
  if (strong.some((o) => o.severity === "moderate")) return "act";
  if (strong.length > 0) return "watch";
  return corroborated(matched.filter((o) => o.tier === "P2")) ? "watch" : "green";
}

// Posture of one hub at a replay cursor; a store read that fails gives "error", never green.
export async function hubPosture(reader: ObservationReader, hub: HubLocation, cursor: string): Promise<Situation> {
  let active: Observation[];
  try {
    active = await reader.activeAt(cursor);
  } catch {
    return { hubId: hub.id, cursor, posture: "error" };
  }
  const matched = active.filter((o) => o.msgType !== "cancel" && contains(o.area, hub));
  return { hubId: hub.id, cursor, posture: posture(matched) };
}
