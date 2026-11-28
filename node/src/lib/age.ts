// RED stub: replaced in GREEN.
export interface FactAge { ageSeconds: number; fetchAgeSeconds: number; stale: boolean }
export function factAge(_observedAt: string, _lastFetch: string, _cadenceSeconds: number, _cursor: string): FactAge {
  return { ageSeconds: 0, fetchAgeSeconds: 0, stale: false };
}
export function ageLabel(_seconds: number): string {
  return "";
}
