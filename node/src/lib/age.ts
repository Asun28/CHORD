// Fact age at the replay cursor (R1): the observation's age, its feed's fetch age, and stale when the
// observation is older than three source cadences at the cursor (parent spec R10, HubNode AgeBadge.swift).
export interface FactAge { ageSeconds: number; fetchAgeSeconds: number; stale: boolean }

const STALE_CADENCES = 3;
const secondsBetween = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / 1000);

export function factAge(observedAt: string, lastFetch: string, cadenceSeconds: number, cursor: string): FactAge {
  const ageSeconds = secondsBetween(observedAt, cursor);
  return { ageSeconds, fetchAgeSeconds: secondsBetween(lastFetch, cursor), stale: ageSeconds > STALE_CADENCES * cadenceSeconds };
}

// A replay cursor can lie before a fetch; that age is negative and reads as after the cursor.
export function ageLabel(seconds: number): string {
  if (seconds < 0) return "after the cursor";
  const [h, m, s] = [Math.floor(seconds / 3600), Math.floor((seconds % 3600) / 60), seconds % 60];
  return h > 0 ? `${h}h ${m}m ago` : `${m}m ${s}s ago`;
}
