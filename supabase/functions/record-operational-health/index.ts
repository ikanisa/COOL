import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  type OperationalEventSeverity,
  type OperationalEventStatus,
  type OperationalHealthEventInput,
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type RecordOperationalHealthRequest = {
  service?: string;
  component?: string;
  status?: OperationalEventStatus;
  severity?: OperationalEventSeverity;
  issueCode?: string | null;
  message?: string;
  functionName?: string | null;
  userId?: string | null;
  subjectType?: string | null;
  subjectId?: string | null;
  metadata?: Record<string, unknown>;
  occurredAt?: string | null;
};

type AdminClient = ReturnType<typeof createAdminClient>;
type UserClient = ReturnType<typeof createUserClient>;

export type RecordOperationalHealthHandlerDependencies = {
  createAdminClient: () => AdminClient;
  createUserClient: (authorization: string) => UserClient;
  enforceRateLimit: (
    adminClient: AdminClient,
    userId: string,
    service: string,
  ) => Promise<void>;
  recordOperationalHealthEvent: (
    adminClient: AdminClient,
    event: OperationalHealthEventInput,
  ) => Promise<void>;
  recordEdgeFunctionFailure: (
    adminClient: AdminClient,
    options: Parameters<typeof recordEdgeFunctionFailure>[1],
  ) => Promise<void>;
};

const allowedComponents = new Map<string, Set<string>>([
  [
    "sms_ingest",
    new Set<string>([
      "android_sms_autoread",
      "android_sms_inbox_recovery",
      "momo_sms_ingestion",
    ]),
  ],
  [
    "biopay",
    new Set<string>([
      "enrollment",
      "matching",
      "payment_intent",
      "revocation",
    ]),
  ],
]);

const allowedStatuses = new Set<OperationalEventStatus>([
  "ok",
  "warn",
  "error",
]);
const allowedSeverities = new Set<OperationalEventSeverity>([
  "info",
  "warning",
  "critical",
]);
const mobileTelemetryWindowMs = 5 * 60 * 1000;
const maxMobileEventsPerWindow = 30;

const defaultDependencies: RecordOperationalHealthHandlerDependencies = {
  createAdminClient,
  createUserClient,
  enforceRateLimit,
  recordOperationalHealthEvent,
  recordEdgeFunctionFailure,
};

export function createRecordOperationalHealthHandler(
  dependencies: Partial<RecordOperationalHealthHandlerDependencies> = {},
) {
  const deps: RecordOperationalHealthHandlerDependencies = {
    ...defaultDependencies,
    ...dependencies,
  };

  return async (request: Request) => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method != "POST") {
      return methodNotAllowed("POST");
    }

    let userIdForTelemetry: string | null = null;

    try {
      const authorization = request.headers.get("authorization")?.trim() ??
        request.headers.get("Authorization")?.trim();
      if (!authorization) {
        throw new HttpError(401, "Authentication required");
      }

      const user = await requireUser(deps.createUserClient, authorization);
      userIdForTelemetry = user.id;
      const adminClient = deps.createAdminClient();
      const body = await request.json() as RecordOperationalHealthRequest;

      const service = normalizeRequired(body.service, "service");
      const component = normalizeRequired(body.component, "component");
      validateAllowedServiceComponent(service, component);

      const message = normalizeRequired(body.message, "message");
      if (message.length > 240) {
        throw new HttpError(400, "message must be 240 characters or fewer");
      }

      const status = body.status ?? "ok";
      if (!allowedStatuses.has(status)) {
        throw new HttpError(400, "Unsupported operational status", { status });
      }

      const severity = body.severity ?? undefined;
      if (severity != null && !allowedSeverities.has(severity)) {
        throw new HttpError(400, "Unsupported operational severity", {
          severity,
        });
      }

      const userId = normalizeOptional(body.userId);
      if (userId != null && userId != user.id) {
        throw new HttpError(403, "userId must match the authenticated user");
      }

      await deps.enforceRateLimit(adminClient, user.id, service);

      await deps.recordOperationalHealthEvent(adminClient, {
        service,
        component,
        status,
        severity,
        issueCode: normalizeOptional(body.issueCode),
        message,
        functionName: normalizeOptional(body.functionName),
        userId: user.id,
        subjectType: normalizeOptional(body.subjectType),
        subjectId: normalizeOptional(body.subjectId),
        metadata: sanitizeMetadata(body.metadata),
        occurredAt: normalizeOptional(body.occurredAt),
        ingestOrigin: "mobile_app",
      });

      return jsonResponse({ success: true });
    } catch (error) {
      if (error instanceof SyntaxError) {
        return errorResponse("Invalid JSON body", 400);
      }
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status, error.details);
      }
      if (error instanceof Error) {
        console.error("record-operational-health failed", error);
        await deps.recordEdgeFunctionFailure(deps.createAdminClient(), {
          functionName: "record-operational-health",
          error,
          userId: userIdForTelemetry,
        });
        return errorResponse(error.message, 500);
      }
      return errorResponse("Failed to record operational health event", 500);
    }
  };
}

