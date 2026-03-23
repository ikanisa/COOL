/**
 * group_reconciler.ts — Group contribution reconciliation.
 *
 * Handles payee-route matching for savings groups, group membership checks,
 * and contribution candidate scoring.
 */

import { createAdminClient } from "../_shared/supabase.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import {
  asGroupRouteRecord,
  asPartnerRouteRecord,
  asString,
  type AutoReconciliationResult,
  buildDirectCandidateScore,
  buildManualReviewResult,
  chooseBestCandidate,
  digitsMatch,
  type GroupContributionCandidateRecord,
  type GroupContributionRecord,
  type GroupRouteRecord,
  normalizeDigits,
  normalizeProviderId,
  type PartnerRouteRecord,
  payeeRouteDigits,
  sourceReference,
} from "./reconciliation_utils.ts";

// ── Route matching ─────────────────────────────────────────────
export async function findGroupRouteMatches(
  adminClient: ReturnType<typeof createAdminClient>,
  parsed: ParsedSms,
): Promise<GroupRouteRecord[]> {
  const digits = payeeRouteDigits(parsed);
  if (!digits) {
    return [];
  }

  const result = await adminClient
    .from("groups")
    .select(
      "id, name, type, receiving_momo_code, momo_number, receiving_momo_route_type",
    );

  if (result.error) {
    throw result.error;
  }

  const rows = Array.isArray(result.data) ? result.data : [];
  return rows
    .map((row) => asGroupRouteRecord(row as Record<string, unknown>))
    .filter((group) =>
      digitsMatch(normalizeDigits(group.receiving_momo_code), digits) ||
      digitsMatch(normalizeDigits(group.momo_number), digits)
    );
}

export async function findPartnerRouteMatches(
  adminClient: ReturnType<typeof createAdminClient>,
  parsed: ParsedSms,
): Promise<PartnerRouteRecord[]> {
  const digits = payeeRouteDigits(parsed);
  if (!digits) {
    return [];
  }

  const result = await adminClient
    .from("partner_payment_routes")
    .select(
      "id, partner_id, recipient_code, reconciliation_label, status, partners(name, slug)",
    )
    .eq("status", "active");

  if (result.error) {
    throw result.error;
  }

  const rows = Array.isArray(result.data) ? result.data : [];
  return rows
    .map((row) => asPartnerRouteRecord(row as Record<string, unknown>))
    .filter((route) =>
      digitsMatch(normalizeDigits(route.recipient_code), digits)
    );
}

export async function isGroupMember(
  adminClient: ReturnType<typeof createAdminClient>,
  groupId: string,
  userId: string,
): Promise<boolean> {
  const result = await adminClient
    .from("group_members")
    .select("id")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  return result.data != null;
}

