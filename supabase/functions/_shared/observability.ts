import type { createAdminClient } from "./supabase.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

export type OperationalEventStatus = "ok" | "warn" | "error";
export type OperationalEventSeverity = "info" | "warning" | "critical";

export type OperationalHealthEventInput = {
  service: string;
  component?: string | null;
  status?: OperationalEventStatus;
  severity?: OperationalEventSeverity;
  issueCode?: string | null;
  message: string;
  functionName?: string | null;
  userId?: string | null;
  subjectType?: string | null;
  subjectId?: string | null;
  metadata?: Record<string, unknown>;
  occurredAt?: string | null;
};

function normalizeNullableString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function defaultSeverity(
  status: OperationalEventStatus | undefined,
): OperationalEventSeverity {
  switch (status) {
    case "warn":
      return "warning";
    case "error":
      return "critical";
    default:
      return "info";
  }
}

export async function recordOperationalHealthEvent(
  adminClient: AdminClient,
  event: OperationalHealthEventInput,
) {
  try {
    const { error } = await adminClient
      .from("operational_health_events")
      .insert({
        service: event.service,
        component: normalizeNullableString(event.component) ?? "general",
        status: event.status ?? "ok",
        severity: event.severity ?? defaultSeverity(event.status),
        issue_code: normalizeNullableString(event.issueCode),
        message: event.message,
        function_name: normalizeNullableString(event.functionName),
        user_id: normalizeNullableString(event.userId),
        subject_type: normalizeNullableString(event.subjectType),
        subject_id: normalizeNullableString(event.subjectId),
        metadata: event.metadata ?? {},
        occurred_at: normalizeNullableString(event.occurredAt) ??
          new Date().toISOString(),
      });

    if (error) {
      console.error("operational health event insert failed", error);
    }
  } catch (error) {
    console.error("operational health event insert crashed", error);
  }
}

export async function recordEdgeFunctionFailure(
  adminClient: AdminClient,
  options: {
    functionName: string;
    error: unknown;
    userId?: string | null;
    issueCode?: string | null;
    subjectType?: string | null;
    subjectId?: string | null;
    metadata?: Record<string, unknown>;
  },
) {
  const message = options.error instanceof Error
    ? options.error.message
    : "Unexpected Edge Function failure";

  await recordOperationalHealthEvent(adminClient, {
    service: "edge_function",
    component: options.functionName,
    status: "error",
    severity: "critical",
    issueCode: options.issueCode ?? "function_invocation_failed",
    message,
    functionName: options.functionName,
    userId: options.userId,
    subjectType: options.subjectType,
    subjectId: options.subjectId,
    metadata: {
      ...(options.metadata ?? {}),
      error_name: options.error instanceof Error
        ? options.error.name
        : typeof options.error,
    },
  });
}
