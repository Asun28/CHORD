// Frozen contracts (plan section 6): changed only by an amendment to the plan.
export type { Asset, Hub, Role, TaskTemplate } from "./corpus.ts";

export type TrustTier = "P0" | "P1" | "P2" | "P3";
export type MsgType = "alert" | "update" | "cancel";
export type Severity = "unknown" | "minor" | "moderate" | "severe" | "extreme";
export type Posture = "green" | "watch" | "act" | "respond" | "error";
export type ViewMode = "public" | "coordinator";

// CAP area: one polygon ring of [lon, lat] pairs, at least 3 points.
export interface Area {
  polygon: [number, number][];
}

// One normalised CAP message; identity is (source, identifier). Times are ISO 8601 UTC.
export interface CapAlert {
  source: string;
  identifier: string;
  msgType: MsgType;
  sent: string;
  expires: string | null;
  references: string[]; // CAP identifiers of earlier messages from the same source
  hazard: string;
  severity: Severity;
  tier: TrustTier;
  headline: string;
  area: Area | null;
}

export interface Observation extends CapAlert {
  fetchedAt: string;
}

export interface FeedSource {
  id: string;
  name: string;
  cadence_seconds: number;
  tier: TrustTier;
}

// Messages active at a replay cursor; the D1 store implements it.
export interface ObservationReader {
  activeAt(cursor: string): Promise<Observation[]>;
}

// The corpus has no hub coordinates yet; the caller supplies the point.
export interface HubLocation {
  id: string;
  lat: number;
  lon: number;
}

export interface Situation {
  hubId: string;
  cursor: string;
  posture: Posture;
}
