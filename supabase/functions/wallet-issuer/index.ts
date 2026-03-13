import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { hmacSha256Hex } from "../_shared/security.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

type WalletIssuerRequest = {
  action?: "health" | "rayon_ticket";
  ticketId?: string;
};

type AuthenticatedCaller = {
  userId: string;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
};

type WalletConfig = {
  issuerId: string;
  issuerName: string;
  appBaseUrl: string;
  origins: string[];
  serviceAccount: ServiceAccount;
};

type WalletReadiness = {
  configured: boolean;
  missingSecrets: string[];
  issues: string[];
  issuerId: string | null;
  origins: string[];
};

type RayonTicketRecord = {
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

type CachedToken = {
  accessToken: string;
  expiresAtMs: number;
};

const encoder = new TextEncoder();
let cachedWalletToken: CachedToken | null = null;

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required.", 401);
  }

  let ticketIdForTelemetry: string | null = null;
  let callerUserIdForTelemetry: string | null = null;

  try {
    const caller = await requireCaller(authorization);
    const body = await request.json() as WalletIssuerRequest;
    const startedAt = Date.now();
    ticketIdForTelemetry = body.ticketId?.trim() ?? null;
    callerUserIdForTelemetry = caller.userId;

    switch (body.action) {
      case "health": {
        return jsonResponse({
          success: true,
          ...inspectWalletConfig(),
        });
      }
      case "rayon_ticket": {
        const response = await issueRayonTicketWalletPass({
          caller,
          ticketId: body.ticketId,
        });

        console.info(
          JSON.stringify({
            service: "wallet-issuer",
            action: "rayon_ticket",
            user_id: caller.userId,
            ticket_id: body.ticketId ?? null,
            latency_ms: Date.now() - startedAt,
          }),
        );

        await recordOperationalHealthEvent(createAdminClient(), {
          service: "wallet_sync",
          component: "wallet-issuer",
          status: "ok",
          severity: "info",
          message: "Google Wallet pass prepared successfully.",
          functionName: "wallet-issuer",
          userId: caller.userId,
          subjectType: "rs_ticket",
          subjectId: body.ticketId ?? null,
          metadata: {
            action: "rayon_ticket",
            wallet_pass_id: response.walletPassId,
            class_id: response.classId,
            object_id: response.objectId,
            latency_ms: Date.now() - startedAt,
          },
        });

        return jsonResponse({ success: true, ...response });
      }
      default:
        return errorResponse("Unsupported wallet action.", 400, {
          action: body.action ?? null,
        });
    }
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body.", 400);
    }

    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status, error.details);
    }

    console.error("wallet-issuer failed", error);

    const adminClient = createAdminClient();
    await recordOperationalHealthEvent(adminClient, {
      service: "wallet_sync",
      component: "wallet-issuer",
      status: "error",
      severity: "critical",
      issueCode: "wallet_sync_failed",
      message: error instanceof Error
        ? error.message
        : "Wallet issuance failed.",
      functionName: "wallet-issuer",
      userId: callerUserIdForTelemetry,
      subjectType: "rs_ticket",
      subjectId: ticketIdForTelemetry,
    });
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "wallet-issuer",
      error,
      userId: callerUserIdForTelemetry,
      subjectType: "rs_ticket",
      subjectId: ticketIdForTelemetry,
    });

    return errorResponse(
      error instanceof Error ? error.message : "Wallet issuance failed.",
      500,
    );
  }
});

async function issueRayonTicketWalletPass(options: {
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
    userId: ticket.userId,
    partnerId: ticket.partnerId,
    entityId: ticket.id,
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
    } as Record<string, unknown>,
  });

  return {
    saveUrl,
    walletPassId,
    classId,
    objectId,
  };
}

async function requireCaller(
  authorization: string,
): Promise<AuthenticatedCaller> {
  const client = createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await client.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required.");
  }

  return { userId: user.id };
}

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

async function ensureEventTicketClass(
  config: WalletConfig,
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

  await walletApiRequest(
    config,
    "/eventTicketClass",
    {
      method: "POST",
      body: JSON.stringify({
        id: classId,
        issuerName: config.issuerName,
        reviewStatus: "UNDER_REVIEW",
        eventId: ticket.matchId,
        eventName: localizedString(ticket.matchTitle, "en"),
      }),
    },
  );
}

async function ensureEventTicketObject(
  config: WalletConfig,
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

  await walletApiRequest(
    config,
    "/eventTicketObject",
    {
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
              uri: `${
                config.appBaseUrl.replace(/\/$/, "")
              }/match/${ticket.matchId}`,
            },
          ],
        },
      }),
    },
  );
}

