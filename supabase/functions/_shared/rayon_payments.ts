import { createAdminClient } from "./supabase.ts";
import { sendTextMessage } from "./whatsapp.ts";
import {
  planRayonInitiativeConfirmation,
  planRayonShopOrderConfirmation,
  planRayonTicketConfirmation,
} from "../parse-momo-sms/rayon_confirmation.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

export type PendingTransactionRecord = {
  id: string;
  user_id: string | null;
  reference: string;
  amount: number;
  provider: string | null;
  status: string | null;
  confirmed_at: string | null;
};

type UserContactRecord = {
  phone: string | null;
  whatsapp_number: string | null;
};

type RsTicketRecord = {
  id: string;
  user_id: string;
  referral_invite_id: string | null;
  seat_type: string | null;
  amount_paid: number;
  momo_reference: string | null;
  status: string | null;
  match_title: string;
  venue: string | null;
  match_date: string | null;
  kickoff_time: string | null;
  partner_id: string | null;
};

type RsShopOrderRecord = {
  id: string;
  user_id: string;
  referral_invite_id: string | null;
  total: number;
  delivery_address: string | null;
  momo_reference: string | null;
  status: string | null;
};

type RsInitiativeContributionRecord = {
  id: string;
  user_id: string;
  referral_invite_id: string | null;
  initiative_id: string | null;
  amount: number;
  momo_reference: string | null;
  status: string | null;
  initiative_title: string;
  partner_id: string | null;
};

