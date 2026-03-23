import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { HttpError } from "../_shared/auth.ts";
import { requireAppCheckToken } from "../_shared/app_check.ts";
import { normalizeBiopayLivenessMetadata } from "../_shared/biopay_liveness.ts";
import {
  countRecentBiopayMatchRateEvents,
  extractClientIp,
  getBiopayMatchProtectionConfig,
  getLatestBiopayMatchRateEventAt,
  hashBiopayMatchActorKey,
  recordBiopayMatchRateEvent,
} from "../_shared/biopay_match_abuse.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import type {
  BiopayMatchProtectionConfig,
  BiopayMatchRateOutcome,
} from "../_shared/biopay_match_abuse.ts";

type AdminClientLike = unknown;
type UserClientLike = {
  auth: {
    getUser(): Promise<{
      data: { user: { id: string } | null };
      error: unknown;
    }>;
  };
};

type MatchRequest = {
  embedding?: unknown;
  liveness?: unknown;
};

type BiopayMatchRow = Record<string, unknown> & {
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

type MatchEventInsert = {
  requesterUserId: string;
  matchedProfileId: string | null;
  matched: boolean;
  score: number;
  thresholdUsed: number;
  metadata: Record<string, unknown>;
};

export type BiopayMatchHandlerDependencies = {
  createAdminClient: () => AdminClientLike;
  createUserClient: (authorization: string) => UserClientLike;
  requireAppCheckToken: (request: Request) => Promise<string>;
  now: () => Date;
  getProtectionConfig: (
    adminClient: AdminClientLike,
  ) => Promise<BiopayMatchProtectionConfig>;
  countRecentRateEvents: (
    adminClient: AdminClientLike,
    options: {
      scope: "user" | "ip";
      actorKey: string;
      windowStartIso: string;
      outcomes?: readonly BiopayMatchRateOutcome[];
    },
  ) => Promise<number>;
  getLatestRateEventAt: (
    adminClient: AdminClientLike,
    options: {
      scope: "user" | "ip";
      actorKey: string;
      outcome: BiopayMatchRateOutcome;
      windowStartIso: string;
    },
  ) => Promise<string | null>;
  recordRateEvent: (
    adminClient: AdminClientLike,
    event: {
      scope: "user" | "ip";
      actorKey: string;
      requesterUserId: string;
      outcome: BiopayMatchRateOutcome;
      metadata?: Record<string, unknown>;
    },
  ) => Promise<void>;
  recordOperationalHealthEvent: (
    adminClient: AdminClientLike,
    event: Parameters<typeof recordOperationalHealthEvent>[1],
  ) => Promise<void>;
  recordEdgeFunctionFailure: (
    adminClient: AdminClientLike,
    options: Parameters<typeof recordEdgeFunctionFailure>[1],
  ) => Promise<void>;
  runMatchRpc: (
    adminClient: AdminClientLike,
    embedding: number[],
  ) => Promise<BiopayMatchRow | null>;
  insertMatchEvent: (
    adminClient: AdminClientLike,
    event: MatchEventInsert,
  ) => Promise<void>;
};

class BiopayValidationError extends Error {}

function normalizeEmbedding(input: unknown): number[] {
  if (!Array.isArray(input) || input.length !== 128) {
    throw new BiopayValidationError(
      "BioPay embedding must contain exactly 128 values.",
    );
  }

  return input.map((value) => {
    const numberValue = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(numberValue)) {
      throw new BiopayValidationError(
        "BioPay embedding contains a non-numeric value.",
      );
    }
    return numberValue;
  });
}

function sanitizeHeaderValue(
  value: string | null,
  maxLength = 180,
): string | null {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }

  return trimmed.slice(0, maxLength);
}

function isoBefore(now: Date, seconds: number) {
  return new Date(now.getTime() - seconds * 1000).toISOString();
}

function isoAfter(startIso: string, seconds: number) {
  return new Date(Date.parse(startIso) + seconds * 1000).toISOString();
}