async function persistWalletPass(
  admin: ReturnType<typeof createAdminClient>,
  options: {
    userId: string;
    partnerId: string | null;
    entityId: string;
    classId: string;
    objectId: string;
    saveUrl: string;
    payload: Record<string, unknown>;
  },
) {
  try {
    const upserted = await admin
      .from("wallet_passes")
      .upsert(
        {
          user_id: options.userId,
          partner_id: options.partnerId,
          provider: "google_wallet",
          pass_type: "event_ticket",
          entity_type: "rs_ticket",
          entity_id: options.entityId,
          google_class_id: options.classId,
          google_object_id: options.objectId,
          status: "ready",
          state: "ACTIVE",
          save_url: options.saveUrl,
          payload: options.payload,
          last_error: null,
          last_issued_at: new Date().toISOString(),
        },
        { onConflict: "pass_type,entity_type,entity_id" },
      )
      .select("id")
      .single();

    const walletPassId = `${upserted.data?.id ?? ""}`.trim();
    if (!walletPassId) {
      return null;
    }

    await admin.from("wallet_pass_events").insert({
      wallet_pass_id: walletPassId,
      user_id: options.userId,
      event_type: "save_url_generated",
      status: "success",
      details: {
        classId: options.classId,
        objectId: options.objectId,
      },
    });

    return walletPassId;
  } catch (error) {
    console.error("wallet-issuer persistence failed", error);
    return null;
  }
}

function loadWalletConfig(): WalletConfig {
  const issuerId = requireEnv("GOOGLE_WALLET_ISSUER_ID");
  const issuerName = normalizeNullableString(
    Deno.env.get("GOOGLE_WALLET_ISSUER_NAME"),
  ) ?? "Cool";
  const appBaseUrl = normalizeNullableString(
    Deno.env.get("COOL_PUBLIC_APP_BASE_URL"),
  ) ?? "https://cool.app";
  const serviceAccount = parseServiceAccount(
    requireEnv("GOOGLE_WALLET_SERVICE_ACCOUNT_JSON"),
  );

  return {
    issuerId,
    issuerName,
    appBaseUrl,
    origins: parseOrigins(
      Deno.env.get("GOOGLE_WALLET_ALLOWED_ORIGINS"),
      appBaseUrl,
    ),
    serviceAccount,
  };
}

function inspectWalletConfig(): WalletReadiness {
  const missingSecrets: string[] = [];
  const issues: string[] = [];

  const issuerId = normalizeNullableString(
    Deno.env.get("GOOGLE_WALLET_ISSUER_ID"),
  );
  if (!issuerId) {
    missingSecrets.push("GOOGLE_WALLET_ISSUER_ID");
  }

  const serviceAccountJson = normalizeNullableString(
    Deno.env.get("GOOGLE_WALLET_SERVICE_ACCOUNT_JSON"),
  );
  if (!serviceAccountJson) {
    missingSecrets.push("GOOGLE_WALLET_SERVICE_ACCOUNT_JSON");
  } else {
    try {
      parseServiceAccount(serviceAccountJson);
    } catch (error) {
      issues.push(error instanceof Error ? error.message : `${error}`);
    }
  }

  if (!normalizeNullableString(Deno.env.get("TICKET_QR_HMAC_SECRET"))) {
    missingSecrets.push("TICKET_QR_HMAC_SECRET");
  }

  const appBaseUrl = normalizeNullableString(
    Deno.env.get("COOL_PUBLIC_APP_BASE_URL"),
  ) ?? "https://cool.app";

  return {
    configured: missingSecrets.length == 0 && issues.length == 0,
    missingSecrets,
    issues,
    issuerId,
    origins: parseOrigins(
      Deno.env.get("GOOGLE_WALLET_ALLOWED_ORIGINS"),
      appBaseUrl,
    ),
  };
}

function parseServiceAccount(raw: string): ServiceAccount {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new HttpError(
      500,
      "GOOGLE_WALLET_SERVICE_ACCOUNT_JSON is not valid JSON.",
      { details: error instanceof Error ? error.message : `${error}` },
    );
  }

  const map = asMap(parsed);
  const clientEmail = normalizeNullableString(map.client_email);
  const privateKey = normalizeNullableString(map.private_key)?.replaceAll(
    "\\n",
    "\n",
  );

  if (!clientEmail || !privateKey) {
    throw new HttpError(
      500,
      "Google Wallet service account credentials are incomplete.",
    );
  }

  return {
    client_email: clientEmail,
    private_key: privateKey,
  };
}

function parseOrigins(raw: string | undefined, appBaseUrl: string): string[] {
  const values = (raw ?? "")
    .split(",")
    .map((value) => normalizeOrigin(value))
    .filter((value) => value.length > 0);

  if (values.length > 0) {
    return values;
  }

  const normalized = normalizeOrigin(appBaseUrl);
  if (normalized.length > 0) {
    return [normalized];
  }

  return ["cool.app"];
}

async function createSaveUrl(config: WalletConfig, objectId: string) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const token = await signJwt(
    config.serviceAccount.private_key,
    {
      iss: config.serviceAccount.client_email,
      aud: "google",
      typ: "savetowallet",
      iat: issuedAt,
      origins: config.origins,
      payload: {
        eventTicketObjects: [{ id: objectId }],
      },
    },
  );

  return `https://pay.google.com/gp/v/save/${token}`;
}

async function walletApiGet(
  config: WalletConfig,
  path: string,
): Promise<Record<string, unknown> | null> {
  const accessToken = await getWalletAccessToken(config);
  const response = await fetch(
    `https://walletobjects.googleapis.com/walletobjects/v1${path}`,
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
  );

  if (response.status == 404) {
    return null;
  }

  return await parseWalletApiResponse(response);
}

