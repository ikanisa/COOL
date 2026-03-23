/**
 * wallet_api.ts — Google Wallet API client, JWT signing, crypto utilities,
 * and wallet configuration loading.
 *
 * Extracted from index.ts to separate API plumbing from domain logic.
 */

import { hmacSha256Hex } from "../_shared/security.ts";

// ── Types ──────────────────────────────────────────────────────
export type ServiceAccount = {
  client_email: string;
  private_key: string;
};

export type WalletConfig = {
  issuerId: string;
  issuerName: string;
  appBaseUrl: string;
  origins: string[];
  serviceAccount: ServiceAccount;
};

export type WalletReadiness = {
  configured: boolean;
  missingSecrets: string[];
  issues: string[];
  issuerId: string | null;
  origins: string[];
};

export type AuthenticatedCaller = {
  userId: string;
};

export type CachedToken = {
  accessToken: string;
  expiresAtMs: number;
};

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

// ── Shared state ───────────────────────────────────────────────
const encoder = new TextEncoder();
let cachedWalletToken: CachedToken | null = null;

// ── Config loading ─────────────────────────────────────────────
export function loadWalletConfig(): WalletConfig {
  const issuerId = requireEnv("GOOGLE_WALLET_ISSUER_ID");
  const issuerName =
    normalizeNullableString(Deno.env.get("GOOGLE_WALLET_ISSUER_NAME")) ??
    "Cool";
  const appBaseUrl =
    normalizeNullableString(Deno.env.get("COOL_PUBLIC_APP_BASE_URL")) ??
    "https://cool.app";
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

export function inspectWalletConfig(): WalletReadiness {
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

  const appBaseUrl =
    normalizeNullableString(Deno.env.get("COOL_PUBLIC_APP_BASE_URL")) ??
    "https://cool.app";

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

// ── Wallet API calls ───────────────────────────────────────────
export async function walletApiGet(
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

export async function walletApiRequest(
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
  const assertion = await signJwt(config.serviceAccount.private_key, {
    iss: config.serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/wallet_object.issuer",
    aud: "https://oauth2.googleapis.com/token",
    iat: issuedAt,
    exp: issuedAt + 3600,
  });

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

  const resPayload = asMap(await parseWalletApiResponse(response));
  const accessToken = normalizeNullableString(resPayload.access_token);
  const expiresIn = Number(resPayload.expires_in ?? 3600);

  if (!accessToken) {
    throw new HttpError(502, "Google OAuth token response was empty.");
  }

  cachedWalletToken = {
    accessToken,
    expiresAtMs: now + (Number.isFinite(expiresIn) ? expiresIn : 3600) * 1000,
  };

  return accessToken;
}

// ── Save URL generation ────────────────────────────────────────
export async function createSaveUrl(
  config: WalletConfig,
  objectId: string,
) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const token = await signJwt(config.serviceAccount.private_key, {
    iss: config.serviceAccount.client_email,
    aud: "google",
    typ: "savetowallet",
    iat: issuedAt,
    origins: config.origins,
    payload: {
      eventTicketObjects: [{ id: objectId }],
    },
  });

  return `https://pay.google.com/gp/v/save/${token}`;
}

// ── Persistence ────────────────────────────────────────────────
export async function persistWalletPass(
  admin: ReturnType<typeof import("../_shared/supabase.ts").createAdminClient>,
  options: {
    userId: string;
    partnerId: string | null;
    entityType: "rs_ticket" | "rs_membership";
    passType: "event_ticket" | "generic_membership";
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
          pass_type: options.passType,
          entity_type: options.entityType,
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

// ── JWT / crypto ───────────────────────────────────────────────
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

// ── Shared utilities ───────────────────────────────────────────
export function localizedString(value: string, languageCode: string) {
  return {
    defaultValue: {
      language: toWalletLanguage(languageCode),
      value,
    },
  };
}

export function toWalletLanguage(_languageCode: string): string {
  return "en-US";
}

export async function buildTicketQrData(ticket: {
  id: string;
  matchId: string;
  qrCode: string | null;
  purchasedAt: string;
}): Promise<string> {
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

export function buildKickoffLabel(
  matchDate: string,
  kickoffTime: string,
): string {
  const date = normalizeNullableString(matchDate) ?? "Date TBC";
  const time = normalizeNullableString(kickoffTime) ?? "Time TBC";
  return `${date} ${time}`;
}

export function buildWalletResourceId(
  issuerId: string,
  suffix: string,
): string {
  const normalizedSuffix = suffix.replaceAll(/[^A-Za-z0-9._-]/g, "_");
  return `${issuerId}.${normalizedSuffix}`;
}

export function unwrapSingleRecord(
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

export function normalizeNullableString(value: unknown): string | null {
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

export function requireEnv(name: string): string {
  const value = normalizeNullableString(Deno.env.get(name));
  if (!value) {
    throw new HttpError(500, `Missing environment variable: ${name}`);
  }
  return value;
}

export function asMap(value: unknown): Record<string, unknown> {
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
