/**
 * reconciliation.ts — Orchestrator for MoMo SMS auto-reconciliation.
 *
 * Delegates to focused reconciler modules:
 * - group_reconciler.ts: group contribution + payee route matching
 * - rayon_reconciler.ts: Rayon Sports reference matching
 * - reconciliation_utils.ts: shared types, utilities, and scoring
 *
 * Re-exports public API consumed by index.ts.
 */

import {
  confirmRayonReferenceMatch as confirmSharedRayonReferenceMatch,
} from "../_shared/rayon_payments.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import {
  findGroupContributionCandidate,
  reconcileByPayeeRoute,
} from "./group_reconciler.ts";
import { findRayonReferenceCandidate } from "./rayon_reconciler.ts";
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
    .select("receiver_type, owner_id")
    .eq("code_or_number", parsed.payee_number_or_code ?? "")
    .maybeSingle();

  const receiverType = receiverResult.data?.receiver_type;
  const isDedicated = receiverType === "bank_custody" || receiverType === "rayon_shop" || receiverType === "agent_till";

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

  // 3) Try Rayon reference candidate.
  const {
    candidate: rayonCandidate,
    score: rayonScore,
    ambiguous: rayonAmbiguous,
  } = await findRayonReferenceCandidate(adminClient, rawSms, parsed);

  if (rayonAmbiguous) {
    return buildManualReviewResult(
      "Parsed SMS matched multiple Rayon Sports payment candidates and needs review.",
      {
        reason: "ambiguous_rayon_match",
        candidate_score: rayonScore,
      },
    );
  }

  if (rayonCandidate) {
    return await confirmSharedRayonReferenceMatch(adminClient, {
      reference: rayonCandidate.reference,
      user_id: rawSms.user_id,
    }, {
      source: "parse-momo-sms",
      timestamp,
      provider: normalizeProviderId(rawSms.provider),
      amount: parsed.amount,
      transactionId: parsed.momo_tx_id ?? rawSms.detected_tx_id,
      payeeNumberOrCode: parsed.payee_number_or_code,
      merchantCode: parsed.merchant_code,
      candidateScore: rayonScore,
      confidence: parsed.confidence,
      rawSmsId: rawSms.id,
      parsedSmsId,
      sender: rawSms.sender,
      country: rawSms.country,
      extraPayload: {
        sms_received_at: rawSms.sms_received_at,
        tx_type: parsed.tx_type,
        tx_direction: parsed.tx_direction,
      },
    });
  }

  // 4) Fall back to partner route match.
  if (groupRouteMatch) {
    return groupRouteMatch;
  }

  const partnerRouteMatch = await reconcileByPayeeRoute(
    adminClient,
    rawSms,
    parsed,
    timestamp,
  );
  if (partnerRouteMatch) {
    return partnerRouteMatch;
  }

  // 5) Safe fallback to wallet if not dedicated receiver
  if (!isDedicated) {
    // Attempt matched identity heuristics before falling back.
    // (In future we could refine this further with payment_identities)
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
    "No intent matched this dedicated receiver code.",
    {
      reason: "unmatched_dedicated_code",
      receiverType,
      provider: normalizeProviderId(rawSms.provider),
    },
  );
}
