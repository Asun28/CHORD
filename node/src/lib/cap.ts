import type { CapAlert, FeedSource } from "./contracts.ts";

export function normalise(raw: unknown, source: FeedSource): CapAlert {
  return { ...(raw as CapAlert), source: source.id };
}
