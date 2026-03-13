import type { createAdminClient } from "./supabase.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

export type OtpRateAction =
  | "send_ip"
  | "send_phone"
  | "verify_ip"
  | "verify_phone";

export type OtpRateEventInput = {
  action: OtpRateAction;
  actorKey: string;
  outcome: string;
  phone?: string | null;
  metadata?: Record<string, unknown>;
};

export function extractClientIp(request: Request): string | null {
  const candidates = [
    request.headers.get("cf-connecting-ip"),
    request.headers.get("x-real-ip"),
    request.headers.get("fly-client-ip"),
    request.headers.get("x-forwarded-for")?.split(",")[0],
  ];

  for (const candidate of candidates) {
    const trimmed = candidate?.trim();
    if (trimmed) {
      return trimmed;
    }
  }

  return null;
}

export async function hashOtpRateActorKey(rawValue: string): Promise<string> {
  const payload = new TextEncoder().encode(rawValue.trim().toLowerCase());
  const digest = await crypto.subtle.digest("SHA-256", payload);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function countRecentOtpRateEvents(
  adminClient: AdminClient,
  options: {
    action: OtpRateAction;
    actorKey: string;
    windowStartIso: string;
  },
) {
  const result = await adminClient
    .from("otp_rate_events")
    .select("id", { count: "exact", head: true })
    .eq("action", options.action)
    .eq("actor_key", options.actorKey)
    .gte("created_at", options.windowStartIso);

  if (result.error) {
    throw result.error;
  }

  return result.count ?? 0;
}

export async function recordOtpRateEvent(
  adminClient: AdminClient,
  event: OtpRateEventInput,
) {
  const { error } = await adminClient
    .from("otp_rate_events")
    .insert({
      action: event.action,
      actor_key: event.actorKey,
      outcome: normalizeOutcome(event.outcome),
      phone: normalizePhone(event.phone),
      metadata: event.metadata ?? {},
    });

  if (error) {
    throw error;
  }
}

function normalizeOutcome(value: string) {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error("OTP rate event outcome is required");
  }
  return trimmed;
}

function normalizePhone(value: string | null | undefined) {
  if (typeof value != "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
