/**
 * status_manager.ts — Raw SMS and parse attempt lifecycle management.
 *
 * Single-responsibility module for all status transitions on:
 * - `momo_sms_raw.parse_status`
 * - `momo_parse_attempts.status`
 */

import type { createAdminClient } from "../_shared/supabase.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

// ── Raw SMS status ─────────────────────────────────────────────

/** Mark a raw SMS record as currently being processed. */
export async function markProcessing(
  adminClient: AdminClient,
  rawSmsId: string,
): Promise<void> {
  await adminClient
    .from("momo_sms_raw")
    .update({ parse_status: "processing" })
    .eq("id", rawSmsId);
}

/** Mark a raw SMS record as successfully parsed. */
export async function markParsed(
  adminClient: AdminClient,
  rawSmsId: string,
  timestamp: string,
): Promise<void> {
  await adminClient
    .from("momo_sms_raw")
    .update({
      parse_status: "parsed",
      updated_at: timestamp,
    })
    .eq("id", rawSmsId);
}

/** Mark a raw SMS record as failed to parse. */
export async function markFailed(
  adminClient: AdminClient,
  rawSmsId: string,
): Promise<void> {
  await adminClient
    .from("momo_sms_raw")
    .update({
      parse_status: "failed",
      updated_at: new Date().toISOString(),
    })
    .eq("id", rawSmsId);
}

// ── Parse attempt status ───────────────────────────────────────

/** Mark a parse attempt as successful with its AI result payload. */
export async function markAttemptSuccess(
  adminClient: AdminClient,
  attemptId: string,
  aiResult: { requestPayload: unknown; responseBody: unknown },
): Promise<void> {
  await adminClient
    .from("momo_parse_attempts")
    .update({
      status: "success",
      request_payload: aiResult.requestPayload,
      response_payload: aiResult.responseBody,
    })
    .eq("id", attemptId);
}

/** Mark a parse attempt as failed with an error message. */
export async function markAttemptFailed(
  adminClient: AdminClient,
  attemptId: string | null,
  error: unknown,
): Promise<void> {
  if (attemptId == null) {
    return;
  }

  await adminClient
    .from("momo_parse_attempts")
    .update({
      status: "failed",
      error_message: error instanceof Error
        ? error.message
        : "AI parse failed",
    })
    .eq("id", attemptId);
}
