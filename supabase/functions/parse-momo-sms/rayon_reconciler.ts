/**
 * rayon_reconciler.ts — Rayon Sports payment reconciliation.
 *
 * Matches parsed MoMo SMS against Rayon tickets, shop orders,
 * and initiative contributions using Rayon reference patterns.
 */

import { looksLikeRayonReference } from "../_shared/rayon_payments.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import {
  asNullableInt,
  asString,
  buildDirectCandidateScore,
  chooseBestCandidate,
  type RayonReferenceCandidateRecord,
} from "./reconciliation_utils.ts";

export async function findRayonReferenceCandidate(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
): Promise<{
  candidate: RayonReferenceCandidateRecord | null;
  score: number | null;
  ambiguous: boolean;
}> {
  if (parsed.amount == null || parsed.amount <= 0) {
    return { candidate: null, score: null, ambiguous: false };
  }

  const scored: Array<{
    candidate: RayonReferenceCandidateRecord;
    score: number;
    key: string;
  }> = [];

  // ── Tickets ──────────────────────────────────────────────────
  const ticketsResult = await adminClient
    .from("rs_tickets")
    .select("momo_reference, amount_paid, status, purchased_at")
    .eq("user_id", rawSms.user_id)
    .order("purchased_at", { ascending: false });

  if (ticketsResult.error) {
    throw ticketsResult.error;
  }

  const ticketGroups = new Map<string, {
    totalAmount: number;
    createdAt: string | null;
    status: string | null;
  }>();

  for (
    const value of Array.isArray(ticketsResult.data) ? ticketsResult.data : []
  ) {
    const row = value as Record<string, unknown>;
    const reference = asString(row.momo_reference);
    if (!reference || !looksLikeRayonReference(reference)) {
      continue;
    }

    const group = ticketGroups.get(reference) ?? {
      totalAmount: 0,
      createdAt: null,
      status: null,
    };
    group.totalAmount += asNullableInt(row.amount_paid) ?? 0;
    group.createdAt = group.createdAt ?? asString(row.purchased_at);
    if (asString(row.status)?.trim().toLowerCase() === "pending") {
      group.status = "pending";
    } else if (group.status == null) {
      group.status = asString(row.status);
    }
    ticketGroups.set(reference, group);
  }

  for (const [reference, group] of ticketGroups.entries()) {
    if (group.totalAmount !== parsed.amount) {
      continue;
    }

    const candidate: RayonReferenceCandidateRecord = {
      reference,
      matchType: "rayon_ticket",
      created_at: group.createdAt,
      status: group.status,
    };
    scored.push({
      candidate,
      score: buildDirectCandidateScore(
        candidate.status,
        candidate.created_at,
        null,
        null,
        parsed,
        rawSms,
      ),
      key: `${candidate.matchType}:${candidate.reference}`,
    });
  }

  // ── Shop orders ──────────────────────────────────────────────
  const shopResult = await adminClient
    .from("rs_shop_orders")
    .select("momo_reference, total, status, created_at")
    .eq("user_id", rawSms.user_id)
    .order("created_at", { ascending: false });

  if (shopResult.error) {
    throw shopResult.error;
  }

  for (const value of Array.isArray(shopResult.data) ? shopResult.data : []) {
    const row = value as Record<string, unknown>;
    const reference = asString(row.momo_reference);
    if (!reference || !looksLikeRayonReference(reference)) {
      continue;
    }
    if ((asNullableInt(row.total) ?? 0) !== parsed.amount) {
      continue;
    }

    const candidate: RayonReferenceCandidateRecord = {
      reference,
      matchType: "rayon_shop_order",
      created_at: asString(row.created_at),
      status: asString(row.status),
    };
    scored.push({
      candidate,
      score: buildDirectCandidateScore(
        candidate.status,
        candidate.created_at,
        null,
        null,
        parsed,
        rawSms,
      ),
      key: `${candidate.matchType}:${candidate.reference}`,
    });
  }

  // ── Initiative contributions ─────────────────────────────────
  const initiativeResult = await adminClient
    .from("rs_initiative_contributions")
    .select("momo_reference, amount, status, created_at")
    .eq("user_id", rawSms.user_id)
    .order("created_at", { ascending: false });

  if (initiativeResult.error) {
    throw initiativeResult.error;
  }

  for (
    const value of Array.isArray(initiativeResult.data)
      ? initiativeResult.data
      : []
  ) {
    const row = value as Record<string, unknown>;
    const reference = asString(row.momo_reference);
    if (!reference || !looksLikeRayonReference(reference)) {
      continue;
    }
    if ((asNullableInt(row.amount) ?? 0) !== parsed.amount) {
      continue;
    }

    const candidate: RayonReferenceCandidateRecord = {
      reference,
      matchType: "rayon_initiative_support",
      created_at: asString(row.created_at),
      status: asString(row.status),
    };
    scored.push({
      candidate,
      score: buildDirectCandidateScore(
        candidate.status,
        candidate.created_at,
        null,
        null,
        parsed,
        rawSms,
      ),
      key: `${candidate.matchType}:${candidate.reference}`,
    });
  }

  return chooseBestCandidate(scored);
}
