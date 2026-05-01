/**
 * parse_orchestrator.ts — Core business logic for the MoMo SMS parse pipeline.
 *
 * Orchestrates the full parse → reconcile → persist → telemetry flow.
 * Consumed by the thin HTTP handler in index.ts.
 */

import type { createAdminClient } from "../_shared/supabase.ts";
import {
  type AiProvider,
  buildPrompt,
  callGemini,
  callOpenAi,
  getAiProvider,
  getModel,
  normalizeParsedSms,
  type ParsedSms,
  type ParseProvider,
  type RawSmsRecord,
  tryHeuristicParse,
} from "./ai_parser.ts";
import {
  buildManualReviewResult,
  reconcileParsedSms,
} from "./reconciliation.ts";
import type { AutoReconciliationResult } from "./reconciliation_utils.ts";
import {
  upsertLedgerEntry,
  upsertParsedSms,
  upsertReconciliation,
} from "./ledger_writer.ts";
import {
  markAttemptFailed,
  markAttemptSuccess,
  markFailed,
  markParsed,
  markProcessing,
} from "./status_manager.ts";
import {
  recordParseFailure,
  recordParseSuccess,
} from "./telemetry.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

const PROMPT_VERSION = "v1";
const HEURISTIC_PROMPT_VERSION = "heuristic-v1";

// ── Public API ─────────────────────────────────────────────────

export type ParseSmsInput = {
  rawSmsId: string;
  rawSms: RawSmsRecord;
  preferredProvider?: "openai" | "gemini";
};

export type ParseSmsResult = {
  rawSmsId: string;
  parsedSmsId: string;
  provider: ParseProvider;
  model: string;
  parseStatus: string;
  confidence: number;
  reconciliation: {
    matchType: string;
    matchStatus: string;
    targetTable: string | null;
    targetRecordId: string | null;
    matchedReference: string | null;
    txCategory: string;
  };
};

/**
 * Full parse pipeline: AI parse → persist → reconcile → ledger → telemetry.
 * Throws on unrecoverable errors (callers should catch and return HTTP 500).
 */
export async function parseSms(
  adminClient: AdminClient,
  input: ParseSmsInput,
): Promise<ParseSmsResult> {
  const { rawSmsId, rawSms } = input;
  let selectedAttemptId: string | null = null;

  await markProcessing(adminClient, rawSmsId);

  try {
    // ── Step 1: Parse (heuristic → AI primary → AI fallback) ──
    const selectedAttempt = await resolveParseAttempt(
      adminClient,
      rawSmsId,
      rawSms,
      input.preferredProvider,
    );

    selectedAttemptId = selectedAttempt.attemptId;
    const { aiResult, parsed, provider } = selectedAttempt;
    const timestamp = new Date().toISOString();

    // ── Step 2: Persist parsed SMS ────────────────────────────
    const parsedSmsId = await upsertParsedSms(adminClient, {
      rawSms,
      parsed,
      provider,
      model: aiResult.model,
      timestamp,
    });

    // ── Step 3: Reconcile ─────────────────────────────────────
    const autoReconciliation = await runReconciliation(
      adminClient,
      rawSms,
      parsed,
      parsedSmsId,
      timestamp,
    );

    // ── Step 4: Write ledger + reconciliation records ─────────
    const sharedParams = {
      parsedSmsId,
      rawSms,
      parsed,
      provider,
      model: aiResult.model,
      reconciliation: autoReconciliation,
      timestamp,
    };

    await upsertLedgerEntry(adminClient, sharedParams);
    await upsertReconciliation(adminClient, sharedParams);

    // ── Step 5: Update attempt + raw SMS status ───────────────
    await markAttemptSuccess(adminClient, selectedAttemptId, {
      requestPayload: aiResult.requestPayload,
      responseBody: aiResult.responseBody,
    });
    await markParsed(adminClient, rawSmsId, timestamp);

    // ── Step 6: Telemetry ─────────────────────────────────────
    await recordParseSuccess(adminClient, {
      rawSms,
      rawSmsId,
      parsedSmsId,
      parsed,
      provider: String(provider),
      model: aiResult.model,
      reconciliation: autoReconciliation,
    });

    return {
      rawSmsId,
      parsedSmsId,
      provider,
      model: aiResult.model,
      parseStatus: parsed.parse_status,
      confidence: parsed.confidence,
      reconciliation: {
        matchType: autoReconciliation.matchType,
        matchStatus: autoReconciliation.matchStatus,
        targetTable: autoReconciliation.targetTable,
        targetRecordId: autoReconciliation.targetRecordId,
        matchedReference: autoReconciliation.matchedReference,
        txCategory: parsed.tx_category,
      },
    };
  } catch (error) {
    // ── Failure path: mark attempt + raw SMS as failed ─────────
    await markAttemptFailed(adminClient, selectedAttemptId, error);
    await markFailed(adminClient, rawSmsId);
    await recordParseFailure(adminClient, {
      rawSms,
      rawSmsId,
      selectedAttemptId,
      error,
    });

    throw error;
  }
}

// ── Internal helpers ───────────────────────────────────────────

type ParseAttemptResult = {
  attemptId: string;
  provider: ParseProvider;
  aiResult: {
    model: string;
    requestPayload: unknown;
    responseBody: unknown;
    text?: string;
  };
  parsed: ParsedSms;
};

