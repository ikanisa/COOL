import {
  confirmRayonReferenceMatch as confirmSharedRayonReferenceMatch,
  looksLikeRayonReference,
} from "../_shared/rayon_payments.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";

type GroupContributionRecord = {
  id: string;
  group_id: string | null;
  status: string | null;
};

type GroupRouteRecord = {
  id: string;
  name: string;
  type: string | null;
  receiving_momo_code: string | null;
  momo_number: string | null;
  receiving_momo_route_type: string | null;
};

type PartnerRouteRecord = {
  id: string;
  partner_id: string;
  partner_name: string | null;
  partner_slug: string | null;
  recipient_code: string | null;
  reconciliation_label: string | null;
  status: string | null;
};

type GroupContributionCandidateRecord = {
  id: string;
  group_id: string | null;
  status: string | null;
  momo_reference: string | null;
  created_at: string | null;
  route_digits: string | null;
};

type DriverSubscriptionCandidateRecord = {
  id: string;
  driver_id: string;
  status: string | null;
  started_at: string | null;
  expires_at: string | null;
  momo_reference: string | null;
  created_at: string | null;
};

type RayonReferenceCandidateRecord = {
  reference: string;
  matchType: "rayon_ticket" | "rayon_shop_order" | "rayon_initiative_support";
  created_at: string | null;
  status: string | null;
};

export type AutoReconciliationResult = {
  matchType: string;
  matchStatus: "matched" | "pending_review" | "manual_review";
  ledgerStatus: "draft" | "posted";
  targetTable: string | null;
  targetRecordId: string | null;
  matchedReference: string | null;
  notes: string | null;
  metadata: Record<string, unknown>;
};

function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function asNullableInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }
  if (typeof value === "string") {
    const cleaned = value.replaceAll(/[^\d.-]/g, "");
    if (!cleaned) return null;
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? Math.round(parsed) : null;
  }
  return null;
}

export function ledgerEntryType(parsed: ParsedSms): "credit" | "debit" {
  return parsed.tx_direction === "credit" ? "credit" : "debit";
}

function normalizeProviderId(value: string | null | undefined): string | null {
  const normalized = value?.trim().toLowerCase();
  switch (normalized) {
    case "mtn":
    case "mtn rwanda":
    case "mtn_rwanda":
      return "mtn_rwanda";
    case "airtel":
      return "airtel";
    case "orange":
      return "orange";
    default:
      return normalized?.length ? normalized : null;
  }
}

function normalizeDigits(value: string | null | undefined): string | null {
  if (!value) {
    return null;
  }

  const digits = value.replaceAll(/\D/g, "");
  return digits.length > 0 ? digits : null;
}

function digitsMatch(left: string | null, right: string | null): boolean {
  if (!left || !right) {
    return false;
  }

  return left === right || left.endsWith(right) || right.endsWith(left);
}

function payeeRouteDigits(parsed: ParsedSms): string | null {
  return normalizeDigits(parsed.payee_number_or_code) ??
    normalizeDigits(parsed.merchant_code);
}