export type RayonPaymentConfirmationResult = {
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

export type RayonPaymentConfirmationContext = {
  source: "parse-momo-sms" | "rs-momo-webhook";
  timestamp: string;
  provider: string | null;
  amount: number | null;
  transactionId?: string | null;
  payeeNumberOrCode?: string | null;
  merchantCode?: string | null;
  candidateScore?: number | null;
  confidence?: number | null;
  rawSmsId?: string | null;
  parsedSmsId?: string | null;
  sender?: string | null;
  country?: string | null;
  extraPayload?: Record<string, unknown>;
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

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function shortTime(value: string | null): string | null {
  if (!value) {
    return null;
  }
  return value.length > 5 ? value.slice(0, 5) : value;
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

export function looksLikeRayonTicketReference(reference: string): boolean {
  return reference.trim().toUpperCase().startsWith("RS-TICKET-");
}

export function looksLikeRayonShopReference(reference: string): boolean {
  return reference.trim().toUpperCase().startsWith("RS-SHOP-");
}

export function looksLikeRayonSupportReference(reference: string): boolean {
  return reference.trim().toUpperCase().startsWith("RS-SUPPORT-");
}

export function looksLikeRayonReference(reference: string): boolean {
  return looksLikeRayonTicketReference(reference) ||
    looksLikeRayonShopReference(reference) ||
    looksLikeRayonSupportReference(reference);
}

export function buildManualReviewResult(
  reason: string,
  metadata: Record<string, unknown> = {},
): RayonPaymentConfirmationResult {
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

export async function resolvePendingTransactionByReference(
  adminClient: AdminClient,
  reference: string,
): Promise<PendingTransactionRecord | null> {
  const result = await adminClient
    .from("pending_transactions")
    .select(
      "id, user_id, reference, amount, provider, status, confirmed_at",
    )
    .eq("reference", reference)
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
    user_id: asString(result.data.user_id),
    reference: asString(result.data.reference) ?? "",
    amount: asNullableInt(result.data.amount) ?? 0,
    provider: asString(result.data.provider),
    status: asString(result.data.status),
    confirmed_at: asString(result.data.confirmed_at),
  };
}

async function resolveUserContact(
  adminClient: AdminClient,
  userId: string,
): Promise<UserContactRecord | null> {
  const result = await adminClient
    .from("users")
    .select("phone, whatsapp_number")
    .eq("id", userId)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  if (!result.data) {
    return null;
  }

  return {
    phone: asString(result.data.phone),
    whatsapp_number: asString(result.data.whatsapp_number),
  };
}

async function resolveRayonPartnerId(
  adminClient: AdminClient,
): Promise<string | null> {
  const lookupNames = ["Rayon Sports FC", "Rayon Sports"];
  const exactResult = await adminClient
    .from("partners")
    .select("id, name")
    .in("name", lookupNames);

  if (exactResult.error) {
    throw exactResult.error;
  }

  const exactRows = Array.isArray(exactResult.data)
    ? exactResult.data as Record<string, unknown>[]
    : [];
  for (const name of lookupNames) {
    for (const row of exactRows) {
      if (asString(row.name) == name) {
        const id = asString(row.id);
        if (id) {
          return id;
        }
      }
    }
  }

  const fallbackResult = await adminClient
    .from("partners")
    .select("id")
    .ilike("name", "Rayon Sports%")
    .maybeSingle();

  if (fallbackResult.error) {
    throw fallbackResult.error;
  }

  return asString(fallbackResult.data?.id);
}

async function resolveRayonTickets(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
): Promise<RsTicketRecord[]> {
  const result = await adminClient
    .from("rs_tickets")
    .select(
      "id, user_id, referral_invite_id, match_id, seat_type, amount_paid, qr_code, momo_reference, status, rs_matches(home_team, away_team, competition, venue, match_date, kickoff_time, partner_id)",
    )
    .eq("momo_reference", pendingTransaction.reference)
    .order("purchased_at", { ascending: false });

  if (result.error) {
    throw result.error;
  }

  const rows = Array.isArray(result.data) ? result.data : [];
  return rows.map((value) => {
    const row = value as Record<string, unknown>;
    const match = asRecord(row.rs_matches);
    const homeTeam = asString(match?.home_team) ?? "Rayon Sports FC";
    const awayTeam = asString(match?.away_team) ?? "Opponent";

    return {
      id: asString(row.id) ?? "",
      user_id: asString(row.user_id) ?? "",
      referral_invite_id: asString(row.referral_invite_id),
      seat_type: asString(row.seat_type),
      amount_paid: asNullableInt(row.amount_paid) ?? 0,
      momo_reference: asString(row.momo_reference),
      status: asString(row.status),
      match_title: `${homeTeam} vs ${awayTeam}`,
      venue: asString(match?.venue),
      match_date: asString(match?.match_date),
      kickoff_time: shortTime(asString(match?.kickoff_time)),
      partner_id: asString(match?.partner_id),
    };
  });
}

async function resolveRayonShopOrder(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
): Promise<RsShopOrderRecord | null> {
  const result = await adminClient
    .from("rs_shop_orders")
    .select(
      "id, user_id, referral_invite_id, total, delivery_address, momo_reference, status",
    )
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
    user_id: asString(result.data.user_id) ?? "",
    referral_invite_id: asString(result.data.referral_invite_id),
    total: asNullableInt(result.data.total) ?? 0,
    delivery_address: asString(result.data.delivery_address),
    momo_reference: asString(result.data.momo_reference),
    status: asString(result.data.status),
  };
}

async function resolveRayonInitiativeContribution(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
): Promise<RsInitiativeContributionRecord | null> {
  const result = await adminClient
    .from("rs_initiative_contributions")
    .select(
      "id, user_id, referral_invite_id, initiative_id, amount, momo_reference, status, rs_initiatives(title, partner_id)",
    )
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

  const initiative = asRecord(result.data.rs_initiatives);
  return {
    id: asString(result.data.id) ?? "",
    user_id: asString(result.data.user_id) ?? "",
    referral_invite_id: asString(result.data.referral_invite_id),
    initiative_id: asString(result.data.initiative_id),
    amount: asNullableInt(result.data.amount) ?? 0,
    momo_reference: asString(result.data.momo_reference),
    status: asString(result.data.status),
    initiative_title: asString(initiative?.title) ?? "Rayon Sports Initiative",
    partner_id: asString(initiative?.partner_id),
  };
}

function formatRwf(amount: number): string {
  return `RWF ${amount}`;
}

async function maybeAwardRayonMembershipPoints(
  adminClient: AdminClient,
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

async function maybeActivateReferralInvite(
  adminClient: AdminClient,
  inviteId: string | null,
  inviteeId: string,
  qualifyingEventType: string,
  qualifyingEventId: string,
  inviterPoints: number,
  inviteePoints: number,
): Promise<boolean> {
  if (!inviteId || !inviteeId) {
    return false;
  }

  const result = await adminClient.rpc("activate_referral_invite_for_user", {
    p_referral_invite_id: inviteId,
    p_invitee_id: inviteeId,
    p_qualifying_event_type: qualifyingEventType,
    p_qualifying_event_id: qualifyingEventId,
    p_inviter_points: inviterPoints,
    p_invitee_points: inviteePoints,
  });

  if (result.error) {
    console.error("Failed to activate referral invite", result.error);
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

async function confirmPendingTransaction(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
  context: RayonPaymentConfirmationContext,
) {
  const confirmationTimestamp = pendingTransaction.confirmed_at ??
    context.timestamp;

  const result = await adminClient
    .from("pending_transactions")
    .update({
      status: "confirmed",
      confirmed_at: confirmationTimestamp,
      updated_at: context.timestamp,
      raw_payload: {
        source: context.source,
        provider: normalizeProviderId(context.provider),
        amount_rwf: context.amount,
        transaction_id: context.transactionId ?? null,
        payee_number_or_code: context.payeeNumberOrCode ?? null,
        merchant_code: context.merchantCode ?? null,
        candidate_score: context.candidateScore ?? null,
        confidence: context.confidence ?? null,
        raw_sms_id: context.rawSmsId ?? null,
        parsed_sms_id: context.parsedSmsId ?? null,
        sender: context.sender ?? null,
        country: context.country ?? null,
        ...context.extraPayload ?? {},
      },
    })
    .eq("id", pendingTransaction.id);

  if (result.error) {
    throw result.error;
  }
}

function buildRayonTicketConfirmationMessage(
  tickets: RsTicketRecord[],
): string {
  const ticket = tickets[0];
  if (!ticket) {
    return "✅ Gikundiro ticket confirmed";
  }

  const totalAmount = tickets.reduce(
    (sum, entry) => sum + entry.amount_paid,
    0,
  );
  const lines = ["✅ Gikundiro ticket confirmed", ticket.match_title];
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
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
  context: RayonPaymentConfirmationContext,
  tickets: RsTicketRecord[],
): Promise<RayonPaymentConfirmationResult> {
  const ticket = tickets[0];
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
        updated_at: context.timestamp,
      })
      .eq("id", entry.ticket.id);

    if (updateResult.error) {
      throw updateResult.error;
    }
  }

  await confirmPendingTransaction(adminClient, pendingTransaction, context);

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
  const referralActivated = await maybeActivateReferralInvite(
    adminClient,
    ticket.referral_invite_id,
    ticket.user_id,
    "rayon_ticket_bought",
    ticket.id,
    140,
    60,
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
    notes: "Rayon Sports ticket payment confirmed.",
    metadata: {
      auto_match: true,
      candidate_score: context.candidateScore ?? null,
      provider: normalizeProviderId(context.provider),
      partner_id: ticket.partner_id,
      ticket_count: tickets.length,
      ticket_ids: tickets.map((entry) => entry.id),
      points_awarded: pointsAwarded ? pointsToAward : 0,
      referral_activated: referralActivated,
      whatsapp_sent: whatsappSent,
      source: context.source,
    },
  };
}

async function confirmRayonShopOrder(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
  context: RayonPaymentConfirmationContext,
  order: RsShopOrderRecord,
): Promise<RayonPaymentConfirmationResult> {
  const confirmation = planRayonShopOrderConfirmation(
    order.status,
    order.total,
  );

  const updateResult = await adminClient
    .from("rs_shop_orders")
    .update({
      status: confirmation.nextStatus,
      updated_at: context.timestamp,
    })
    .eq("id", order.id);

  if (updateResult.error) {
    throw updateResult.error;
  }

  await confirmPendingTransaction(adminClient, pendingTransaction, context);

  const partnerId = await resolveRayonPartnerId(adminClient);
  const pointsAwarded = await maybeAwardRayonMembershipPoints(
    adminClient,
    order.user_id,
    partnerId,
    confirmation.pointsToAward,
  );
  const referralActivated = await maybeActivateReferralInvite(
    adminClient,
    order.referral_invite_id,
    order.user_id,
    "rayon_shop_order_confirmed",
    order.id,
    120,
    50,
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
    notes: "Rayon Sports shop order payment confirmed.",
    metadata: {
      auto_match: true,
      candidate_score: context.candidateScore ?? null,
      provider: normalizeProviderId(context.provider),
      partner_id: partnerId,
      points_awarded: pointsAwarded ? confirmation.pointsToAward : 0,
      referral_activated: referralActivated,
      whatsapp_sent: whatsappSent,
      source: context.source,
      applied_status: confirmation.nextStatus,
    },
  };
}

async function confirmRayonInitiativeContribution(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
  context: RayonPaymentConfirmationContext,
  contribution: RsInitiativeContributionRecord,
): Promise<RayonPaymentConfirmationResult> {
  const confirmation = planRayonInitiativeConfirmation(
    contribution.status,
    contribution.amount,
  );

  const updateResult = await adminClient
    .from("rs_initiative_contributions")
    .update({
      status: confirmation.nextStatus,
      updated_at: context.timestamp,
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
        updated_at: context.timestamp,
      })
      .eq("id", contribution.initiative_id);

    if (correctedResult.error) {
      throw correctedResult.error;
    }
  }

  await confirmPendingTransaction(adminClient, pendingTransaction, context);

  const pointsAwarded = await maybeAwardRayonMembershipPoints(
    adminClient,
    contribution.user_id,
    contribution.partner_id,
    confirmation.pointsToAward,
  );
  const referralActivated = await maybeActivateReferralInvite(
    adminClient,
    contribution.referral_invite_id,
    contribution.user_id,
    "rayon_support_confirmed",
    contribution.id,
    130,
    50,
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
    notes: "Rayon Sports initiative contribution confirmed.",
    metadata: {
      auto_match: true,
      candidate_score: context.candidateScore ?? null,
      provider: normalizeProviderId(context.provider),
      partner_id: contribution.partner_id,
      points_awarded: pointsAwarded ? confirmation.pointsToAward : 0,
      referral_activated: referralActivated,
      whatsapp_sent: whatsappSent,
      source: context.source,
    },
  };
}

export async function confirmRayonPendingTransaction(
  adminClient: AdminClient,
  pendingTransaction: PendingTransactionRecord,
  context: RayonPaymentConfirmationContext,
): Promise<RayonPaymentConfirmationResult> {
  if (looksLikeRayonTicketReference(pendingTransaction.reference)) {
    const tickets = await resolveRayonTickets(adminClient, pendingTransaction);
    if (tickets.length === 0) {
      return buildManualReviewResult(
        "No Rayon Sports ticket rows matched the payment reference.",
        {
          reason: "missing_rayon_ticket_rows",
          matched_reference: pendingTransaction.reference,
        },
      );
    }

    return await confirmRayonTickets(
      adminClient,
      pendingTransaction,
      context,
      tickets,
    );
  }

  if (looksLikeRayonSupportReference(pendingTransaction.reference)) {
    const contribution = await resolveRayonInitiativeContribution(
      adminClient,
      pendingTransaction,
    );
    if (!contribution) {
      return buildManualReviewResult(
        "No Rayon Sports initiative contribution matched the payment reference.",
        {
          reason: "missing_rayon_support_row",
          matched_reference: pendingTransaction.reference,
        },
      );
    }

    return await confirmRayonInitiativeContribution(
      adminClient,
      pendingTransaction,
      context,
      contribution,
    );
  }

  if (looksLikeRayonShopReference(pendingTransaction.reference)) {
    const order = await resolveRayonShopOrder(adminClient, pendingTransaction);
    if (!order) {
      return buildManualReviewResult(
        "No Rayon Sports shop order matched the payment reference.",
        {
          reason: "missing_rayon_shop_order",
          matched_reference: pendingTransaction.reference,
        },
      );
    }

    return await confirmRayonShopOrder(
      adminClient,
      pendingTransaction,
      context,
      order,
    );
  }

  return buildManualReviewResult(
    "Pending transaction reference is not a supported Rayon Sports payment.",
    {
      reason: "unsupported_rayon_reference",
      matched_reference: pendingTransaction.reference,
    },
  );
}