if (import.meta.main) {
  Deno.serve(createRecordOperationalHealthHandler());
}

async function requireUser(
  buildUserClient:
    RecordOperationalHealthHandlerDependencies["createUserClient"],
  authorization: string,
) {
  const client = buildUserClient(authorization);
  const {
    data: { user },
    error,
  } = await client.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required");
  }

  return user;
}

function normalizeRequired(value: string | undefined, field: string) {
  const normalized = normalizeOptional(value);
  if (normalized == null) {
    throw new HttpError(400, `${field} is required`);
  }
  return normalized;
}

function normalizeOptional(value: string | null | undefined) {
  if (typeof value != "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function validateAllowedServiceComponent(service: string, component: string) {
  const allowed = allowedComponents.get(service);
  if (allowed == null || !allowed.has(component)) {
    throw new HttpError(400, "Unsupported operational service/component");
  }
}

function sanitizeMetadata(value: unknown): Record<string, unknown> {
  if (value == null) {
    return {};
  }
  if (typeof value != "object" || Array.isArray(value)) {
    throw new HttpError(400, "metadata must be an object");
  }

  const entries = Object.entries(value);
  if (entries.length > 12) {
    throw new HttpError(400, "metadata can include at most 12 keys");
  }

  finalMetadataLoop:
  for (const [key, entryValue] of entries) {
    if (key.trim().length == 0 || key.length > 64) {
      throw new HttpError(
        400,
        "metadata keys must be between 1 and 64 characters",
      );
    }
    switch (typeof entryValue) {
      case "string":
        if (entryValue.length > 240) {
          throw new HttpError(
            400,
            "metadata string values must be 240 characters or fewer",
          );
        }
        break;
      case "number":
      case "boolean":
        break;
      case "object":
        if (entryValue !== null) {
          throw new HttpError(
            400,
            "metadata values must be scalar JSON values",
          );
        }
        break;
      default:
        throw new HttpError(400, "metadata values must be scalar JSON values");
    }
    continue finalMetadataLoop;
  }

  return value as Record<string, unknown>;
}

async function enforceRateLimit(
  adminClient: AdminClient,
  userId: string,
  service: string,
) {
  const windowStart = new Date(Date.now() - mobileTelemetryWindowMs)
    .toISOString();
  const result = await adminClient
    .from("operational_health_events")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("service", service)
    .eq("ingest_origin", "mobile_app")
    .gte("occurred_at", windowStart);

  if (result.error) {
    throw result.error;
  }

  if ((result.count ?? 0) >= maxMobileEventsPerWindow) {
    throw new HttpError(429, "Operational telemetry rate limit exceeded", {
      retryAfterSeconds: Math.floor(mobileTelemetryWindowMs / 1000),
    });
  }
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
    this.name = "HttpError";
  }
}