function parseIsoDate(value: string | null | undefined): Date | null {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function candidateTimestamp(
  parsed: ParsedSms,
  rawSms: RawSmsRecord,
): Date | null {
  return parseIsoDate(parsed.tx_datetime_iso) ??
    parseIsoDate(rawSms.sms_received_at);
}

function sourceReference(rawSms: RawSmsRecord, parsed: ParsedSms): string {
  return parsed.momo_tx_id ?? rawSms.detected_tx_id ?? `SMS-${rawSms.id}`;
}

function buildDirectCandidateScore(
  status: string | null,
  createdAt: string | null,
  payeeDigits: string | null,
  routeDigits: string | null,
  parsed: ParsedSms,
  rawSms: RawSmsRecord,
): number {
  let score = 0;
  const normalizedStatus = status?.trim().toLowerCase();
  if (normalizedStatus === "pending") {
    score += 30;
  } else if (
    normalizedStatus === "confirmed" ||
    normalizedStatus === "active" ||
    normalizedStatus === "paid" ||
    normalizedStatus === "valid"
  ) {
    score += 18;
  }

  const smsTime = candidateTimestamp(parsed, rawSms);
  const createdAtDate = parseIsoDate(createdAt);
  if (smsTime && createdAtDate) {
    const deltaMs = Math.abs(smsTime.getTime() - createdAtDate.getTime());
    if (deltaMs <= 10 * 60 * 1000) {
      score += 24;
    } else if (deltaMs <= 60 * 60 * 1000) {
      score += 18;
    } else if (deltaMs <= 6 * 60 * 60 * 1000) {
      score += 10;
    } else if (deltaMs <= 24 * 60 * 60 * 1000) {
      score += 4;
    } else {
      score -= 25;
    }
  }

  if (payeeDigits && routeDigits) {
    if (digitsMatch(routeDigits, payeeDigits)) {
      score += 14;
    } else if (
      routeDigits.length >= 3 &&
      payeeDigits.length >= 3 &&
      routeDigits.slice(-3) === payeeDigits.slice(-3)
    ) {
      score += 6;
    } else {
      score -= 10;
    }
  }

  return score;
}

function chooseBestCandidate<T>(
  scored: Array<{ candidate: T; score: number; key: string }>,
): {
  candidate: T | null;
  score: number | null;
  ambiguous: boolean;
} {
  const ranked = scored.sort((left, right) => right.score - left.score);
  const best = ranked[0];
  if (!best || best.score < 15) {
    return { candidate: null, score: best?.score ?? null, ambiguous: false };
  }

  const second = ranked[1];
  if (
    second &&
    second.key !== best.key &&
    second.score >= 15 &&
    Math.abs(best.score - second.score) <= 2
  ) {
    return { candidate: null, score: best.score, ambiguous: true };
  }

  return { candidate: best.candidate, score: best.score, ambiguous: false };
}

function looksLikeSubscriptionReference(reference: string): boolean {
  return reference.trim().toUpperCase().startsWith("SUB-");
}

function asGroupRouteRecord(value: Record<string, unknown>): GroupRouteRecord {
  return {
    id: asString(value["id"]) ?? "",
    name: asString(value["name"]) ?? "Savings group",
    type: asString(value["type"]),
    receiving_momo_code: asString(value["receiving_momo_code"]),
    momo_number: asString(value["momo_number"]),
    receiving_momo_route_type: asString(value["receiving_momo_route_type"]),
  };
}

function asPartnerRouteRecord(
  value: Record<string, unknown>,
): PartnerRouteRecord {
  const partner = asRecord(value["partners"]);
  return {
    id: asString(value["id"]) ?? "",
    partner_id: asString(value["partner_id"]) ?? "",
    partner_name: asString(partner?.["name"]),
    partner_slug: asString(partner?.["slug"]),
    recipient_code: asString(value["recipient_code"]),
    reconciliation_label: asString(value["reconciliation_label"]),
    status: asString(value["status"]),
  };
}

async function findGroupRouteMatches(
  adminClient: ReturnType<typeof createAdminClient>,
  parsed: ParsedSms,
): Promise<GroupRouteRecord[]> {
  const payeeDigits = payeeRouteDigits(parsed);
  if (!payeeDigits) {
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
      digitsMatch(normalizeDigits(group.receiving_momo_code), payeeDigits) ||
      digitsMatch(normalizeDigits(group.momo_number), payeeDigits)
    );
}

async function findPartnerRouteMatches(
  adminClient: ReturnType<typeof createAdminClient>,
  parsed: ParsedSms,
): Promise<PartnerRouteRecord[]> {
  const payeeDigits = payeeRouteDigits(parsed);
  if (!payeeDigits) {
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
      digitsMatch(normalizeDigits(route.recipient_code), payeeDigits)
    );
}

async function isGroupMember(
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

async function resolveExistingGroupContributionByPayeeRoute(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  group: GroupRouteRecord,
): Promise<GroupContributionRecord | null> {
  const sourceReference = parsed.momo_tx_id ?? rawSms.detected_tx_id ??
    `SMS-${rawSms.id}`;

  const byReference = await adminClient
    .from("group_contributions")
    .select("id, group_id, status")
    .eq("group_id", group.id)
    .eq("user_id", rawSms.user_id)
    .eq("momo_reference", sourceReference)
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
    .in("status", ["pending", "confirmed"])
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

async function ensureGroupContributionByPayeeRoute(
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
    // Atomically confirm the contribution and update group balance.
    // confirm_contribution() sets status → 'completed' and adds to groups.amount.
    await adminClient.rpc("confirm_contribution", {
      p_contribution_id: existing.id,
    });

    return {
      id: existing.id,
      group_id: existing.group_id,
      status: "completed",
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

  // Atomically confirm the contribution and update group balance.
  await adminClient.rpc("confirm_contribution", {
    p_contribution_id: insertedId,
  });

  return {
    id: insertedId,
    group_id: asString(insertResult.data.group_id),
    status: "completed",
  };
}

async function findGroupContributionCandidate(
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
    .in("status", ["pending", "confirmed"])
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

async function findDriverSubscriptionCandidate(
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

async function findRayonReferenceCandidate(
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

async function reconcileByPayeeRoute(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  timestamp: string,
): Promise<AutoReconciliationResult | null> {
  const payeeDigits = payeeRouteDigits(parsed);
  if (!payeeDigits) {
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
    const isMember = await isGroupMember(
      adminClient,
      matchedGroup.id,
      rawSms.user_id,
    );
    const groupType = matchedGroup.type?.trim().toLowerCase() ?? "saving";

    if (!isMember && groupType !== "community") {
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
        receiver_source_of_truth: payeeDigits,
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
      receiver_source_of_truth: payeeDigits,
    },
  };
}

export function buildManualReviewResult(
  reason: string,
  metadata: Record<string, unknown> = {},
): AutoReconciliationResult {
  return {
    matchType: "manual_review",
    matchStatus: "manual_review",
    ledgerStatus: "draft",
    targetTable: null,
    targetRecordId: null,
    matchedReference: null,
    notes: reason,
    metadata: {
      auto_match: false,
      ...metadata,
    },
  };
}

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

  const groupRouteMatch = await reconcileByPayeeRoute(
    adminClient,
    rawSms,
    parsed,
    timestamp,
  );
  if (groupRouteMatch?.targetTable === "group_contributions") {
    return groupRouteMatch;
  }

  const {
    candidate: contributionCandidate,
    score: contributionScore,
    ambiguous: contributionAmbiguous,
  } = await findGroupContributionCandidate(
    adminClient,
    rawSms,
    parsed,
  );

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

    // Update the momo_reference (keep status as 'pending' for the RPC).
    const updateResult = await adminClient
      .from("group_contributions")
      .update({
        momo_reference: matchedReference,
      })
      .eq("id", contributionCandidate.id);

    if (updateResult.error) {
      throw updateResult.error;
    }

    // Atomically confirm the contribution and update group balance.
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

  const {
    candidate: subscriptionCandidate,
    score: subscriptionScore,
    ambiguous: subscriptionAmbiguous,
  } = await findDriverSubscriptionCandidate(
    adminClient,
    rawSms,
    parsed,
  );

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

  const {
    candidate: rayonCandidate,
    score: rayonScore,
    ambiguous: rayonAmbiguous,
  } = await findRayonReferenceCandidate(
    adminClient,
    rawSms,
    parsed,
  );

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
