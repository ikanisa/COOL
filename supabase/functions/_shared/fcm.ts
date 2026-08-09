export type FcmCredentials = {
  serviceAccountJson: string;
};

export type FcmMessage = {
  token: string;
  title: string;
  body: string;
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
  const tokenUri = account.token_uri || defaultTokenUri;
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
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${base64Url(signature)}`,
    }),
  });
  const payload = await response.json().catch(() => ({})) as {
    access_token?: unknown;
  };
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new Error("FCM OAuth token exchange failed");
  }
  return payload.access_token;
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
  const account = serviceAccount(credentials);
  const started = performance.now();
  const response = await fetcher(
    `https://fcm.googleapis.com/v1/projects/${
      encodeURIComponent(account.project_id)
    }/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: message.title, body: message.body },
          data: {
            collect_event_id: message.eventId,
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
  const latencyMs = Math.max(0, Math.round(performance.now() - started));
  const payload = await response.json().catch(() => ({})) as {
    name?: unknown;
    error?: {
      status?: unknown;
      details?: Array<{ errorCode?: unknown }>;
    };
  };
  const detailCode = payload.error?.details?.find(
    (detail) => typeof detail.errorCode === "string",
  )?.errorCode;
  const errorCode = response.ok
    ? null
    : typeof detailCode === "string"
    ? detailCode
    : typeof payload.error?.status === "string"
    ? payload.error.status
    : `http_${response.status}`;
  return {
    ok: response.ok,
    retryable: response.status === 408 ||
      response.status === 429 ||
      response.status >= 500,
    messageId: typeof payload.name === "string" ? payload.name : null,
    errorCode,
    status: response.status,
    latencyMs,
  };
}
