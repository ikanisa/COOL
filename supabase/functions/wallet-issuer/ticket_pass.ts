/**
 * ticket_pass.ts — Rayon Sports ticket wallet pass issuance.
 *
 * Handles loading ticket data, ensuring Wallet class/object exist,
 * and returning a save URL for the user's Google Wallet.
 */

import { createAdminClient } from "../_shared/supabase.ts";
import {
  type AuthenticatedCaller,
  buildKickoffLabel,
  buildTicketQrData,
  buildWalletResourceId,
  createSaveUrl,
  HttpError,
  loadWalletConfig,
  localizedString,
  normalizeNullableString,
  persistWalletPass,
  unwrapSingleRecord,
  walletApiGet,
  walletApiRequest,
} from "./wallet_api.ts";

// ── Types ──────────────────────────────────────────────────────
export type RayonTicketRecord = {
  id: string;
  userId: string;
  matchId: string;
  seatType: string;
  amountPaid: number;
  qrCode: string | null;
  momoReference: string | null;
  status: string;
  purchasedAt: string;
  holderName: string;
  languageCode: string;
  matchTitle: string;
  competition: string;
  venue: string;
  matchDate: string;
  kickoffTime: string;
  partnerId: string | null;
};

// ── Main entry point ───────────────────────────────────────────
export async function issueRayonTicketWalletPass(options: {
  caller: AuthenticatedCaller;
  ticketId?: string;
}) {
  const ticketId = options.ticketId?.trim();
  if (!ticketId) {
    throw new HttpError(400, "ticketId is required.");
  }

  const admin = createAdminClient();
  const config = loadWalletConfig();
  const ticket = await loadRayonTicket(admin, ticketId, options.caller.userId);

  if (ticket.status != "valid") {
    throw new HttpError(
      409,
      "Only confirmed tickets can be saved to Google Wallet.",
      { ticketId: ticket.id, status: ticket.status },
    );
  }

  const classId = buildWalletResourceId(
    config.issuerId,
    `rs_match_${ticket.matchId}`,
  );
  const objectId = buildWalletResourceId(
    config.issuerId,
    `rs_ticket_${ticket.id}`,
  );

  await ensureEventTicketClass(config, classId, ticket);
  await ensureEventTicketObject(config, objectId, classId, ticket);

  const saveUrl = await createSaveUrl(config, objectId);
  const walletPassId = await persistWalletPass(admin, {
    userId: options.caller.userId,
    partnerId: ticket.partnerId,
    entityType: "rs_ticket",
    entityId: ticket.id,
    passType: "event_ticket",
    classId,
    objectId,
    saveUrl,
    payload: {
      ticketId: ticket.id,
      matchId: ticket.matchId,
      matchTitle: ticket.matchTitle,
      seatType: ticket.seatType,
      competition: ticket.competition,
      venue: ticket.venue,
      kickoff: buildKickoffLabel(ticket.matchDate, ticket.kickoffTime),
      holderName: ticket.holderName,
      status: ticket.status,
      amountPaid: ticket.amountPaid,
      purchasedAt: ticket.purchasedAt,
      momoReference: ticket.momoReference,
    } as Record<string, unknown>,
  });

  return {
    saveUrl,
    walletPassId,
    classId,
    objectId,
  };
}

