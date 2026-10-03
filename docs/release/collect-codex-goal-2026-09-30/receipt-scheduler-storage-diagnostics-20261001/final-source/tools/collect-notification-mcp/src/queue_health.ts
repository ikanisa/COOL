const countNames = ["queued", "awaiting_confirmation", "send_started", "uncertain", "suppressed", "active_workers"] as const;
type QueueHealth = {enabled: boolean} & Record<typeof countNames[number], number>;

// Both connection paths require actual queue counts before reporting readiness.
// Return only the bounded aggregate fields, never arbitrary backend properties.
export function queueHealth(value: unknown): QueueHealth {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("RESPONSE_SHAPE");
  const row = value as Record<string, unknown>;
  if (typeof row.enabled !== "boolean" || countNames.some(name =>
    !Number.isSafeInteger(row[name]) || Number(row[name]) < 0)) throw new Error("RESPONSE_SHAPE");
  return {enabled: row.enabled, ...Object.fromEntries(countNames.map(name => [name, row[name]]))} as QueueHealth;
}
