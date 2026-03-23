/**
 * subscription_reconciler.ts — Driver subscription reconciliation.
 *
 * Scores and matches parsed MoMo SMS against pending driver subscriptions.
 */

import { createAdminClient } from "../_shared/supabase.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import {
  asNullableInt,
  asString,
  buildDirectCandidateScore,
  chooseBestCandidate,
  type DriverSubscriptionCandidateRecord,
  looksLikeSubscriptionReference,
} from "./reconciliation_utils.ts";

export async function findDriverSubscriptionCandidate(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
): Promise<{
  candidate: DriverSubscriptionCandidateRecord | null;
  score: number | null;
  ambiguous: boolean;
}> {
  if (parsed.amount == null || parsed.amount <= 0) {
    return { candidate: null, score: null, ambiguous: false };
  }

  const result = await adminClient
    .from("driver_subscriptions")
    .select(
      "id, driver_id, status, started_at, expires_at, momo_reference, created_at, amount, amount_rwf",
    )
    .eq("driver_id", rawSms.user_id)
    .in("status", ["pending", "active"])
    .order("created_at", { ascending: false })
    .limit(20);

  if (result.error) {
    throw result.error;
  }

  const scored: Array<{
    candidate: DriverSubscriptionCandidateRecord;
    score: number;
    key: string;
  }> = [];

  for (const value of Array.isArray(result.data) ? result.data : []) {
    const row = value as Record<string, unknown>;
    const amount = asNullableInt(row.amount_rwf) ?? asNullableInt(row.amount);
    if (amount !== parsed.amount) {
      continue;
    }

    const candidate: DriverSubscriptionCandidateRecord = {
      id: asString(row.id) ?? "",
      driver_id: asString(row.driver_id) ?? rawSms.user_id,
      status: asString(row.status),
      started_at: asString(row.started_at),
      expires_at: asString(row.expires_at),
      momo_reference: asString(row.momo_reference),
      created_at: asString(row.created_at),
    };

    let score = buildDirectCandidateScore(
      candidate.status,
      candidate.created_at,
      null,
      null,
      parsed,
      rawSms,
    );
    if (
      candidate.momo_reference &&
      looksLikeSubscriptionReference(candidate.momo_reference)
    ) {
      score += 1;
    }

    scored.push({
      candidate,
      score,
      key: candidate.id,
    });
  }

  return chooseBestCandidate(scored);
}
