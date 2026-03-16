export const approvedSenderTokens = new Set([
  "mmoney",
  "mmoneyalerts",
  "mobilemoney",
  "momo",
  "momoalerts",
  "mtnmomo",
  "mtnmomorwanda",
]);

export const allowedIngestionSources = new Set([
  "android_sms_listener",
  "android_sms_listener_foreground",
  "android_sms_listener_background",
  "android_sms_initial_sync",
  "android_sms_manual_sync",
]);

export function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  return null;
}

export function normalizeWhitespace(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

export function normalizeSender(value: string): string {
  return value.toLowerCase().trim().replaceAll(/[^a-z0-9]/g, "");
}

export function isApprovedSender(value: string): boolean {
  return approvedSenderTokens.has(normalizeSender(value));
}

export function parseReceivedAt(
  value: string | null,
  fallbackNow: Date = new Date(),
): string {
  if (!value) {
    return fallbackNow.toISOString();
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? fallbackNow.toISOString()
    : parsed.toISOString();
}

export function normalizeIngestionSource(value: unknown): string {
  const rawValue = asString(value)?.toLowerCase();
  return rawValue && allowedIngestionSources.has(rawValue)
    ? rawValue
    : "android_sms_listener";
}

export async function buildDeviceMessageKey(options: {
  sender: string;
  smsBody: string;
  smsReceivedAt: string;
}) {
  const payload = [
    normalizeSender(options.sender),
    options.smsReceivedAt,
    normalizeWhitespace(options.smsBody),
  ].join("|");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(payload),
  );

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