function secondsUntil(targetIso: string, now: Date) {
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

const defaultDependencies: BiopayMatchHandlerDependencies = {
  createAdminClient,
  createUserClient,
  requireAppCheckToken,
  now: () => new Date(),
  getProtectionConfig: (adminClient) =>
    getBiopayMatchProtectionConfig(
      adminClient as ReturnType<typeof createAdminClient>,
    ),
  countRecentRateEvents: (adminClient, options) =>
    countRecentBiopayMatchRateEvents(
      adminClient as ReturnType<typeof createAdminClient>,
      options,
    ),
  getLatestRateEventAt: (adminClient, options) =>
    getLatestBiopayMatchRateEventAt(
      adminClient as ReturnType<typeof createAdminClient>,
      options,
    ),
  recordRateEvent: (adminClient, event) =>
    recordBiopayMatchRateEvent(
      adminClient as ReturnType<typeof createAdminClient>,
      event,
    ),
  recordOperationalHealthEvent: (adminClient, event) =>
    recordOperationalHealthEvent(
      adminClient as ReturnType<typeof createAdminClient>,
      event,
    ),
  recordEdgeFunctionFailure: (adminClient, options) =>
    recordEdgeFunctionFailure(
      adminClient as ReturnType<typeof createAdminClient>,
      options,
    ),
  runMatchRpc,
  insertMatchEvent,
};

export function createBiopayMatchHandler(
  dependencies: Partial<BiopayMatchHandlerDependencies> = {},
) {
  const deps: BiopayMatchHandlerDependencies = {
    ...defaultDependencies,
    ...dependencies,
  };

  return async (request: Request) => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method !== "POST") {
      return methodNotAllowed("POST");
    }

    const adminClient = deps.createAdminClient();
    let requesterUserId: string | null = null;

    try {
      const authorization = request.headers.get("authorization") ??
        request.headers.get("Authorization");
      if (!authorization) {
        return errorResponse("Missing authorization header.", 401);
      }

      const userClient = deps.createUserClient(authorization);
      const { data: authData, error: authError } = await userClient.auth
        .getUser();
      if (authError || !authData.user) {
        return errorResponse("Unauthorized.", 401);
      }

      requesterUserId = authData.user.id;
      await deps.requireAppCheckToken(request);

      const now = deps.now();
      const body = await request.json() as MatchRequest;
      const embedding = normalizeEmbedding(body.embedding);
      const liveness = normalizeBiopayLivenessMetadata(body.liveness);
      const protectionConfig = await deps.getProtectionConfig(adminClient);
      const clientIp = extractClientIp(request);
      const userActorKey = await hashBiopayMatchActorKey(
        `match_user:${requesterUserId}`,
      );
      const ipActorKey = clientIp == null
        ? null
        : await hashBiopayMatchActorKey(`match_ip:${clientIp}`);
      const telemetryMetadata = {
        ip_actor_key: ipActorKey,
        user_actor_key: userActorKey,
        client_info: sanitizeHeaderValue(request.headers.get("x-client-info")),
        user_agent: sanitizeHeaderValue(request.headers.get("user-agent")),
        liveness,
        app_check_enforced: true,
      };
      const rateWindowStartIso = isoBefore(
        now,
        protectionConfig.rateWindowSeconds,
      );
      const missWindowStartIso = isoBefore(
        now,
        protectionConfig.missWindowSeconds,
      );
      const lockoutWindowStartIso = isoBefore(
        now,
        protectionConfig.lockoutSeconds,
      );

      const latestLockoutAt = await deps.getLatestRateEventAt(adminClient, {
        scope: "user",
        actorKey: userActorKey,
        outcome: "lockout_started",
        windowStartIso: lockoutWindowStartIso,
      });

      if (latestLockoutAt) {
        const lockoutUntil = isoAfter(
          latestLockoutAt,
          protectionConfig.lockoutSeconds,
        );
        if (Date.parse(lockoutUntil) > now.getTime()) {
          const retryAfterSeconds = secondsUntil(lockoutUntil, now);
          await deps.recordRateEvent(adminClient, {
            scope: "user",
            actorKey: userActorKey,
            requesterUserId,
            outcome: "blocked_lockout",
            metadata: {
              ...telemetryMetadata,
              lockout_until: lockoutUntil,
              retry_after_seconds: retryAfterSeconds,
            },
          });
          await deps.recordOperationalHealthEvent(adminClient, {
            service: "biopay",
            component: "matching",
            status: "warn",
            severity: "warning",
            issueCode: "biopay_match_locked_out",
            message: "BioPay match request blocked by an active user lockout.",
            functionName: "biopay-match",
            userId: requesterUserId,
            subjectType: "biopay_match_request",
            metadata: {
              ...telemetryMetadata,
              lockout_until: lockoutUntil,
            },
          });
          return errorResponse(
            "Too many failed BioPay match attempts. Please wait before trying again.",
            423,
            { retryAfterSeconds, lockoutUntil },
          );
        }
      }

      const recentUserAttempts = await deps.countRecentRateEvents(adminClient, {
        scope: "user",
        actorKey: userActorKey,
        windowStartIso: rateWindowStartIso,
        outcomes: ["match", "miss"],
      });

      if (recentUserAttempts >= protectionConfig.userMaxAttempts) {
        await deps.recordRateEvent(adminClient, {
          scope: "user",
          actorKey: userActorKey,
          requesterUserId,
          outcome: "blocked_user_rate_limit",
          metadata: {
            ...telemetryMetadata,
            limit: protectionConfig.userMaxAttempts,
            window_seconds: protectionConfig.rateWindowSeconds,
          },
        });
        await deps.recordOperationalHealthEvent(adminClient, {
          service: "biopay",
          component: "matching",
          status: "warn",
          severity: "warning",
          issueCode: "biopay_match_user_rate_limited",
          message: "BioPay match request blocked by the user attempt budget.",
          functionName: "biopay-match",
          userId: requesterUserId,
          subjectType: "biopay_match_request",
          metadata: {
            ...telemetryMetadata,
            attempt_count: recentUserAttempts,
            limit: protectionConfig.userMaxAttempts,
          },
        });
        return errorResponse(
          "Too many BioPay match attempts. Please wait a moment before trying again.",
          429,
          { retryAfterSeconds: protectionConfig.rateWindowSeconds },
        );
      }

      if (ipActorKey != null) {
        const recentIpAttempts = await deps.countRecentRateEvents(adminClient, {
          scope: "ip",
          actorKey: ipActorKey,
          windowStartIso: rateWindowStartIso,
          outcomes: ["match", "miss"],
        });

        if (recentIpAttempts >= protectionConfig.ipMaxAttempts) {
          await deps.recordRateEvent(adminClient, {
            scope: "ip",
            actorKey: ipActorKey,
            requesterUserId,
            outcome: "blocked_ip_rate_limit",
            metadata: {
              ...telemetryMetadata,
              limit: protectionConfig.ipMaxAttempts,
              window_seconds: protectionConfig.rateWindowSeconds,
            },
          });
          await deps.recordOperationalHealthEvent(adminClient, {
            service: "biopay",
            component: "matching",
            status: "warn",
            severity: "warning",
            issueCode: "biopay_match_ip_rate_limited",
            message: "BioPay match request blocked by the IP attempt budget.",
            functionName: "biopay-match",
            userId: requesterUserId,
            subjectType: "biopay_match_request",
            metadata: {
              ...telemetryMetadata,
              attempt_count: recentIpAttempts,
              limit: protectionConfig.ipMaxAttempts,
            },
          });
          return errorResponse(
            "Too many BioPay match attempts. Please wait a moment before trying again.",
            429,
            { retryAfterSeconds: protectionConfig.rateWindowSeconds },
          );
        }
      }

      const row = await deps.runMatchRpc(adminClient, embedding);
      const score = Number(row?.score ?? 0);
      const normalizedScore = Number.isFinite(score) ? score : 0;
      const hasMatch = !!row &&
        normalizedScore >= protectionConfig.threshold &&
        row.profile_id != null;
      const outcome: BiopayMatchRateOutcome = hasMatch ? "match" : "miss";
      const decisionMetadata = {
        ...telemetryMetadata,
        decision_version: "biopay-match-v2",
        route_type: row?.route_type ?? null,
        public_id: row?.public_id ?? null,
      };

      try {
        await deps.insertMatchEvent(adminClient, {
          requesterUserId,
          matchedProfileId: hasMatch && row?.profile_id != null
            ? row.profile_id.toString()
            : null,
          matched: hasMatch,
          score: normalizedScore,
          thresholdUsed: protectionConfig.threshold,
          metadata: decisionMetadata,
        });
      } catch (error) {
        await deps.recordOperationalHealthEvent(adminClient, {
          service: "biopay",
          component: "matching",
          status: "warn",
          severity: "warning",
          issueCode: "biopay_match_event_insert_failed",
          message: "BioPay match telemetry could not be persisted.",
          functionName: "biopay-match",
          userId: requesterUserId,
          subjectType: "biopay_match_event",
          metadata: {
            ...decisionMetadata,
            error: error instanceof Error ? error.message : String(error),
          },
        });
      }

      await deps.recordRateEvent(adminClient, {
        scope: "user",
        actorKey: userActorKey,
        requesterUserId,
        outcome,
        metadata: {
          ...decisionMetadata,
          score: normalizedScore,
          threshold: protectionConfig.threshold,
        },
      });
      if (ipActorKey != null) {
        await deps.recordRateEvent(adminClient, {
          scope: "ip",
          actorKey: ipActorKey,
          requesterUserId,
          outcome,
          metadata: {
            ...decisionMetadata,
            score: normalizedScore,
            threshold: protectionConfig.threshold,
          },
        });
      }

      if (!hasMatch) {
        const recentMisses = await deps.countRecentRateEvents(adminClient, {
          scope: "user",
          actorKey: userActorKey,
          windowStartIso: missWindowStartIso,
          outcomes: ["miss"],
        });

        if (recentMisses >= protectionConfig.maxMissesPerWindow) {
          const lockoutUntil = isoAfter(
            now.toISOString(),
            protectionConfig.lockoutSeconds,
          );
          await deps.recordRateEvent(adminClient, {
            scope: "user",
            actorKey: userActorKey,
            requesterUserId,
            outcome: "lockout_started",
            metadata: {
              ...decisionMetadata,
              miss_count: recentMisses,
              lockout_until: lockoutUntil,
            },
          });
          await deps.recordOperationalHealthEvent(adminClient, {
            service: "biopay",
            component: "matching",
            status: "warn",
            severity: "warning",
            issueCode: "biopay_match_lockout_started",
            message:
              "BioPay match request triggered a temporary lockout after repeated misses.",
            functionName: "biopay-match",
            userId: requesterUserId,
            subjectType: "biopay_match_request",
            metadata: {
              ...decisionMetadata,
              miss_count: recentMisses,
              lockout_until: lockoutUntil,
            },
          });
          return errorResponse(
            "Too many failed BioPay match attempts. Please wait before trying again.",
            423,
            {
              retryAfterSeconds: protectionConfig.lockoutSeconds,
              lockoutUntil,
            },
          );
        }

        return jsonResponse({
          success: true,
          data: {
            match: false,
            score: normalizedScore,
          },
        });
      }

      return jsonResponse({
        success: true,
        data: {
          match: true,
          ...row,
        },
      });
    } catch (error) {
      if (error instanceof SyntaxError) {
        return errorResponse("Invalid JSON body", 400);
      }
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status);
      }
      if (error instanceof BiopayValidationError) {
        return errorResponse(error.message, 400);
      }

      await deps.recordEdgeFunctionFailure(adminClient, {
        functionName: "biopay-match",
        error,
        issueCode: "biopay_match_failed",
        userId: requesterUserId,
      });
      return errorResponse(
        error instanceof Error ? error.message : "BioPay match failed.",
        500,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createBiopayMatchHandler());
}
