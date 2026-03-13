import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  corsHeaders,
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

// ── HMAC validation ──────────────────────────────────────────────────────────

const QR_HMAC_SECRET = Deno.env.get("TICKET_QR_HMAC_SECRET")?.trim() ?? "";

const encoder = new TextEncoder();

async function hmacSha256Hex(
  secret: string,
  payload: string,
): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    encoder.encode(payload),
  );

  return [...new Uint8Array(signature)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ── QR Parsing ───────────────────────────────────────────────────────────────

type ParsedQr = {
  ticketId: string;
  matchId: string;
  timestampMs: string;
  hmac: string;
};

function parseQrCode(raw: string): ParsedQr | null {
  // Format: COOL-TKT:{ticketId}:{matchId}:{timestampMs}:{hmac12}
  if (!raw.startsWith("COOL-TKT:")) return null;

  const parts = raw.slice("COOL-TKT:".length).split(":");
  if (parts.length !== 4) return null;

  const [ticketId, matchId, timestampMs, hmac] = parts;
  if (!ticketId || !matchId || !timestampMs || !hmac) return null;

  return { ticketId, matchId, timestampMs, hmac };
}

async function verifyHmac(parsed: ParsedQr): Promise<boolean> {
  if (!QR_HMAC_SECRET) {
    throw new HttpError(500, "TICKET_QR_HMAC_SECRET is not configured.");
  }

  const payload = `${parsed.ticketId}:${parsed.matchId}:${parsed.timestampMs}`;
  const expectedFull = await hmacSha256Hex(QR_HMAC_SECRET, payload);
  // Flutter truncates HMAC to first 12 hex chars
  const expected = expectedFull.substring(0, 12);
  return expected === parsed.hmac;
}

// ── Auth ─────────────────────────────────────────────────────────────────────

type AuthenticatedCaller = {
  userId: string;
  isAppAdmin: boolean;
  appMetadata: Record<string, unknown>;
};

async function requireCaller(
  authorization: string,
): Promise<AuthenticatedCaller> {
  const userClient = createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await userClient.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required.");
  }

  const appMetadata = (user.app_metadata ?? {}) as Record<string, unknown>;

  return {
    userId: user.id,
    isAppAdmin: String(appMetadata["is_admin"]) === "true",
    appMetadata,
  };
}

function isPartnerAdmin(
  caller: AuthenticatedCaller,
  partnerId: string | null,
): boolean {
  // App-level admins can scan any partner's tickets
  if (caller.isAppAdmin) {
    return true;
  }

  if (!partnerId) {
    return false;
  }

  // Global partner admin flag
  if (String(caller.appMetadata["is_partner_admin"]) === "true") {
    return true;
  }

  // Per-partner admin list (can be array or object/map)
  const ids = caller.appMetadata["partner_admin_ids"];
  if (Array.isArray(ids)) {
    return ids.includes(partnerId);
  }
  if (ids && typeof ids === "object") {
    return partnerId in (ids as Record<string, unknown>);
  }

  return false;
}

// ── Scan logic ───────────────────────────────────────────────────────────────

type ScanRequest = {
  qrData: string;
  scannerId?: string;
};

type ScanResult = {
  status: "ok" | "already_used" | "invalid" | "cancelled" | "not_found";
  ticketId?: string;
  matchTitle?: string;
  seatType?: string;
  message: string;
  pointsAwarded?: number;
};