// ── Existing contribution resolution ───────────────────────────
async function resolveExistingGroupContributionByPayeeRoute(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  group: GroupRouteRecord,
): Promise<GroupContributionRecord | null> {
  const ref = parsed.momo_tx_id ?? rawSms.detected_tx_id ??
    `SMS-${rawSms.id}`;

  const byReference = await adminClient
    .from("group_contributions")
    .select("id, group_id, status")
    .eq("group_id", group.id)
    .eq("user_id", rawSms.user_id)
    .eq("momo_reference", ref)
    .limit(1)
    .maybeSingle();

  if (byReference.error) {
    throw byReference.error;
  }

  if (byReference.data) {
    return {
      id: asString(byReference.data.id) ?? "",
      group_id: asString(byReference.data.group_id),
      status: asString(byReference.data.status),
    };
  }

  const amount = parsed.amount;
  if (amount == null || amount <= 0) {
    return null;
  }

  const result = await adminClient
    .from("group_contributions")
    .select("id, group_id, status")
    .eq("group_id", group.id)
    .eq("user_id", rawSms.user_id)
    .eq("amount", amount)
    .in("status", ["pending", "confirmed", "completed"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  if (!result.data) {
    return null;
  }

  return {
    id: asString(result.data.id) ?? "",
    group_id: asString(result.data.group_id),
    status: asString(result.data.status),
  };
}

// ── Ensure contribution (upsert + confirm) ─────────────────────
export async function ensureGroupContributionByPayeeRoute(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  group: GroupRouteRecord,
  timestamp: string,
): Promise<GroupContributionRecord> {
  const existing = await resolveExistingGroupContributionByPayeeRoute(
    adminClient,
    rawSms,
    parsed,
    group,
  );

  if (existing) {
    await adminClient.rpc("confirm_contribution", {
      p_contribution_id: existing.id,
    });

    return {
      id: existing.id,
      group_id: existing.group_id,
      status: "confirmed",
    };
  }

  const insertReference = parsed.momo_tx_id ?? rawSms.detected_tx_id ??
    `SMS-${rawSms.id}`;
  const insertResult = await adminClient
    .from("group_contributions")
    .insert({
      group_id: group.id,
      user_id: rawSms.user_id,
      amount: parsed.amount ?? 0,
      status: "pending",
      momo_reference: insertReference,
      created_at: parsed.tx_datetime_iso ?? rawSms.sms_received_at ?? timestamp,
    })
    .select("id, group_id, status")
    .single();

  if (insertResult.error) {
    throw insertResult.error;
  }

  const insertedId = asString(insertResult.data.id) ?? "";

  await adminClient.rpc("confirm_contribution", {
    p_contribution_id: insertedId,
  });

  return {
    id: insertedId,
    group_id: asString(insertResult.data.group_id),
    status: "confirmed",
  };
}

// ── Candidate scoring ──────────────────────────────────────────
export async function findGroupContributionCandidate(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
): Promise<{
  candidate: GroupContributionCandidateRecord | null;
  score: number | null;
  ambiguous: boolean;
}> {
  if (parsed.amount == null || parsed.amount <= 0) {
    return { candidate: null, score: null, ambiguous: false };
  }

  const result = await adminClient
    .from("group_contributions")
    .select("id, group_id, status, momo_reference, created_at")
    .eq("user_id", rawSms.user_id)
    .eq("amount", parsed.amount)
    .in("status", ["pending", "confirmed", "completed"])
    .order("created_at", { ascending: false })
    .limit(20);

  if (result.error) {
    throw result.error;
  }

  const payeeDigits = payeeRouteDigits(parsed);
  const groupRouteDigits = new Map<string, string | null>();
  const scored: Array<{
    candidate: GroupContributionCandidateRecord;
    score: number;
    key: string;
  }> = [];

  for (const value of Array.isArray(result.data) ? result.data : []) {
    const row = value as Record<string, unknown>;
    const groupId = asString(row.group_id);
    let routeDigits: string | null = null;
    if (groupId) {
      if (!groupRouteDigits.has(groupId)) {
        const groupResult = await adminClient
          .from("groups")
          .select("receiving_momo_code, momo_number")
          .eq("id", groupId)
          .maybeSingle();

        if (groupResult.error) {
          throw groupResult.error;
        }

        groupRouteDigits.set(
          groupId,
          normalizeDigits(groupResult.data?.receiving_momo_code) ??
            normalizeDigits(groupResult.data?.momo_number),
        );
      }
      routeDigits = groupRouteDigits.get(groupId) ?? null;
    }

    const candidate: GroupContributionCandidateRecord = {
      id: asString(row.id) ?? "",
      group_id: groupId,
      status: asString(row.status),
      momo_reference: asString(row.momo_reference),
      created_at: asString(row.created_at),
      route_digits: routeDigits,
    };
    scored.push({
      candidate,
      score: buildDirectCandidateScore(
        candidate.status,
        candidate.created_at,
        payeeDigits,
        candidate.route_digits,
        parsed,
        rawSms,
      ),
      key: candidate.id,
    });
  }

  return chooseBestCandidate(scored);
}

// ── Payee route reconciliation ─────────────────────────────────
export async function reconcileByPayeeRoute(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  timestamp: string,
): Promise<AutoReconciliationResult | null> {
  const digits = payeeRouteDigits(parsed);
  if (!digits) {
    return null;
  }

  const groupMatches = await findGroupRouteMatches(adminClient, parsed);
  const partnerMatches = await findPartnerRouteMatches(adminClient, parsed);

  if (groupMatches.length + partnerMatches.length == 0) {
    return null;
  }

  if (groupMatches.length + partnerMatches.length > 1) {
    return buildManualReviewResult(
      "Parsed SMS matched multiple payee routes and needs manual review.",
      {
        reason: "ambiguous_payee_route",
        payee_number_or_code: parsed.payee_number_or_code,
        merchant_code: parsed.merchant_code,
        matching_group_ids: groupMatches.map((group) => group.id),
        matching_partner_route_ids: partnerMatches.map((route) => route.id),
      },
    );
  }

  const matchedGroup = groupMatches[0];
  if (matchedGroup) {
    const member = await isGroupMember(
      adminClient,
      matchedGroup.id,
      rawSms.user_id,
    );
    const groupType = matchedGroup.type?.trim().toLowerCase() ?? "saving";

    if (!member && groupType !== "community") {
      return buildManualReviewResult(
        "Parsed SMS matched a group payee route, but the payer is not a member of that savings group.",
        {
          reason: "payer_not_group_member",
          group_id: matchedGroup.id,
          group_type: groupType,
          payee_number_or_code: parsed.payee_number_or_code,
          merchant_code: parsed.merchant_code,
        },
      );
    }

    const contribution = await ensureGroupContributionByPayeeRoute(
      adminClient,
      rawSms,
      parsed,
      matchedGroup,
      timestamp,
    );

    return {
      matchType: "payee_route_group",
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: "group_contributions",
      targetRecordId: contribution.id,
      matchedReference: sourceReference(rawSms, parsed),
      notes:
        "Parsed SMS was allocated directly from the group payee MoMo route.",
      metadata: {
        auto_match: true,
        group_id: matchedGroup.id,
        group_name: matchedGroup.name,
        group_type: groupType,
        provider: normalizeProviderId(rawSms.provider),
        allocation_source: "payee_route",
        receiver_source_of_truth: digits,
      },
    };
  }

  const matchedPartner = partnerMatches[0];
  if (!matchedPartner) {
    return null;
  }

  return {
    matchType: "payee_route_partner",
    matchStatus: "matched",
    ledgerStatus: "posted",
    targetTable: "partner_payment_routes",
    targetRecordId: matchedPartner.id,
    matchedReference: sourceReference(rawSms, parsed),
    notes:
      "Parsed SMS was allocated directly from the partner payee MoMo route.",
    metadata: {
      auto_match: true,
      partner_id: matchedPartner.partner_id,
      partner_name: matchedPartner.partner_name,
      partner_slug: matchedPartner.partner_slug,
      reconciliation_label: matchedPartner.reconciliation_label,
      provider: normalizeProviderId(rawSms.provider),
      allocation_source: "payee_route",
      receiver_source_of_truth: digits,
    },
  };
}
