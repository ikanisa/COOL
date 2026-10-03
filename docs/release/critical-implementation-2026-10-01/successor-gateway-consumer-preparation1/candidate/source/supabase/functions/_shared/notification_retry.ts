// Firebase recommends >=10s requests, >=60s for quota failures and jitter.
// Apple recommends >=15 minutes before retrying 5xx notification responses.
// Provider floors are persisted by the fenced completion RPC; no inline retry.
export const maximumRetryAfterSeconds = 3600;

export function retryAfterSeconds(
  header: string | null,
  now = Date.now(),
): number | null {
  if (header === null) return null;
  const value = header.trim();
  if (!value || value.length > 128) return null;
  let seconds: number;
  if (/^\d+$/.test(value)) {
    seconds = Number(value);
  } else {
    // Accept HTTP-date, not JavaScript's permissive parsing of numeric strings.
    if (
      !/^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4} \d{2}:\d{2}:\d{2} GMT$/
        .test(value)
    ) return null;
    const date = Date.parse(value);
    if (!Number.isFinite(date)) return null;
    seconds = Math.max(0, Math.ceil((date - now) / 1000));
  }
  // An excessive provider floor must NOT be clipped into an earlier send.
  // This sentinel terminalizes the attempt for operator review in SQL.
  return Math.min(maximumRetryAfterSeconds + 1, seconds);
}

export function providerRetryFloor(
  provider: "fcm" | "apns",
  status: number,
  header: string | null,
  now = Date.now(),
): number | null {
  const retryable = status === 429 || status >= 500 ||
    (provider === "fcm" && status === 408);
  if (!retryable) return null;
  const providerMinimum = provider === "apns" && status >= 500
    ? 900
    : status === 429
    ? 60
    : 10;
  return Math.max(providerMinimum, retryAfterSeconds(header, now) ?? 0);
}

export const genericPushTitle = "Collect";
export const genericPushBody = "Open Collect to view your updates";

export function requirePushRecipient(recipientId: string): void {
  if (
    typeof recipientId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(recipientId)
  ) {
    throw new Error("notification_recipient_required");
  }
}