/** Resolve the best parse attempt: heuristic first, then AI with fallback. */
async function resolveParseAttempt(
  adminClient: AdminClient,
  rawSmsId: string,
  rawSms: RawSmsRecord,
  preferredProvider?: "openai" | "gemini",
): Promise<ParseAttemptResult> {
  // 1. Try heuristic first
  const heuristicAttempt = await runHeuristicAttempt(
    adminClient,
    rawSmsId,
    rawSms,
  );
  if (heuristicAttempt) {
    return heuristicAttempt;
  }

  // 2. AI attempt with optional fallback
  const prompt = buildPrompt(rawSms);
  const primaryProvider = getAiProvider(preferredProvider);
  const openAiFallbackAvailable = primaryProvider === "gemini" &&
    (Deno.env.get("OPENAI_API_KEY") ?? "").trim().length > 0;

  try {
    return await runProviderAttempt(
      adminClient,
      rawSmsId,
      rawSms,
      primaryProvider,
      prompt,
    );
  } catch (primaryError) {
    if (!openAiFallbackAvailable) {
      throw primaryError;
    }

    console.error(
      "parse-momo-sms gemini attempt failed, retrying with OpenAI",
      primaryError,
    );
    return await runProviderAttempt(
      adminClient,
      rawSmsId,
      rawSms,
      "openai",
      prompt,
    );
  }
}

/** Run a single AI provider parse attempt. */
async function runProviderAttempt(
  adminClient: AdminClient,
  rawSmsId: string,
  rawSms: RawSmsRecord,
  provider: AiProvider,
  prompt: string,
): Promise<ParseAttemptResult> {
  const model = getModel(provider);

  const attemptsResult = await adminClient
    .from("momo_parse_attempts")
    .select("attempt_number")
    .eq("raw_sms_id", rawSmsId)
    .eq("provider", provider);

  if (attemptsResult.error) {
    throw attemptsResult.error;
  }

  const attemptNumber = (attemptsResult.data?.length ?? 0) + 1;
  const attemptInsert = await adminClient
    .from("momo_parse_attempts")
    .insert({
      raw_sms_id: rawSmsId,
      user_id: rawSms.user_id,
      provider,
      model,
      attempt_number: attemptNumber,
      status: "pending",
      prompt_version: PROMPT_VERSION,
    })
    .select("id")
    .single();

  if (attemptInsert.error) {
    throw attemptInsert.error;
  }

  const attemptId = attemptInsert.data.id as string;

  try {
    const aiResult = provider === "gemini"
      ? await callGemini(prompt)
      : await callOpenAi(prompt);

    return {
      attemptId,
      provider,
      aiResult,
      parsed: normalizeParsedSms(
        JSON.parse(aiResult.text) as Record<string, unknown>,
      ),
    };
  } catch (error) {
    await markAttemptFailed(adminClient, attemptId, error);
    throw error;
  }
}

/** Try the heuristic (regex) parser. Returns null if no match. */
async function runHeuristicAttempt(
  adminClient: AdminClient,
  rawSmsId: string,
  rawSms: RawSmsRecord,
): Promise<ParseAttemptResult | null> {
  const heuristic = tryHeuristicParse(rawSms);
  if (!heuristic) {
    return null;
  }

  const attemptsResult = await adminClient
    .from("momo_parse_attempts")
    .select("attempt_number")
    .eq("raw_sms_id", rawSmsId)
    .eq("provider", "heuristic");

  if (attemptsResult.error) {
    throw attemptsResult.error;
  }

  const attemptNumber = (attemptsResult.data?.length ?? 0) + 1;
  const attemptInsert = await adminClient
    .from("momo_parse_attempts")
    .insert({
      raw_sms_id: rawSmsId,
      user_id: rawSms.user_id,
      provider: "heuristic",
      model: heuristic.model,
      attempt_number: attemptNumber,
      status: "success",
      prompt_version: HEURISTIC_PROMPT_VERSION,
      request_payload: heuristic.requestPayload,
      response_payload: heuristic.responsePayload,
    })
    .select("id")
    .single();

  if (attemptInsert.error) {
    throw attemptInsert.error;
  }

  return {
    attemptId: attemptInsert.data.id as string,
    provider: "heuristic" as ParseProvider,
    aiResult: {
      model: heuristic.model,
      requestPayload: heuristic.requestPayload,
      responseBody: heuristic.responsePayload,
    },
    parsed: heuristic.parsed,
  };
}

/** Run reconciliation with graceful degradation to manual review. */
async function runReconciliation(
  adminClient: AdminClient,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  parsedSmsId: string,
  timestamp: string,
): Promise<AutoReconciliationResult> {
  if (parsed.parse_status !== "parsed") {
    return buildManualReviewResult(
      "Parsed SMS needs manual review before reconciliation.",
      { reason: "parsed_status_requires_review" },
    );
  }

  try {
    return await reconcileParsedSms(
      adminClient,
      rawSms,
      parsed,
      parsedSmsId,
      timestamp,
    );
  } catch (reconciliationError) {
    console.error(
      "parse-momo-sms reconciliation failed",
      reconciliationError,
    );
    return buildManualReviewResult(
      "AI parsing succeeded, but reconciliation failed and needs manual review.",
      {
        reason: "reconciliation_error",
        error: reconciliationError instanceof Error
          ? reconciliationError.message
          : "unknown_reconciliation_error",
      },
    );
  }
}
