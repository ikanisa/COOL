/**
 * reconciliation.ts — Orchestrator for MoMo SMS auto-reconciliation.
 *
 * Delegates to focused reconciler modules:
 * - group_reconciler.ts: group contribution + payee route matching
 * - reconciliation_utils.ts: shared types, utilities, and scoring
 *
 * Re-exports public API consumed by index.ts.
 */

import { createAdminClient } from "../_shared/supabase.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import {
  findGroupContributionCandidate,
  reconcileByPayeeRoute,
} from "./group_reconciler.ts";
import {
  asString,
  type AutoReconciliationResult,
  buildManualReviewResult,
  normalizeProviderId,
  sourceReference,
} from "./reconciliation_utils.ts";

// Re-export public API for index.ts
export { buildManualReviewResult } from "./reconciliation_utils.ts";
export { ledgerEntryType } from "./reconciliation_utils.ts";
export type { AutoReconciliationResult } from "./reconciliation_utils.ts";

export async function reconcileParsedSms(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  parsedSmsId: string,
  timestamp: string,
): Promise<AutoReconciliationResult> {
  if (parsed.amount == null || parsed.amount <= 0) {
    return buildManualReviewResult(
      "Parsed SMS does not contain a usable payment amount.",
      { reason: "missing_amount" },
    );
  }

  // 0) Look up receiver account
  const receiverResult = await adminClient
    .from("payment_receiver_accounts")
    .select("id, purpose, owner_user_id, partner_id, is_active")
    .eq("payee_number_or_code", parsed.payee_number_or_code ?? "")
    .maybeSingle();

  const receiverPurpose = asString(receiverResult.data?.purpose);
  const receiverOwnerUserId = asString(receiverResult.data?.owner_user_id);
  const receiverIsActive = receiverResult.data?.is_active != false;
  const canFallbackToWallet =
    receiverPurpose == "personal_wallet" &&
    receiverIsActive &&
    (receiverOwnerUserId == null || receiverOwnerUserId == rawSms.user_id);

  // 0.5) Try matching generic pending payment_intents first
  const intentResult = await adminClient
    .from("payment_intents")
    .select("id, target_table, target_record_id, intent_type")
    .eq("creator_id", rawSms.user_id)
    .eq("status", "pending")
    .eq("expected_amount", parsed.amount);

  const pendingIntents = intentResult.data ?? [];
  if (pendingIntents.length === 1) {
    const intent = pendingIntents[0];
    
    // Update intent to completed
    await adminClient
      .from("payment_intents")
      .update({
        status: "completed",
        updated_at: timestamp,
      })
      .eq("id", intent.id);

    return {
      matchType: `intent_${intent.intent_type}`,
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: intent.target_table ?? "payment_intents",
      targetRecordId: intent.target_record_id ?? intent.id,
      matchedReference: parsed.momo_tx_id ?? sourceReference(rawSms, parsed),
      notes: "Parsed SMS was explicitly matched to a pending intent.",
      metadata: {
        auto_match: true,
        intent_id: intent.id,
        provider: normalizeProviderId(rawSms.provider),
      },
    };
  } else if (pendingIntents.length > 1) {
    return buildManualReviewResult(
      "Parsed SMS matched multiple pending intents.",
      { reason: "ambiguous_intents", count: pendingIntents.length }
    );
  }

  // 1) Try payee-route-based group match.
  const groupRouteMatch = await reconcileByPayeeRoute(
    adminClient,
    rawSms,
    parsed,
    timestamp,
  );
  if (groupRouteMatch?.targetTable === "group_contributions") {
    return groupRouteMatch;
  }

  // 2) Try direct group contribution candidate.
  const {
    candidate: contributionCandidate,
    score: contributionScore,
    ambiguous: contributionAmbiguous,
  } = await findGroupContributionCandidate(adminClient, rawSms, parsed);

  if (contributionAmbiguous) {
    return buildManualReviewResult(
      "Parsed SMS matched multiple group contribution candidates and needs review.",
      {
        reason: "ambiguous_group_contribution_match",
        candidate_score: contributionScore,
      },
    );
  }

  if (contributionCandidate) {
    const matchedReference = contributionCandidate.momo_reference ??
      sourceReference(rawSms, parsed);

    const updateResult = await adminClient
      .from("group_contributions")
      .update({
        momo_reference: matchedReference,
      })
      .eq("id", contributionCandidate.id);

    if (updateResult.error) {
      throw updateResult.error;
    }

    await adminClient.rpc("confirm_contribution", {
      p_contribution_id: contributionCandidate.id,
    });

    return {
      matchType: "group_contribution",
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: "group_contributions",
      targetRecordId: contributionCandidate.id,
      matchedReference: matchedReference,
      notes: "Parsed SMS matched a group contribution payment.",
      metadata: {
        auto_match: true,
        candidate_score: contributionScore,
        group_id: contributionCandidate.group_id,
        provider: normalizeProviderId(rawSms.provider),
      },
    };
  }

  // 3) Fall back to partner route match.
  if (groupRouteMatch) {
    return groupRouteMatch;
  }

  // 4) Safe fallback to wallet only for explicit personal-wallet receivers.
  if (canFallbackToWallet) {
    return {
      matchType: "personal_wallet_fallback",
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: "users",
      targetRecordId: rawSms.user_id,
      matchedReference: sourceReference(rawSms, parsed),
      notes: "Parsed SMS was unmatched to any intent, safe fallback to personal wallet.",
      metadata: {
        auto_match: true,
        provider: normalizeProviderId(rawSms.provider),
      },
    };
  }

  return buildManualReviewResult(
    "No payment target matched this parsed SMS.",
    {
      reason: "no_matching_payment_record",
      receiver_purpose: receiverPurpose,
      receiver_owner_user_id: receiverOwnerUserId,
      receiver_active: receiverIsActive,
      provider: normalizeProviderId(rawSms.provider),
    },
  );
}
