// CAP normaliser: a fixture feed item -> CapAlert keyed by (source, identifier). Refuses what it cannot parse.
import type { Area, CapAlert, FeedSource, MsgType, Severity } from "./contracts.ts";

const ISO_WITH_ZONE = /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(\.\d+)?(Z|[+-](\d\d):(\d\d))$/;
const MSG_TYPES: MsgType[] = ["alert", "update", "cancel"];
const SEVERITIES: Severity[] = ["unknown", "minor", "moderate", "severe", "extreme"];

function refuse(what: string, value: unknown): never {
  throw new Error(`CAP: bad ${what}: ${JSON.stringify(value)}`);
}

const daysIn = (year: number, month: number) =>
  month === 2 ? (year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28) : [4, 6, 9, 11].includes(month) ? 30 : 31;

// True when every component names a real date, clock time and offset. Date.parse would roll
// 2026-02-30 over to 2026-03-02 and T24:00 to the next day, so it is checked before conversion.
function realTime(m: RegExpExecArray): boolean {
  const [year, month, day, hour, minute, second] = m.slice(1, 7).map(Number);
  const [offsetHour, offsetMinute] = [m[9], m[10]].map((part) => Number(part ?? 0));
  return month >= 1 && month <= 12 && day >= 1 && day <= daysIn(year, month) &&
    hour <= 23 && minute <= 59 && second <= 59 && offsetHour <= 23 && offsetMinute <= 59;
}

// An ISO 8601 time with a zone, as UTC with milliseconds; a time without a zone is ambiguous and
// refused, and so is one that names no real instant. Every time read from input goes through here.
export function toUtc(value: unknown): string {
  const m = typeof value === "string" ? ISO_WITH_ZONE.exec(value) : null;
  if (!m || !realTime(m)) refuse("time", value);
  return new Date(m[0]).toISOString();
}

const text = (what: string, v: unknown): string => (typeof v === "string" && v.trim() !== "" ? v : refuse(what, v));
const isPoint = (p: unknown) => Array.isArray(p) && p.length === 2 && p.every((n) => Number.isFinite(n));

function area(v: unknown): Area | null {
  if (v === undefined || v === null) return null;
  const polygon = (v as { polygon?: unknown }).polygon;
  if (!Array.isArray(polygon) || polygon.length < 3 || !polygon.every(isPoint)) refuse("area", v);
  return { polygon: polygon as [number, number][] };
}

export function normalise(raw: unknown, source: FeedSource): CapAlert {
  const r = (raw ?? {}) as Record<string, unknown>;
  const msgType = (r.msgType ?? "alert") as MsgType;
  const severity = (r.severity ?? "unknown") as Severity;
  const references = r.references ?? [];
  if (!MSG_TYPES.includes(msgType)) refuse("msgType", r.msgType);
  if (!SEVERITIES.includes(severity)) refuse("severity", r.severity);
  if (!Array.isArray(references) || !references.every((x) => typeof x === "string")) refuse("references", references);
  return {
    source: source.id,
    identifier: text("identifier", r.identifier),
    msgType,
    sent: toUtc(r.sent),
    expires: r.expires === undefined || r.expires === null ? null : toUtc(r.expires),
    references,
    hazard: text("hazard", r.hazard),
    severity,
    tier: source.tier,
    headline: text("headline", r.headline),
    area: area(r.area),
  };
}
