/**
 * telemetry.ts — Operational telemetry for the parse-momo-sms pipeline.
 *
 * Consolidates all `recordOperationalHealthEvent`, `recordEdgeFunctionFailure`,
 * and `sendParsedPaymentNotification` calls into a focused module.
 */

import type { createAdminClient } from "../_shared/supabase.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import type { ParsedSms, RawSmsRecord } from "./ai_parser.ts";
import type { AutoReconciliationResult } from "./reconciliation_utils.ts";
import { sendParsedPaymentNotification } from "./parse_helpers.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

const FUNCTION_NAME = "parse-momo-sms";
const SERVICE_NAME = "momo_parsing";

// ── Success telemetry ──────────────────────────────────────────

export type ParseSuccessContext = {
  rawSms: RawSmsRecord;
  rawSmsId: string;
  parsedSmsId: string;
  parsed: ParsedSms;
  provider: string;
  model: string;
  reconciliation: AutoReconciliationResult;
};

/** Record a successful parse + reconciliation as a health event and send notification. */
export async function recordParseSuccess(
  adminClient: AdminClient,
  ctx: ParseSuccessContext,
): Promise<void> {
  await recordOperationalHealthEvent(adminClient, {
    service: SERVICE_NAME,
    component: FUNCTION_NAME,
    status: ctx.reconciliation.matchStatus === "matched" ? "ok" : "warn",
    severity: ctx.reconciliation.matchStatus === "matched"
      ? "info"
      : "warning",
    issueCode: ctx.reconciliation.matchStatus === "matched"
      ? null
      : "payment_requires_review",
    message: ctx.reconciliation.matchStatus === "matched"
      ? "MoMo SMS parsed and reconciled successfully."
      : "MoMo SMS parsed, but reconciliation requires manual review.",
    functionName: FUNCTION_NAME,
    userId: ctx.rawSms.user_id,
    subjectType: "momo_sms_raw",
    subjectId: ctx.rawSmsId,
    metadata: {
      parsed_sms_id: ctx.parsedSmsId,
      parser_provider: ctx.provider,
      parser_model: ctx.model,
      parse_status: ctx.parsed.parse_status,
      match_status: ctx.reconciliation.matchStatus,
      match_type: ctx.reconciliation.matchType,
      matched_reference: ctx.reconciliation.matchedReference,
    },
  });

  await sendParsedPaymentNotification({
    parsed: ctx.parsed,
    rawSms: ctx.rawSms,
    rawSmsId: ctx.rawSmsId,
  });
}

// ── Failure telemetry ──────────────────────────────────────────

export type ParseFailureContext = {
  rawSms: RawSmsRecord;
  rawSmsId: string;
  selectedAttemptId: string | null;
  error: unknown;
};

/** Record a parse failure as a health event and an edge function failure. */
export async function recordParseFailure(
  adminClient: AdminClient,
  ctx: ParseFailureContext,
): Promise<void> {
  await recordOperationalHealthEvent(adminClient, {
    service: SERVICE_NAME,
    component: FUNCTION_NAME,
    status: "error",
    severity: "critical",
    issueCode: "momo_parse_failed",
    message: ctx.error instanceof Error
      ? ctx.error.message
      : "Failed to parse MoMo SMS.",
    functionName: FUNCTION_NAME,
    userId: ctx.rawSms.user_id,
    subjectType: "momo_sms_raw",
    subjectId: ctx.rawSmsId,
    metadata: {
      selected_attempt_id: ctx.selectedAttemptId,
    },
  });

  await recordEdgeFunctionFailure(adminClient, {
    functionName: FUNCTION_NAME,
    error: ctx.error,
    userId: ctx.rawSms.user_id,
    subjectType: "momo_sms_raw",
    subjectId: ctx.rawSmsId,
    metadata: {
      selected_attempt_id: ctx.selectedAttemptId,
    },
  });
}
