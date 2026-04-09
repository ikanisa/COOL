import {
  type BiopayMatchProtectionConfig,
  type BiopayMatchRateOutcome,
} from "../_shared/biopay_match_abuse.ts";
import type { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";

export type AdminClientLike = unknown;
export type UserClientLike = {
  auth: {
    getUser(): Promise<{
      data: { user: { id: string } | null };
      error: unknown;
    }>;
  };
};

export type MatchRequest = {
  embedding?: unknown;
  liveness?: unknown;
};

export type BiopayMatchRow = Record<string, unknown> & {
  profile_id?: unknown;
  score?: unknown;
  route_type?: unknown;
  public_id?: unknown;
  user_id?: unknown;
  display_name?: unknown;
  recipient_value?: unknown;
  country_code?: unknown;
  consent_version?: unknown;
  consent_at?: unknown;
  created_at?: unknown;
  updated_at?: unknown;
};

export type MatchEventInsert = {
  requesterUserId: string;
  matchedProfileId: string | null;
  matched: boolean;
  score: number;
  thresholdUsed: number;
  metadata: Record<string, unknown>;
};

export class BiopayValidationError extends Error {}

export function sanitizeHeaderValue(
  value: string | null,
  maxLength = 180,
): string | null {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }

  return trimmed.slice(0, maxLength);
}

export function isoBefore(now: Date, seconds: number) {
  return new Date(now.getTime() - seconds * 1000).toISOString();
}

export function isoAfter(startIso: string, seconds: number) {
  return new Date(Date.parse(startIso) + seconds * 1000).toISOString();
}

export function secondsUntil(targetIso: string, now: Date) {
  return Math.max(1, Math.ceil((Date.parse(targetIso) - now.getTime()) / 1000));
}

async function runMatchRpc(
  adminClient: AdminClientLike,
  embedding: number[],
) {
  const { data, error } = await (adminClient as ReturnType<
    typeof createAdminClient
  >).rpc("match_biopay_profile", {
    p_embedding: embedding,
  });

  if (error) {
    throw error;
  }

  const row = Array.isArray(data) ? data[0] : data;
  return row ? row as BiopayMatchRow : null;
}

async function insertMatchEvent(
  adminClient: AdminClientLike,
  event: MatchEventInsert,
) {
  const { error } = await (adminClient as ReturnType<
    typeof createAdminClient
  >).from("biopay_match_events").insert({
    requester_user_id: event.requesterUserId,
    matched_profile_id: event.matchedProfileId,
    matched: event.matched,
    score: event.score,
    threshold_used: event.thresholdUsed,
    metadata: event.metadata,
  });

  if (error) {
    throw error;
  }
}

export function createDefaultBiopayMatchDependencies(options: {
  createAdminClient: typeof createAdminClient;
  createUserClient: (authorization: string) => UserClientLike;
  requireAppCheckToken: (request: Request) => Promise<string>;
  getProtectionConfig: (
    adminClient: ReturnType<typeof createAdminClient>,
  ) => Promise<BiopayMatchProtectionConfig>;
  countRecentRateEvents: (
    adminClient: ReturnType<typeof createAdminClient>,
    options: {
      scope: "user" | "ip";
      actorKey: string;
      windowStartIso: string;
      outcomes?: readonly BiopayMatchRateOutcome[];
    },
  ) => Promise<number>;
  getLatestRateEventAt: (
    adminClient: ReturnType<typeof createAdminClient>,
    options: {
      scope: "user" | "ip";
      actorKey: string;
      outcome: BiopayMatchRateOutcome;
      windowStartIso: string;
    },
  ) => Promise<string | null>;
  recordRateEvent: (
    adminClient: ReturnType<typeof createAdminClient>,
    event: {
      scope: "user" | "ip";
      actorKey: string;
      requesterUserId: string;
      outcome: BiopayMatchRateOutcome;
      metadata?: Record<string, unknown>;
    },
  ) => Promise<void>;
  recordOperationalHealthEvent: (
    adminClient: ReturnType<typeof createAdminClient>,
    event: Parameters<
      typeof import("../_shared/observability.ts").recordOperationalHealthEvent
    >[1],
  ) => Promise<void>;
  recordEdgeFunctionFailure: (
    adminClient: ReturnType<typeof createAdminClient>,
    options: Parameters<typeof recordEdgeFunctionFailure>[1],
  ) => Promise<void>;
}) {
  return {
    createAdminClient: options.createAdminClient,
    createUserClient: options.createUserClient,
    requireAppCheckToken: options.requireAppCheckToken,
    now: () => new Date(),
    getProtectionConfig: (adminClient: AdminClientLike) =>
      options.getProtectionConfig(
        adminClient as ReturnType<typeof createAdminClient>,
      ),
    countRecentRateEvents: (
      adminClient: AdminClientLike,
      config: {
        scope: "user" | "ip";
        actorKey: string;
        windowStartIso: string;
        outcomes?: readonly BiopayMatchRateOutcome[];
      },
    ) =>
      options.countRecentRateEvents(
        adminClient as ReturnType<typeof createAdminClient>,
        config,
      ),
    getLatestRateEventAt: (
      adminClient: AdminClientLike,
      config: {
        scope: "user" | "ip";
        actorKey: string;
        outcome: BiopayMatchRateOutcome;
        windowStartIso: string;
      },
    ) =>
      options.getLatestRateEventAt(
        adminClient as ReturnType<typeof createAdminClient>,
        config,
      ),
    recordRateEvent: (
      adminClient: AdminClientLike,
      event: {
        scope: "user" | "ip";
        actorKey: string;
        requesterUserId: string;
        outcome: BiopayMatchRateOutcome;
        metadata?: Record<string, unknown>;
      },
    ) =>
      options.recordRateEvent(
        adminClient as ReturnType<typeof createAdminClient>,
        event,
      ),
    recordOperationalHealthEvent: (
      adminClient: AdminClientLike,
      event: Parameters<
        typeof import("../_shared/observability.ts").recordOperationalHealthEvent
      >[1],
    ) =>
      options.recordOperationalHealthEvent(
        adminClient as ReturnType<typeof createAdminClient>,
        event,
      ),
    recordEdgeFunctionFailure: (
      adminClient: AdminClientLike,
      event: Parameters<typeof recordEdgeFunctionFailure>[1],
    ) =>
      options.recordEdgeFunctionFailure(
        adminClient as ReturnType<typeof createAdminClient>,
        event,
      ),
    runMatchRpc,
    insertMatchEvent,
  };
}