// ── Data loading ───────────────────────────────────────────────
async function loadRayonTicket(
  admin: ReturnType<typeof createAdminClient>,
  ticketId: string,
  userId: string,
): Promise<RayonTicketRecord> {
  const { data, error } = await admin
    .from("rs_tickets")
    .select(
      `
        id,
        user_id,
        match_id,
        seat_type,
        amount_paid,
        qr_code,
        momo_reference,
        status,
        purchased_at,
        rs_matches (
          id,
          partner_id,
          home_team,
          away_team,
          competition,
          venue,
          match_date,
          kickoff_time
        ),
        users (
          full_name
        )
      `,
    )
    .eq("id", ticketId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Failed to load ticket.", {
      ticketId,
      details: error.message,
    });
  }

  if (!data) {
    throw new HttpError(404, "Ticket not found.");
  }

  const match = unwrapSingleRecord(data.rs_matches);
  const user = unwrapSingleRecord(data.users);
  if (!match) {
    throw new HttpError(500, "Ticket match data is missing.", { ticketId });
  }

  const homeTeam = `${match.home_team ?? "Rayon Sports FC"}`.trim();
  const awayTeam = `${match.away_team ?? "Opponent"}`.trim();

  return {
    id: `${data.id ?? ""}`.trim(),
    userId: `${data.user_id ?? ""}`.trim(),
    matchId: `${data.match_id ?? ""}`.trim(),
    seatType: `${data.seat_type ?? "General"}`.trim(),
    amountPaid: Number(data.amount_paid ?? 0),
    qrCode: normalizeNullableString(data.qr_code),
    momoReference: normalizeNullableString(data.momo_reference),
    status: `${data.status ?? "pending"}`.trim().toLowerCase(),
    purchasedAt: `${data.purchased_at ?? ""}`.trim(),
    holderName: normalizeNullableString(user?.full_name) ?? "Cool Fan",
    languageCode: "en",
    matchTitle: `${homeTeam} vs ${awayTeam}`,
    competition: `${match.competition ?? "Football Match"}`.trim(),
    venue: `${match.venue ?? "Venue TBC"}`.trim(),
    matchDate: `${match.match_date ?? ""}`.trim(),
    kickoffTime: `${match.kickoff_time ?? ""}`.trim(),
    partnerId: normalizeNullableString(match.partner_id),
  };
}

// ── Wallet class/object management ─────────────────────────────
async function ensureEventTicketClass(
  config: ReturnType<typeof loadWalletConfig>,
  classId: string,
  ticket: RayonTicketRecord,
) {
  const existing = await walletApiGet(
    config,
    `/eventTicketClass/${encodeURIComponent(classId)}`,
  );
  if (existing) {
    return;
  }

  await walletApiRequest(config, "/eventTicketClass", {
    method: "POST",
    body: JSON.stringify({
      id: classId,
      issuerName: config.issuerName,
      reviewStatus: "UNDER_REVIEW",
      eventId: ticket.matchId,
      eventName: localizedString(ticket.matchTitle, "en"),
    }),
  });
}

async function ensureEventTicketObject(
  config: ReturnType<typeof loadWalletConfig>,
  objectId: string,
  classId: string,
  ticket: RayonTicketRecord,
) {
  const existing = await walletApiGet(
    config,
    `/eventTicketObject/${encodeURIComponent(objectId)}`,
  );
  if (existing) {
    return;
  }

  await walletApiRequest(config, "/eventTicketObject", {
    method: "POST",
    body: JSON.stringify({
      id: objectId,
      classId,
      state: "ACTIVE",
      barcode: {
        type: "QR_CODE",
        value: await buildTicketQrData(ticket),
        alternateText: ticket.id,
      },
      ticketHolderName: ticket.holderName,
      ticketNumber: ticket.id,
      textModulesData: [
        {
          id: "match_summary",
          header: "Match",
          body: ticket.matchTitle,
        },
        {
          id: "kickoff",
          header: "Kickoff",
          body: buildKickoffLabel(ticket.matchDate, ticket.kickoffTime),
        },
        {
          id: "venue",
          header: "Venue",
          body: ticket.venue,
        },
        {
          id: "seat",
          header: "Seat",
          body: ticket.seatType,
        },
        {
          id: "competition",
          header: "Competition",
          body: ticket.competition,
        },
      ],
      linksModuleData: {
        uris: [
          {
            id: "open_match",
            description: "Open in Cool",
            uri: `${config.appBaseUrl.replace(/\/$/, "")}/match/${ticket.matchId}`,
          },
        ],
      },
    }),
  });
}