async function scanTicket(
  adminClient: ReturnType<typeof createAdminClient>,
  req: ScanRequest,
  caller: AuthenticatedCaller,
): Promise<ScanResult> {
  // 1. Parse QR data
  const parsed = parseQrCode(req.qrData);
  if (!parsed) {
    return { status: "invalid", message: "Invalid QR code format." };
  }

  // 2. Verify HMAC
  const validHmac = await verifyHmac(parsed);
  if (!validHmac) {
    return { status: "invalid", message: "QR code signature is invalid." };
  }

  // 3. Look up ticket
  const { data: ticket, error: fetchError } = await adminClient
    .from("rs_tickets")
    .select(
      "id, user_id, match_id, seat_type, amount_paid, status, momo_reference, rs_matches(home_team, away_team, competition, venue, match_date, kickoff_time, partner_id)",
    )
    .eq("id", parsed.ticketId)
    .single();

  if (fetchError || !ticket) {
    return { status: "not_found", message: "Ticket not found in the system." };
  }

  const rawMatch = ticket.rs_matches;
  const match: Record<string, unknown> | null = Array.isArray(rawMatch)
    ? (rawMatch[0] as Record<string, unknown> ?? null)
    : (rawMatch as Record<string, unknown> | null);
  const homeTeam = (match?.["home_team"] as string) ?? "Rayon Sports";
  const awayTeam = (match?.["away_team"] as string) ?? "Opponent";
  const matchTitle = `${homeTeam} vs ${awayTeam}`;
  const partnerId = (match?.["partner_id"] as string) ?? null;

  // 4. Authorization: caller must be a partner admin for this match
  if (!isPartnerAdmin(caller, partnerId)) {
    throw new HttpError(
      403,
      "Not authorized to scan tickets for this partner.",
    );
  }

  // 5. Check current status
  if (ticket.status === "used") {
    return {
      status: "already_used",
      ticketId: ticket.id,
      matchTitle,
      seatType: ticket.seat_type,
      message: "This ticket has already been scanned.",
    };
  }

  if (ticket.status === "cancelled") {
    return {
      status: "cancelled",
      ticketId: ticket.id,
      matchTitle,
      seatType: ticket.seat_type,
      message: "This ticket has been cancelled.",
    };
  }

  if (ticket.status === "pending") {
    return {
      status: "invalid",
      ticketId: ticket.id,
      matchTitle,
      seatType: ticket.seat_type,
      message: "This ticket is still pending payment confirmation.",
    };
  }

  // 6. ticket.status === 'valid' → mark as used
  const { error: updateError } = await adminClient
    .from("rs_tickets")
    .update({
      status: "used",
      updated_at: new Date().toISOString(),
    })
    .eq("id", ticket.id)
    .eq("status", "valid"); // optimistic lock

  if (updateError) {
    console.error("Failed to mark ticket as used:", updateError);
    return {
      status: "invalid",
      ticketId: ticket.id,
      matchTitle,
      message: "Failed to process ticket. Please try again.",
    };
  }

  // 7. Award attendance points (non-blocking)
  let pointsAwarded = 0;
  if (partnerId && ticket.user_id) {
    try {
      const { data: membership } = await adminClient.rpc(
        "rs_apply_membership_points",
        {
          p_user_id: ticket.user_id,
          p_partner_id: partnerId,
          p_points: 100,
        },
      );
      if (membership) {
        pointsAwarded = 100;
      }
    } catch (err) {
      console.error("Non-critical: failed to award attendance points:", err);
    }
  }

  return {
    status: "ok",
    ticketId: ticket.id,
    matchTitle,
    seatType: ticket.seat_type,
    pointsAwarded,
    message: `✅ Ticket valid — ${matchTitle} (${
      ticket.seat_type?.toUpperCase() ?? "GENERAL"
    })`,
  };
}

// ── HTTP handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return handleCors(req) ?? new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  // Require authentication
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required.", 401);
  }

  let callerUserIdForTelemetry: string | null = null;

  try {
    const caller = await requireCaller(authorization);
    callerUserIdForTelemetry = caller.userId;
    const body = (await req.json()) as ScanRequest;

    if (!body.qrData || typeof body.qrData !== "string") {
      return errorResponse("Missing or invalid 'qrData' field.", 400);
    }

    const adminClient = createAdminClient();
    const result = await scanTicket(adminClient, body, caller);

    const httpStatus = result.status === "ok"
      ? 200
      : result.status === "not_found"
      ? 404
      : result.status === "already_used"
      ? 409
      : result.status === "cancelled"
      ? 410
      : 422;

    return jsonResponse(result, httpStatus);
  } catch (err) {
    if (err instanceof HttpError) {
      return errorResponse(err.message, err.status);
    }
    console.error("rs-scan-ticket error:", err);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "rs-scan-ticket",
      error: err,
      userId: callerUserIdForTelemetry,
      subjectType: "ticket_scan",
    });
    return errorResponse(
      err instanceof Error ? err.message : "Internal server error",
      500,
    );
  }
});

class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}
