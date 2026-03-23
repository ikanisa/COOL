import type { createAdminClient } from "./supabase.ts";
import { extractClientIp, hashOtpRateActorKey } from "./otp_abuse.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

export type BiopayMatchRateScope = "user" | "ip";
export type BiopayMatchRateOutcome =
  | "match"
  | "miss"
  | "blocked_user_rate_limit"
  | "blocked_ip_rate_limit"
  | "lockout_started"
  | "blocked_lockout";

export type BiopayMatchProtectionConfig = {
  threshold: number;
  rateWindowSeconds: number;
  userMaxAttempts: number;
  ipMaxAttempts: number;
  missWindowSeconds: number;
  maxMissesPerWindow: number;
  lockoutSeconds: number;
};

const defaultBiopayMatchProtectionConfig: BiopayMatchProtectionConfig = {
  threshold: 0.72,
  rateWindowSeconds: 60,
  userMaxAttempts: 8,
  ipMaxAttempts: 20,
  missWindowSeconds: 600,
  maxMissesPerWindow: 5,
  lockoutSeconds: 900,
};

const protectionConfigKeys = [
  "biopay_match_threshold",
  "biopay_match_rate_window_seconds",
  "biopay_match_user_max_attempts",
  "biopay_match_ip_max_attempts",
  "biopay_match_miss_window_seconds",
  "biopay_match_miss_lockout_threshold",
  "biopay_match_lockout_seconds",
] as const;

function parsePositiveInteger(
  rawValue: string | undefined,
  fallback: number,
): number {
  const parsed = Number.parseInt(rawValue ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function parseThreshold(
  rawValue: string | undefined,
  fallback: number,
): number {
  const parsed = Number(rawValue ?? "");
  return Number.isFinite(parsed) && parsed > 0 && parsed <= 1
    ? parsed
    : fallback;
}

export async function getBiopayMatchProtectionConfig(
  adminClient: AdminClient,
): Promise<BiopayMatchProtectionConfig> {
  const { data, error } = await adminClient
    .from("app_config")
    .select("key, value")
    .in("key", [...protectionConfigKeys]);

  if (error) {
    throw error;
  }

  const values = new Map<string, string>();
  for (const row of data ?? []) {
    const key = row.key?.toString().trim();
    const value = row.value?.toString().trim();
    if (key && value) {
      values.set(key, value);
    }
  }

  return {
    threshold: parseThreshold(
      values.get("biopay_match_threshold"),
      defaultBiopayMatchProtectionConfig.threshold,
    ),
    rateWindowSeconds: parsePositiveInteger(
      values.get("biopay_match_rate_window_seconds"),
      defaultBiopayMatchProtectionConfig.rateWindowSeconds,
    ),
    userMaxAttempts: parsePositiveInteger(
      values.get("biopay_match_user_max_attempts"),
      defaultBiopayMatchProtectionConfig.userMaxAttempts,
    ),
    ipMaxAttempts: parsePositiveInteger(
      values.get("biopay_match_ip_max_attempts"),
      defaultBiopayMatchProtectionConfig.ipMaxAttempts,
    ),
    missWindowSeconds: parsePositiveInteger(
      values.get("biopay_match_miss_window_seconds"),
      defaultBiopayMatchProtectionConfig.missWindowSeconds,
    ),
    maxMissesPerWindow: parsePositiveInteger(
      values.get("biopay_match_miss_lockout_threshold"),
      defaultBiopayMatchProtectionConfig.maxMissesPerWindow,
    ),
    lockoutSeconds: parsePositiveInteger(
      values.get("biopay_match_lockout_seconds"),
      defaultBiopayMatchProtectionConfig.lockoutSeconds,
    ),
  };
}

export async function countRecentBiopayMatchRateEvents(
  adminClient: AdminClient,
  options: {
    scope: BiopayMatchRateScope;
    actorKey: string;
    windowStartIso: string;
    outcomes?: readonly BiopayMatchRateOutcome[];
  },
): Promise<number> {
  let query = adminClient
    .from("biopay_match_rate_events")
    .select("id", { count: "exact", head: true })
    .eq("scope", options.scope)
    .eq("actor_key", options.actorKey)
    .gte("created_at", options.windowStartIso);

  if ((options.outcomes?.length ?? 0) == 1) {
    query = query.eq("outcome", options.outcomes![0]);
  } else if ((options.outcomes?.length ?? 0) > 1) {
    query = query.in("outcome", [...options.outcomes!]);
  }

  const result = await query;
  if (result.error) {
    throw result.error;
  }

  return result.count ?? 0;
}

export async function getLatestBiopayMatchRateEventAt(
  adminClient: AdminClient,
  options: {
    scope: BiopayMatchRateScope;
    actorKey: string;
    outcome: BiopayMatchRateOutcome;
    windowStartIso: string;
  },
): Promise<string | null> {
  const { data, error } = await adminClient
    .from("biopay_match_rate_events")
    .select("created_at")
    .eq("scope", options.scope)
    .eq("actor_key", options.actorKey)
    .eq("outcome", options.outcome)
    .gte("created_at", options.windowStartIso)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const createdAt = data?.created_at?.toString().trim();
  return createdAt?.length ? createdAt : null;
}

export async function hashBiopayMatchActorKey(rawValue: string) {
  return await hashOtpRateActorKey(rawValue);
}

export async function recordBiopayMatchRateEvent(
  adminClient: AdminClient,
  event: {
    scope: BiopayMatchRateScope;
    actorKey: string;
    requesterUserId: string;
    outcome: BiopayMatchRateOutcome;
    metadata?: Record<string, unknown>;
  },
) {
  const { error } = await adminClient
    .from("biopay_match_rate_events")
    .insert({
      scope: event.scope,
      actor_key: event.actorKey,
      requester_user_id: event.requesterUserId,
      outcome: event.outcome,
      metadata: event.metadata ?? {},
    });

  if (error) {
    throw error;
  }
}

export { extractClientIp };
