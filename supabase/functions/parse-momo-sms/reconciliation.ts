/**
 * reconciliation.ts — Orchestrator for MoMo SMS auto-reconciliation.
 *
 * Delegates to focused reconciler modules:
 * - group_reconciler.ts: group contribution + payee route matching
 * - subscription_reconciler.ts: driver subscription matching
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
import { findDriverSubscriptionCandidate } from "./subscription_reconciler.ts";
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

  // 1) Try payee-route-based group match first.
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

  // 3) Try driver subscription candidate.
  const {
    candidate: subscriptionCandidate,
    score: subscriptionScore,
    ambiguous: subscriptionAmbiguous,
  } = await findDriverSubscriptionCandidate(adminClient, rawSms, parsed);

  if (subscriptionAmbiguous) {
    return buildManualReviewResult(
      "Parsed SMS matched multiple driver subscription candidates and needs review.",
      {
        reason: "ambiguous_driver_subscription_match",
        candidate_score: subscriptionScore,
      },
    );
  }

  if (subscriptionCandidate) {
    const startedAt = subscriptionCandidate.started_at ?? timestamp;
    const expiresAt = subscriptionCandidate.expires_at ??
      new Date(Date.parse(startedAt) + 30 * 24 * 60 * 60 * 1000).toISOString();

    const updateResult = await adminClient
      .from("driver_subscriptions")
      .update({
        status: "active",
        started_at: startedAt,
        expires_at: expiresAt,
        updated_at: timestamp,
      })
      .eq("id", subscriptionCandidate.id);

    if (updateResult.error) {
      throw updateResult.error;
    }

    return {
      matchType: "driver_subscription",
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: "driver_subscriptions",
      targetRecordId: subscriptionCandidate.id,
      matchedReference: subscriptionCandidate.momo_reference ??
        sourceReference(rawSms, parsed),
      notes: "Parsed SMS matched a driver subscription payment.",
      metadata: {
        auto_match: true,
        candidate_score: subscriptionScore,
        driver_id: subscriptionCandidate.driver_id,
        provider: normalizeProviderId(rawSms.provider),
      },
    };
  }

  // 4) Try Rayon reference candidate.
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

  // 5) Fall back to partner route match.
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

  return buildManualReviewResult(
    "No group, subscription, or partner payment record matched the parsed SMS.",
    {
      reason: "no_matching_payment_record",
      provider: normalizeProviderId(rawSms.provider),
    },
  );
}
