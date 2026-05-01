/**
 * Shared Firebase Cloud Messaging (FCM) HTTP v1 sender for Edge Functions.
 *
 * Uses a Google service account to mint short-lived OAuth2 tokens and sends
 * push notifications via the FCM HTTP v1 API. No `firebase-admin` SDK needed.
 *
 * Requirements:
 *   FIREBASE_SERVICE_ACCOUNT_JSON — full service account JSON string
 *   FIREBASE_PROJECT_ID — Firebase project ID (or extracted from the SA JSON)
 */

import { createAdminClient } from "./supabase.ts";

// ── Types ────────────────────────────────────────────────────────────────

export interface FcmNotification {
  title: string;
  body: string;
  image?: string;
}

export interface FcmData {
  [key: string]: string;
}

export interface SendResult {
  success: boolean;
  sent_count: number;
  failed_count: number;
  cleaned_tokens: number;
  errors: string[];
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// ── OAuth2 Token via JWT Assertion ───────────────────────────────────────

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";
const GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer";

let _cachedToken: { token: string; expiresAt: number } | null = null;

function getServiceAccount(): ServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is not set.");
  }

  const sa = JSON.parse(raw) as ServiceAccount;
  if (!sa.client_email || !sa.private_key) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT_JSON is missing client_email or private_key.",
    );
  }

  return sa;
}

function getProjectId(sa: ServiceAccount): string {
  return Deno.env.get("FIREBASE_PROJECT_ID") ?? sa.project_id;
}

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64urlEncode(obj: Record<string, unknown>): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\\n/g, "")
    .replace(/\n/g, "")
    .trim();

  const binaryDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

export async function buildJwtAssertion(
  sa: ServiceAccount,
  scope: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64urlEncode({ alg: "RS256", typ: "JWT" });
  const payload = base64urlEncode({
    iss: sa.client_email,
    scope,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  });

  const signingInput = `${header}.${payload}`;
  const key = await importPrivateKey(sa.private_key);
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signingInput),
    ),
  );

  return `${signingInput}.${base64url(signature)}`;
}

export async function getAccessToken(): Promise<string> {
  // Return cached token if still valid (with 60s buffer).
  if (_cachedToken && Date.now() < _cachedToken.expiresAt - 60_000) {
    return _cachedToken.token;
  }

  const sa = getServiceAccount();
  const jwt = await buildJwtAssertion(sa, FCM_SCOPE);

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=${encodeURIComponent(GRANT_TYPE)}&assertion=${
      encodeURIComponent(jwt)
    }`,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `OAuth2 token exchange failed: ${response.status} ${errorText}`,
    );
  }

  const data = await response.json();
  _cachedToken = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  };

  return _cachedToken.token;
}

// ── FCM HTTP v1 Send ────────────────────────────────────────────────────

async function sendFcmMessage(
  projectId: string,
  accessToken: string,
  message: Record<string, unknown>,
): Promise<{ ok: boolean; error?: string; errorCode?: string }> {
  const url =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ message }),
  });

  if (response.ok) {
    return { ok: true };
  }

  const errorBody = await response.text();
  let errorCode = "UNKNOWN";
  try {
    const parsed = JSON.parse(errorBody);
    errorCode = parsed?.error?.details?.[0]?.errorCode ??
      parsed?.error?.status ??
      "UNKNOWN";
  } catch {
    // Use raw text.
  }

  return {
    ok: false,
    error: `${response.status}: ${errorCode}`,
    errorCode,
  };
}

// ── Public API ───────────────────────────────────────────────────────────

/**
 * Send a push notification to all devices of a specific user.
 *
 * Looks up tokens from `user_fcm_tokens`, sends to each, and auto-cleans
 * stale/unregistered tokens.
 */
export async function sendToUser(
  userId: string,
  notification: FcmNotification,
  data?: FcmData,
): Promise<SendResult> {
  const result: SendResult = {
    success: false,
    sent_count: 0,
    failed_count: 0,
    cleaned_tokens: 0,
    errors: [],
  };

  const sa = getServiceAccount();
  const projectId = getProjectId(sa);
  const accessToken = await getAccessToken();

  // Fetch all FCM tokens for the user.
  const supabase = createAdminClient();
  const { data: tokens, error: dbError } = await supabase
    .from("user_fcm_tokens")
    .select("id, token")
    .eq("user_id", userId);

  if (dbError) {
    result.errors.push(`DB error: ${dbError.message}`);
    return result;
  }

  if (!tokens || tokens.length === 0) {
    result.errors.push("No FCM tokens found for user.");
    return result;
  }

  const staleTokenIds: string[] = [];

  for (const row of tokens) {
    const message: Record<string, unknown> = {
      token: row.token,
      notification: {
        title: notification.title,
        body: notification.body,
        ...(notification.image ? { image: notification.image } : {}),
      },
      android: {
        priority: "high" as const,
        notification: {
          channel_id: "cool_default",
          default_sound: true,
          default_vibrate_timings: true,
        },
      },
      ...(data ? { data } : {}),
    };

    const sendResult = await sendFcmMessage(projectId, accessToken, message);

    if (sendResult.ok) {
      result.sent_count++;
    } else {
      result.failed_count++;

      // Clean up stale/unregistered tokens automatically.
      if (
        sendResult.errorCode === "UNREGISTERED" ||
        sendResult.errorCode === "NOT_FOUND"
      ) {
        staleTokenIds.push(row.id);
      } else {
        result.errors.push(sendResult.error ?? "Unknown send error");
      }
    }
  }

  // Remove stale tokens from DB.
  if (staleTokenIds.length > 0) {
    const { error: deleteError } = await supabase
      .from("user_fcm_tokens")
      .delete()
      .in("id", staleTokenIds);

    if (deleteError) {
      result.errors.push(`Stale token cleanup failed: ${deleteError.message}`);
    } else {
      result.cleaned_tokens = staleTokenIds.length;
    }
  }

  result.success = result.sent_count > 0;
  return result;
}

/**
 * Send a push notification to a topic (e.g. `market_RW`).
 */
export async function sendToTopic(
  topic: string,
  notification: FcmNotification,
  data?: FcmData,
): Promise<SendResult> {
  const result: SendResult = {
    success: false,
    sent_count: 0,
    failed_count: 0,
    cleaned_tokens: 0,
    errors: [],
  };

  const sa = getServiceAccount();
  const projectId = getProjectId(sa);
  const accessToken = await getAccessToken();

  const message: Record<string, unknown> = {
    topic,
    notification: {
      title: notification.title,
      body: notification.body,
      ...(notification.image ? { image: notification.image } : {}),
    },
    android: {
      priority: "high" as const,
      notification: {
        channel_id: "cool_default",
        default_sound: true,
        default_vibrate_timings: true,
      },
    },
    ...(data ? { data } : {}),
  };

  const sendResult = await sendFcmMessage(projectId, accessToken, message);

  if (sendResult.ok) {
    result.success = true;
    result.sent_count = 1;
  } else {
    result.failed_count = 1;
    result.errors.push(sendResult.error ?? "Unknown topic send error");
  }

  return result;
}
