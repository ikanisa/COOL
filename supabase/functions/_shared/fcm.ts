import {
  genericPushBody,
  genericPushTitle,
  providerRetryFloor,
  requirePushRecipient,
} from "./notification_retry.ts";
import { boundedBody } from "./production_contract.ts";
export type FcmCredentials = {
  serviceAccountJson: string;
};

export type FcmMessage = {
  token: string;
  title: string;
  body: string;
  recipientId: string;
  eventId: string;
  eventType: string;
  deepLink?: string | null;
};

export type FcmResult = {
  ok: boolean;
  retryable: boolean;
  messageId: string | null;
  errorCode: string | null;
  status: number;
  latencyMs: number;
  retryAfterSeconds: number | null;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

const messagingScope = "https://www.googleapis.com/auth/firebase.messaging";
const defaultTokenUri = "https://oauth2.googleapis.com/token";

function base64Url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0)).buffer;
}

function serviceAccount(credentials: FcmCredentials): ServiceAccount {
  const account = JSON.parse(credentials.serviceAccountJson) as ServiceAccount;
  if (!account.project_id || !account.client_email || !account.private_key) {
    throw new Error("Invalid FCM service account configuration");
  }
  return account;
}

export async function createFcmAccessToken(
  credentials: FcmCredentials,
  fetcher: typeof fetch = fetch,
  issuedAt = Math.floor(Date.now() / 1000),
): Promise<string> {
  const account = serviceAccount(credentials);
  const tokenUri = defaultTokenUri;
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: messagingScope,
    aud: tokenUri,
    exp: issuedAt + 3600,
    iat: issuedAt,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const response = await fetcher(tokenUri, {
    method: "POST",
    signal: AbortSignal.timeout(8000),
    redirect: "error",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${base64Url(signature)}`,
    }),
  });
  const payload = await responseObject(response);
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new Error("FCM OAuth token exchange failed");
  }
  return payload.access_token;
}

async function responseObject(
  response: Response,
): Promise<Record<string, unknown>> {
  try {
    const value: unknown = JSON.parse(await boundedBody(response, 65536));
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? value as Record<string, unknown>
      : {};
  } catch {
    // Headers already establish acceptance/rejection. A failed optional body
    // read must not turn an accepted send into a duplicate provider request.
    await response.body?.cancel().catch(() => {});
    return {};
  }
}

function objectValue(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function providerCode(value: unknown): string | null {
  return typeof value === "string" && /^[A-Z_]{1,80}$/.test(value)
    ? value
    : null;
}

function channelForEventType(eventType: string): string {
  const value = eventType.toLowerCase();
  if (value.includes("contribution")) return "collect_contributions";
  if (value.includes("reminder")) return "collect_reminders";
  if (value.includes("security")) return "collect_security";
  return "collect_group_updates";
}

export async function sendFcmMessage(
  credentials: FcmCredentials,
  accessToken: string,
  message: FcmMessage,
  fetcher: typeof fetch = fetch,
): Promise<FcmResult> {
  requirePushRecipient(message.recipientId);
  const account = serviceAccount(credentials);
  const started = performance.now();
  const response = await fetcher(
    `https://fcm.googleapis.com/v1/projects/${
      encodeURIComponent(account.project_id)
    }/messages:send`,
    {
      method: "POST",
      signal: AbortSignal.timeout(10000),
      redirect: "error",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: genericPushTitle, body: genericPushBody },
          data: {
            collect_event_id: message.eventId,
            recipient_id: message.recipientId,
            collect_push_version: "2",
            type: message.eventType,
            ...(message.deepLink ? { deep_link: message.deepLink } : {}),
          },
          android: {
            priority: "high",
            notification: {
              channel_id: channelForEventType(message.eventType),
              icon: "ic_collect_notification",
              color: "#087A55",
              visibility: "PRIVATE",
            },
          },
        },
      }),
    },
  );
  const payload = await responseObject(response);
  const latencyMs = Math.max(0, Math.round(performance.now() - started));
  const error = objectValue(payload.error);
  const detailCode = Array.isArray(error.details)
    ? error.details.map((detail) => providerCode(objectValue(detail).errorCode))
      .find((code) => code !== null)
    : null;
  const messageId = typeof payload.name === "string" &&
      /^projects\/[A-Za-z0-9_-]+\/messages\/[A-Za-z0-9_%:.~+-]+$/.test(
        payload.name,
      )
    ? payload.name
    : null;
  const errorCode = response.ok
    ? (messageId ? null : "accepted_response_unavailable")
    : detailCode ?? providerCode(error.status) ?? `http_${response.status}`;
  return {
    ok: response.ok,
    retryable: response.status === 408 ||
      response.status === 429 ||
      response.status >= 500,
    messageId,
    errorCode,
    retryAfterSeconds: providerRetryFloor(
      "fcm",
      response.status,
      response.headers.get("retry-after"),
    ),
    status: response.status,
    latencyMs,
  };
}