async function walletApiRequest(
  config: WalletConfig,
  path: string,
  init: RequestInit,
) {
  const accessToken = await getWalletAccessToken(config);
  const response = await fetch(
    `https://walletobjects.googleapis.com/walletobjects/v1${path}`,
    {
      ...init,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    },
  );

  return await parseWalletApiResponse(response);
}

async function parseWalletApiResponse(response: Response) {
  const raw = await response.text();
  const payload = raw.length > 0 ? safeJsonParse(raw) : null;

  if (!response.ok) {
    throw new HttpError(502, "Google Wallet API request failed.", {
      status: response.status,
      response: payload ?? raw,
    });
  }

  if (payload && typeof payload == "object") {
    return asMap(payload);
  }

  return {} as Record<string, unknown>;
}

async function getWalletAccessToken(config: WalletConfig): Promise<string> {
  const now = Date.now();
  if (cachedWalletToken && cachedWalletToken.expiresAtMs - 60_000 > now) {
    return cachedWalletToken.accessToken;
  }

  const issuedAt = Math.floor(now / 1000);
  const assertion = await signJwt(
    config.serviceAccount.private_key,
    {
      iss: config.serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/wallet_object.issuer",
      aud: "https://oauth2.googleapis.com/token",
      iat: issuedAt,
      exp: issuedAt + 3600,
    },
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const payload = asMap(await parseWalletApiResponse(response));
  const accessToken = normalizeNullableString(payload.access_token);
  const expiresIn = Number(payload.expires_in ?? 3600);

  if (!accessToken) {
    throw new HttpError(502, "Google OAuth token response was empty.");
  }

  cachedWalletToken = {
    accessToken,
    expiresAtMs: now + (Number.isFinite(expiresIn) ? expiresIn : 3600) * 1000,
  };

  return accessToken;
}

async function signJwt(
  privateKeyPem: string,
  payload: Record<string, unknown>,
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const encodedHeader = base64UrlEncodeJson(header);
  const encodedPayload = base64UrlEncodeJson(payload);
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const key = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncodeBytes(new Uint8Array(signature))}`;
}

async function importPrivateKey(privateKeyPem: string): Promise<CryptoKey> {
  const normalized = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s+/g, "");

  const binary = Uint8Array.from(
    atob(normalized),
    (char) => char.charCodeAt(0),
  );
  return await crypto.subtle.importKey(
    "pkcs8",
    binary.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncodeBytes(encoder.encode(JSON.stringify(value)));
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function localizedString(value: string, languageCode: string) {
  return {
    defaultValue: {
      language: toWalletLanguage(languageCode),
      value,
    },
  };
}

function toWalletLanguage(languageCode: string): string {
  return "en-US";
}

async function buildTicketQrData(ticket: RayonTicketRecord): Promise<string> {
  const existing = normalizeNullableString(ticket.qrCode);
  if (existing && existing.startsWith("COOL-TKT:")) {
    return existing;
  }

  const secret = requireEnv("TICKET_QR_HMAC_SECRET");
  const parsedTimestamp = Date.parse(ticket.purchasedAt);
  const timestampMs = Number.isFinite(parsedTimestamp)
    ? `${parsedTimestamp}`
    : `${Date.now()}`;
  const payload = `${ticket.id}:${ticket.matchId}:${timestampMs}`;
  const digest = await hmacSha256Hex(secret, payload);
  return `COOL-TKT:${payload}:${digest.slice(0, 12)}`;
}

function buildKickoffLabel(matchDate: string, kickoffTime: string): string {
  const date = normalizeNullableString(matchDate) ?? "Date TBC";
  const time = normalizeNullableString(kickoffTime) ?? "Time TBC";
  return `${date} ${time}`;
}

function buildWalletResourceId(issuerId: string, suffix: string): string {
  const normalizedSuffix = suffix.replaceAll(/[^A-Za-z0-9._-]/g, "_");
  return `${issuerId}.${normalizedSuffix}`;
}

function unwrapSingleRecord(
  value: unknown,
): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    const first = value.find((item) => item && typeof item == "object");
    return first ? asMap(first) : null;
  }
  if (value && typeof value == "object") {
    return asMap(value);
  }
  return null;
}

function normalizeNullableString(value: unknown): string | null {
  const normalized = `${value ?? ""}`.trim();
  return normalized.length > 0 ? normalized : null;
}

function normalizeOrigin(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length == 0) {
    return "";
  }

  try {
    return new URL(trimmed).host;
  } catch (_) {
    return trimmed.replace(/^https?:\/\//i, "").replace(/\/+$/, "");
  }
}

function requireEnv(name: string): string {
  const value = normalizeNullableString(Deno.env.get(name));
  if (!value) {
    throw new HttpError(500, `Missing environment variable: ${name}`);
  }
  return value;
}

function asMap(value: unknown): Record<string, unknown> {
  if (value && typeof value == "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function safeJsonParse(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch (_) {
    return value;
  }
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "HttpError";
  }
}
