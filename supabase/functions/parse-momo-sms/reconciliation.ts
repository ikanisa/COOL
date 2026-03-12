import {
  confirmRayonPendingTransaction as confirmSharedRayonPendingTransaction,
  looksLikeRayonReference,
} from "../_shared/rayon_payments.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { sendTextMessage } from "../_shared/whatsapp.ts";
import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import {
  planRayonInitiativeConfirmation,
  planRayonShopOrderConfirmation,
  planRayonTicketConfirmation,
} from "./rayon_confirmation.ts";

type PendingTransactionRecord = {
  id: string;
  user_id: string | null;
  group_id: string | null;
  group_contribution_id: string | null;
  reference: string;
  recipient_momo: string | null;
  amount: number;
  provider: string | null;
  status: string | null;
  created_at: string | null;
  confirmed_at: string | null;
};

type GroupContributionRecord = {
  id: string;
  group_id: string | null;
  status: string | null;
};

type DriverSubscriptionRecord = {
  id: string;
  driver_id: string;
  status: string | null;
  started_at: string | null;
  expires_at: string | null;
};

type UserContactRecord = {
  id: string;
  full_name: string | null;
  phone: string | null;
  whatsapp_number: string | null;
};

type RsTicketRecord = {
  id: string;
  user_id: string;
  match_id: string | null;
  seat_type: string | null;
  amount_paid: number;
  qr_code: string | null;
  momo_reference: string | null;
  status: string | null;
  match_title: string;
  competition: string | null;
  venue: string | null;
  match_date: string | null;
  kickoff_time: string | null;
  partner_id: string | null;
};

type RsShopOrderRecord = {
  id: string;
  user_id: string;
  total: number;
  delivery_address: string | null;
  momo_reference: string | null;
  status: string | null;
};

type RsInitiativeContributionRecord = {
  id: string;
  user_id: string;
  initiative_id: string | null;
  amount: number;
  momo_reference: string | null;
  status: string | null;
  initiative_title: string;
  partner_id: string | null;
};

export type AutoReconciliationResult = {
  matchType: string;
  matchStatus: "matched" | "pending_review" | "manual_review";
  ledgerStatus: "draft" | "posted";
  targetTable: string | null;
  targetRecordId: string | null;
  matchedReference: string | null;
  pendingTransactionId: string | null;
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

function normalizeLast3(value: string | null): string | null {
  if (!value) return null;
  const digits = value.replaceAll(/\D/g, "");
  if (!digits) return null;
  return digits.slice(-3);
}

function shortTime(value: string | null): string | null {
  if (!value) {
    return null;
  }
  return value.length > 5 ? value.slice(0, 5) : value;
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

function looksLikeSubscriptionReference(reference: string): boolean {
  return reference.trim().toUpperCase().startsWith("SUB-");
}

function asPendingTransactionRecord(
  value: Record<string, unknown>,
): PendingTransactionRecord {
  return {
    id: asString(value["id"]) ?? "",
    user_id: asString(value["user_id"]),
    group_id: asString(value["group_id"]),
    group_contribution_id: asString(value["group_contribution_id"]),
    reference: asString(value["reference"]) ?? "",
    recipient_momo: asString(value["recipient_momo"]),
    amount: asNullableInt(value["amount"]) ?? 0,
    provider: asString(value["provider"]),
    status: asString(value["status"]),
    created_at: asString(value["created_at"]),
    confirmed_at: asString(value["confirmed_at"]),
  };
}

function asUserContactRecord(
  value: Record<string, unknown>,
): UserContactRecord {
  return {
    id: asString(value["id"]) ?? "",
    full_name: asString(value["full_name"]),
    phone: asString(value["phone"]),
    whatsapp_number: asString(value["whatsapp_number"]),
  };
}

function asRsTicketRecord(value: Record<string, unknown>): RsTicketRecord {
  const match = asRecord(value["rs_matches"]);
  const homeTeam = asString(match?.["home_team"]) ?? "Rayon Sports FC";
  const awayTeam = asString(match?.["away_team"]) ?? "Opponent";

  return {
    id: asString(value["id"]) ?? "",
    user_id: asString(value["user_id"]) ?? "",
    match_id: asString(value["match_id"]),
    seat_type: asString(value["seat_type"]),
    amount_paid: asNullableInt(value["amount_paid"]) ?? 0,
    qr_code: asString(value["qr_code"]),
    momo_reference: asString(value["momo_reference"]),
    status: asString(value["status"]),
    match_title: `${homeTeam} vs ${awayTeam}`,
    competition: asString(match?.["competition"]),
    venue: asString(match?.["venue"]),
    match_date: asString(match?.["match_date"]),
    kickoff_time: shortTime(asString(match?.["kickoff_time"])),
    partner_id: asString(match?.["partner_id"]),
  };
}

function asRsShopOrderRecord(
  value: Record<string, unknown>,
): RsShopOrderRecord {
  return {
    id: asString(value["id"]) ?? "",
    user_id: asString(value["user_id"]) ?? "",
    total: asNullableInt(value["total"]) ?? 0,
    delivery_address: asString(value["delivery_address"]),
    momo_reference: asString(value["momo_reference"]),
    status: asString(value["status"]),
  };
}

function asRsInitiativeContributionRecord(
  value: Record<string, unknown>,
): RsInitiativeContributionRecord {
  const initiative = asRecord(value["rs_initiatives"]);

  return {
    id: asString(value["id"]) ?? "",
    user_id: asString(value["user_id"]) ?? "",
    initiative_id: asString(value["initiative_id"]),
    amount: asNullableInt(value["amount"]) ?? 0,
    momo_reference: asString(value["momo_reference"]),
    status: asString(value["status"]),
    initiative_title: asString(initiative?.["title"]) ??
      "Rayon Sports Initiative",
    partner_id: asString(initiative?.["partner_id"]),
  };
}

function buildPendingCandidateScore(
  candidate: PendingTransactionRecord,
  parsed: ParsedSms,
  rawSms: RawSmsRecord,
): number {
  let score = 0;

  if (candidate.status === "pending") {
    score += 30;
  } else if (candidate.status === "confirmed") {
    score += 18;
  }

  const parsedProvider = normalizeProviderId(rawSms.provider);
  const candidateProvider = normalizeProviderId(candidate.provider);
  if (
    parsedProvider && candidateProvider && parsedProvider === candidateProvider
  ) {
    score += 15;
  }

  const smsTime = candidateTimestamp(parsed, rawSms);
  const createdAt = parseIsoDate(candidate.created_at);
  if (smsTime && createdAt) {
    const deltaMs = Math.abs(smsTime.getTime() - createdAt.getTime());
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

  const recipientDigits = normalizeDigits(candidate.recipient_momo);
  const payeeDigits = normalizeDigits(parsed.payee_number_or_code) ??
    normalizeDigits(parsed.merchant_code);
  if (recipientDigits && payeeDigits) {
    if (
      recipientDigits.endsWith(payeeDigits) ||
      payeeDigits.endsWith(recipientDigits)
    ) {
      score += 14;
    } else if (
      recipientDigits.length >= 3 &&
      payeeDigits.length >= 3 &&
      recipientDigits.slice(-3) === payeeDigits.slice(-3)
    ) {
      score += 6;
    } else {
      score -= 10;
    }
  }

  if (candidate.group_contribution_id) {
    score += 3;
  }

  if (looksLikeSubscriptionReference(candidate.reference)) {
    score += 1;
  }

  return score;
}

async function findPendingTransactionCandidate(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
): Promise<{
  candidate: PendingTransactionRecord | null;
  score: number | null;
}> {
  if (parsed.amount == null || parsed.amount <= 0) {
    return { candidate: null, score: null };
  }

  const columns = [
    "id",
    "user_id",
    "group_id",
    "group_contribution_id",
    "reference",
    "recipient_momo",
    "amount",
    "provider",
    "status",
    "created_at",
    "confirmed_at",
  ].join(", ");
  const provider = normalizeProviderId(rawSms.provider);

  const fetchCandidates = async (strictProvider: boolean) => {
    let query = adminClient
      .from("pending_transactions")
      .select(columns)
      .eq("user_id", rawSms.user_id)
      .in("status", ["pending", "confirmed"])
      .eq("amount", parsed.amount)
      .order("created_at", { ascending: false })
      .limit(20);

    if (strictProvider && provider) {
      query = query.eq("provider", provider);
    }

    const result = await query;
    if (result.error) {
      throw result.error;
    }

    const rows = Array.isArray(result.data) ? result.data : [];
    return rows.map((row) =>
      asPendingTransactionRecord(row as unknown as Record<string, unknown>)
    );
  };

  const strictCandidates = await fetchCandidates(true);
  const candidates = strictCandidates.length > 0 || !provider
    ? strictCandidates
    : await fetchCandidates(false);

  if (candidates.length === 0) {
    return { candidate: null, score: null };
  }

  const scored = candidates
    .map((candidate) => ({
      candidate,
      score: buildPendingCandidateScore(candidate, parsed, rawSms),
    }))
    .sort((left, right) => right.score - left.score);

  const best = scored[0];
  if (!best || best.score < 15) {
    return { candidate: null, score: best?.score ?? null };
  }

  return best;
}

async function resolveGroupContribution(
  adminClient: ReturnType<typeof createAdminClient>,
  pendingTransaction: PendingTransactionRecord,
): Promise<GroupContributionRecord | null> {
  const directId = pendingTransaction.group_contribution_id;
  const byId = directId
    ? await adminClient
      .from("group_contributions")
      .select("id, group_id, status")
      .eq("id", directId)
      .maybeSingle()
    : null;

  if (byId?.error) {
    throw byId.error;
  }

  if (byId?.data) {
    return {
      id: asString(byId.data.id) ?? "",
      group_id: asString(byId.data.group_id),
      status: asString(byId.data.status),
    };
  }

  const byReference = await adminClient
    .from("group_contributions")
    .select("id, group_id, status")
    .eq("momo_reference", pendingTransaction.reference)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (byReference.error) {
    throw byReference.error;
  }

  if (!byReference.data) {
    return null;
  }

  return {
    id: asString(byReference.data.id) ?? "",
    group_id: asString(byReference.data.group_id),
    status: asString(byReference.data.status),
  };
}

async function resolveDriverSubscription(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  pendingTransaction: PendingTransactionRecord,
): Promise<DriverSubscriptionRecord | null> {
  const result = await adminClient
    .from("driver_subscriptions")
    .select("id, driver_id, status, started_at, expires_at")
    .eq("driver_id", rawSms.user_id)
    .eq("momo_reference", pendingTransaction.reference)
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
    driver_id: asString(result.data.driver_id) ?? rawSms.user_id,
    status: asString(result.data.status),
    started_at: asString(result.data.started_at),
    expires_at: asString(result.data.expires_at),
  };
}

async function resolveUserContact(
  adminClient: ReturnType<typeof createAdminClient>,
  userId: string,
): Promise<UserContactRecord | null> {
  const result = await adminClient
    .from("users")
    .select("id, full_name, phone, whatsapp_number")
    .eq("id", userId)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  if (!result.data) {
    return null;
  }

  return asUserContactRecord(result.data as Record<string, unknown>);
}

async function resolveRayonPartnerId(
  adminClient: ReturnType<typeof createAdminClient>,
): Promise<string | null> {
  const lookupNames = ["Rayon Sports FC", "Rayon Sports"];
  const exactResult = await adminClient
    .from("partners")
    .select("id, name")
    .in("name", lookupNames);

  if (exactResult.error) {
    throw exactResult.error;
  }

  if (Array.isArray(exactResult.data)) {
    for (const lookupName of lookupNames) {
      const match = exactResult.data.find((row) =>
        asString((row as Record<string, unknown>).name) === lookupName
      );
      const id = asString((match as Record<string, unknown> | undefined)?.id);
      if (id) {
        return id;
      }
    }
  }

  const result = await adminClient
    .from("partners")
    .select("id")
    .ilike("name", "Rayon Sports%")
    .order("name")
    .limit(1)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  return asString(result.data?.id);
}

async function resolveRayonTickets(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  pendingTransaction: PendingTransactionRecord,
): Promise<RsTicketRecord[]> {
  const result = await adminClient
    .from("rs_tickets")
    .select(
      "id, user_id, match_id, seat_type, amount_paid, qr_code, momo_reference, status, rs_matches(home_team, away_team, competition, venue, match_date, kickoff_time, partner_id)",
    )
    .eq("user_id", rawSms.user_id)
    .eq("momo_reference", pendingTransaction.reference)
    .order("purchased_at", { ascending: false });

  if (result.error) {
    throw result.error;
  }

  if (!Array.isArray(result.data) || result.data.length === 0) {
    return [];
  }

  return result.data.map((row) =>
    asRsTicketRecord(row as Record<string, unknown>)
  );
}

async function resolveRayonShopOrder(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  pendingTransaction: PendingTransactionRecord,
): Promise<RsShopOrderRecord | null> {
  const result = await adminClient
    .from("rs_shop_orders")
    .select("id, user_id, total, delivery_address, momo_reference, status")
    .eq("user_id", rawSms.user_id)
    .eq("momo_reference", pendingTransaction.reference)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  if (!result.data) {
    return null;
  }

  return asRsShopOrderRecord(result.data as Record<string, unknown>);
}

async function resolveRayonInitiativeContribution(
  adminClient: ReturnType<typeof createAdminClient>,
  rawSms: RawSmsRecord,
  pendingTransaction: PendingTransactionRecord,
): Promise<RsInitiativeContributionRecord | null> {
  const result = await adminClient
    .from("rs_initiative_contributions")
    .select(
      "id, user_id, initiative_id, amount, momo_reference, status, rs_initiatives(title, partner_id)",
    )
    .eq("user_id", rawSms.user_id)
    .eq("momo_reference", pendingTransaction.reference)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  if (!result.data) {
    return null;
  }

  return asRsInitiativeContributionRecord(
    result.data as Record<string, unknown>,
  );
}

function formatRwf(amount: number): string {
  return `RWF ${amount}`;
}

async function maybeAwardRayonMembershipPoints(
  adminClient: ReturnType<typeof createAdminClient>,
  userId: string,
  partnerId: string | null,
  points: number,
): Promise<boolean> {
  if (!partnerId || points <= 0) {
    return false;
  }

  const result = await adminClient.rpc("rs_apply_membership_points", {
    p_user_id: userId,
    p_partner_id: partnerId,
    p_points: points,
  });

  if (result.error) {
    console.error("Failed to award Rayon Sports points", result.error);
    return false;
  }

  return true;
}

async function maybeSendWhatsAppConfirmation(
  phone: string | null,
  body: string,
): Promise<boolean> {
  if (!phone) {
    return false;
  }

  try {
    await sendTextMessage({ phone, body });
    return true;
  } catch (error) {
    console.error("Failed to send WhatsApp confirmation", error);
    return false;
  }
}

function buildRayonTicketConfirmationMessage(
  tickets: RsTicketRecord[],
): string {
  const [ticket] = tickets;
  if (!ticket) {
    return "✅ Gikundiro ticket confirmed";
  }

  const totalAmount = tickets.reduce(
    (sum, entry) => sum + entry.amount_paid,
    0,
  );
  const lines = [
    "✅ Gikundiro ticket confirmed",
    ticket.match_title,
  ];

  const matchMeta = [ticket.venue, ticket.match_date, ticket.kickoff_time]
    .filter((value) => value && value.length > 0)
    .join(" · ");
  if (matchMeta.length > 0) {
    lines.push(matchMeta);
  }

  if (tickets.length > 1) {
    lines.push(
      `${tickets.length} tickets · ${formatRwf(totalAmount)}`,
      `Reference: ${ticket.momo_reference ?? ticket.id}`,
    );
  } else {
    lines.push(
      `${ticket.seat_type ?? "General"} · ${formatRwf(ticket.amount_paid)}`,
      `Reference: ${ticket.momo_reference ?? ticket.id}`,
    );
  }

  return lines.join("\n");
}

function buildRayonShopConfirmationMessage(order: RsShopOrderRecord): string {
  const lines = [
    "✅ Gikundiro shop order confirmed",
    `${formatRwf(order.total)} · Official club merchandise`,
  ];

  if (order.delivery_address) {
    lines.push(`Delivery: ${order.delivery_address}`);
  }

  lines.push(`Reference: ${order.momo_reference ?? order.id}`);
  return lines.join("\n");
}

function buildRayonSupportConfirmationMessage(
  contribution: RsInitiativeContributionRecord,
): string {
  return [
    "✅ Gikundiro support confirmed",
    contribution.initiative_title,
    `${formatRwf(contribution.amount)} contributed`,
    `Reference: ${contribution.momo_reference ?? contribution.id}`,
  ].join("\n");
}

async function confirmRayonTickets(
  adminClient: ReturnType<typeof createAdminClient>,
  pendingTransaction: PendingTransactionRecord,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  parsedSmsId: string,
  timestamp: string,
  tickets: RsTicketRecord[],
  score: number | null,
): Promise<AutoReconciliationResult> {
  const [ticket] = tickets;
  if (!ticket) {
    return buildManualReviewResult(
      "Rayon ticket rows were not found for the matched payment reference.",
      {
        reason: "missing_rayon_ticket_rows",
        matched_reference: pendingTransaction.reference,
      },
    );
  }

  const confirmations = tickets.map((entry) => ({
    ticket: entry,
    confirmation: planRayonTicketConfirmation(entry.status),
  }));

  for (const entry of confirmations) {
    const updateResult = await adminClient
      .from("rs_tickets")
      .update({
        status: entry.confirmation.nextStatus,
        updated_at: timestamp,
      })
      .eq("id", entry.ticket.id);

    if (updateResult.error) {
      throw updateResult.error;
    }
  }

  await confirmPendingTransaction(
    adminClient,
    pendingTransaction,
    rawSms,
    parsed,
    parsedSmsId,
    timestamp,
  );

  const pointsToAward = confirmations.reduce(
    (sum, entry) => sum + entry.confirmation.pointsToAward,
    0,
  );
  const pointsAwarded = await maybeAwardRayonMembershipPoints(
    adminClient,
    ticket.user_id,
    ticket.partner_id,
    pointsToAward,
  );
  const shouldSendWhatsApp = confirmations.some((entry) =>
    entry.confirmation.shouldSendWhatsApp
  );
  const contact = shouldSendWhatsApp
    ? await resolveUserContact(adminClient, ticket.user_id)
    : null;
  const whatsappSent = await maybeSendWhatsAppConfirmation(
    contact?.whatsapp_number ?? contact?.phone ?? null,
    buildRayonTicketConfirmationMessage(tickets),
  );

  return {
    matchType: "rayon_ticket",
    matchStatus: "matched",
    ledgerStatus: "posted",
    targetTable: "rs_tickets",
    targetRecordId: ticket.id,
    matchedReference: pendingTransaction.reference,
    pendingTransactionId: pendingTransaction.id,
    notes: "Parsed SMS matched a Rayon Sports ticket payment.",
    metadata: {
      auto_match: true,
      candidate_score: score,
      provider: normalizeProviderId(rawSms.provider),
      partner_id: ticket.partner_id,
      ticket_count: tickets.length,
      ticket_ids: tickets.map((entry) => entry.id),
      points_awarded: pointsAwarded ? pointsToAward : 0,
      whatsapp_sent: whatsappSent,
    },
  };
}

async function confirmRayonShopOrder(
  adminClient: ReturnType<typeof createAdminClient>,
  pendingTransaction: PendingTransactionRecord,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  parsedSmsId: string,
  timestamp: string,
  order: RsShopOrderRecord,
  score: number | null,
): Promise<AutoReconciliationResult> {
  const confirmation = planRayonShopOrderConfirmation(
    order.status,
    order.total,
  );

  const updateResult = await adminClient
    .from("rs_shop_orders")
    .update({
      status: confirmation.nextStatus,
      updated_at: timestamp,
    })
    .eq("id", order.id);

  if (updateResult.error) {
    throw updateResult.error;
  }

  await confirmPendingTransaction(
    adminClient,
    pendingTransaction,
    rawSms,
    parsed,
    parsedSmsId,
    timestamp,
  );

  const partnerId = await resolveRayonPartnerId(adminClient);
  const pointsAwarded = await maybeAwardRayonMembershipPoints(
    adminClient,
    order.user_id,
    partnerId,
    confirmation.pointsToAward,
  );
  const contact = confirmation.shouldSendWhatsApp
    ? await resolveUserContact(adminClient, order.user_id)
    : null;
  const whatsappSent = await maybeSendWhatsAppConfirmation(
    contact?.whatsapp_number ?? contact?.phone ?? null,
    buildRayonShopConfirmationMessage(order),
  );

  return {
    matchType: "rayon_shop_order",
    matchStatus: "matched",
    ledgerStatus: "posted",
    targetTable: "rs_shop_orders",
    targetRecordId: order.id,
    matchedReference: pendingTransaction.reference,
    pendingTransactionId: pendingTransaction.id,
    notes: "Parsed SMS matched a Rayon Sports shop order payment.",
    metadata: {
      auto_match: true,
      candidate_score: score,
      provider: normalizeProviderId(rawSms.provider),
      partner_id: partnerId,
      points_awarded: pointsAwarded ? confirmation.pointsToAward : 0,
      whatsapp_sent: whatsappSent,
    },
  };
}

async function confirmRayonInitiativeContribution(
  adminClient: ReturnType<typeof createAdminClient>,
  pendingTransaction: PendingTransactionRecord,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  parsedSmsId: string,
  timestamp: string,
  contribution: RsInitiativeContributionRecord,
  score: number | null,
): Promise<AutoReconciliationResult> {
  const confirmation = planRayonInitiativeConfirmation(
    contribution.status,
    contribution.amount,
  );

  const updateResult = await adminClient
    .from("rs_initiative_contributions")
    .update({
      status: confirmation.nextStatus,
      updated_at: timestamp,
    })
    .eq("id", contribution.id);

  if (updateResult.error) {
    throw updateResult.error;
  }

  if (
    confirmation.shouldIncrementInitiativeTotals && contribution.initiative_id
  ) {
    const initiativeResult = await adminClient
      .from("rs_initiatives")
      .select("raised_amount, supporter_count")
      .eq("id", contribution.initiative_id)
      .maybeSingle();

    if (initiativeResult.error) {
      throw initiativeResult.error;
    }

    const currentRaised = asNullableInt(initiativeResult.data?.raised_amount) ??
      0;
    const currentSupporters =
      asNullableInt(initiativeResult.data?.supporter_count) ?? 0;

    const correctedResult = await adminClient
      .from("rs_initiatives")
      .update({
        raised_amount: currentRaised + contribution.amount,
        supporter_count: currentSupporters + 1,
        updated_at: timestamp,
      })
      .eq("id", contribution.initiative_id);

    if (correctedResult.error) {
      throw correctedResult.error;
    }
  }

  await confirmPendingTransaction(
    adminClient,
    pendingTransaction,
    rawSms,
    parsed,
    parsedSmsId,
    timestamp,
  );

  const pointsAwarded = await maybeAwardRayonMembershipPoints(
    adminClient,
    contribution.user_id,
    contribution.partner_id,
    confirmation.pointsToAward,
  );
  const contact = confirmation.shouldSendWhatsApp
    ? await resolveUserContact(adminClient, contribution.user_id)
    : null;
  const whatsappSent = await maybeSendWhatsAppConfirmation(
    contact?.whatsapp_number ?? contact?.phone ?? null,
    buildRayonSupportConfirmationMessage(contribution),
  );

  return {
    matchType: "rayon_initiative_support",
    matchStatus: "matched",
    ledgerStatus: "posted",
    targetTable: "rs_initiative_contributions",
    targetRecordId: contribution.id,
    matchedReference: pendingTransaction.reference,
    pendingTransactionId: pendingTransaction.id,
    notes: "Parsed SMS matched a Rayon Sports initiative contribution.",
    metadata: {
      auto_match: true,
      candidate_score: score,
      provider: normalizeProviderId(rawSms.provider),
      partner_id: contribution.partner_id,
      points_awarded: pointsAwarded ? confirmation.pointsToAward : 0,
      whatsapp_sent: whatsappSent,
    },
  };
}

async function confirmPendingTransaction(
  adminClient: ReturnType<typeof createAdminClient>,
  pendingTransaction: PendingTransactionRecord,
  rawSms: RawSmsRecord,
  parsed: ParsedSms,
  parsedSmsId: string,
  timestamp: string,
) {
  const confirmationTimestamp = pendingTransaction.confirmed_at ?? timestamp;

  const result = await adminClient
    .from("pending_transactions")
    .update({
      status: "confirmed",
      confirmed_at: confirmationTimestamp,
      updated_at: timestamp,
      raw_payload: {
        source: "parse-momo-sms",
        raw_sms_id: rawSms.id,
        parsed_sms_id: parsedSmsId,
        provider: normalizeProviderId(rawSms.provider),
        country: rawSms.country,
        sender: rawSms.sender,
        tx_type: parsed.tx_type,
        tx_direction: parsed.tx_direction,
        amount_rwf: parsed.amount,
        transaction_id: parsed.momo_tx_id ?? rawSms.detected_tx_id,
        confidence: parsed.confidence,
        payee_name: parsed.payee_name,
        payee_number_or_code: parsed.payee_number_or_code,
        merchant_code: parsed.merchant_code,
        sms_received_at: rawSms.sms_received_at,
      },
    })
    .eq("id", pendingTransaction.id);

  if (result.error) {
    throw result.error;
  }
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
    pendingTransactionId: null,
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

  const { candidate, score } = await findPendingTransactionCandidate(
    adminClient,
    rawSms,
    parsed,
  );
  if (!candidate) {
    return buildManualReviewResult(
      "No pending app payment matched the parsed SMS amount and timing.",
      { reason: "no_pending_transaction_match", candidate_score: score },
    );
  }

  if (looksLikeRayonReference(candidate.reference)) {
    return await confirmSharedRayonPendingTransaction(adminClient, candidate, {
      source: "parse-momo-sms",
      timestamp,
      provider: normalizeProviderId(rawSms.provider),
      amount: parsed.amount,
      transactionId: parsed.momo_tx_id ?? rawSms.detected_tx_id,
      payeeNumberOrCode: parsed.payee_number_or_code,
      merchantCode: parsed.merchant_code,
      candidateScore: score,
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

  const resolveSubscriptionFirst = looksLikeSubscriptionReference(
    candidate.reference,
  );
  const subscription = resolveSubscriptionFirst
    ? await resolveDriverSubscription(adminClient, rawSms, candidate)
    : null;
  const contribution = subscription == null
    ? await resolveGroupContribution(adminClient, candidate)
    : null;
  const fallbackSubscription = contribution == null && !resolveSubscriptionFirst
    ? await resolveDriverSubscription(adminClient, rawSms, candidate)
    : null;

  const matchedSubscription = subscription ?? fallbackSubscription;
  if (matchedSubscription) {
    const startedAt = matchedSubscription.started_at ?? timestamp;
    const expiresAt = matchedSubscription.expires_at ??
      new Date(Date.parse(startedAt) + 30 * 24 * 60 * 60 * 1000).toISOString();

    const updateResult = await adminClient
      .from("driver_subscriptions")
      .update({
        status: "active",
        started_at: startedAt,
        expires_at: expiresAt,
        updated_at: timestamp,
      })
      .eq("id", matchedSubscription.id);

    if (updateResult.error) {
      throw updateResult.error;
    }

    await confirmPendingTransaction(
      adminClient,
      candidate,
      rawSms,
      parsed,
      parsedSmsId,
      timestamp,
    );

    return {
      matchType: "pending_transaction_reference",
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: "driver_subscriptions",
      targetRecordId: matchedSubscription.id,
      matchedReference: candidate.reference,
      pendingTransactionId: candidate.id,
      notes: "Parsed SMS matched a driver subscription payment.",
      metadata: {
        auto_match: true,
        candidate_score: score,
        provider: normalizeProviderId(rawSms.provider),
      },
    };
  }

  if (contribution) {
    const updateResult = await adminClient
      .from("group_contributions")
      .update({
        status: "confirmed",
      })
      .eq("id", contribution.id);

    if (updateResult.error) {
      throw updateResult.error;
    }

    await confirmPendingTransaction(
      adminClient,
      candidate,
      rawSms,
      parsed,
      parsedSmsId,
      timestamp,
    );

    return {
      matchType: "pending_transaction_reference",
      matchStatus: "matched",
      ledgerStatus: "posted",
      targetTable: "group_contributions",
      targetRecordId: contribution.id,
      matchedReference: candidate.reference,
      pendingTransactionId: candidate.id,
      notes: "Parsed SMS matched a group contribution payment.",
      metadata: {
        auto_match: true,
        candidate_score: score,
        group_id: contribution.group_id,
        provider: normalizeProviderId(rawSms.provider),
      },
    };
  }

  return {
    matchType: "pending_transaction_only",
    matchStatus: "pending_review",
    ledgerStatus: "draft",
    targetTable: null,
    targetRecordId: null,
    matchedReference: candidate.reference,
    pendingTransactionId: candidate.id,
    notes:
      "Pending transaction matched, but no contribution or subscription record was resolved.",
    metadata: {
      auto_match: false,
      candidate_score: score,
      reason: "target_record_not_found",
      provider: normalizeProviderId(rawSms.provider),
    },
  };
}
