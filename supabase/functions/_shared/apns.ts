export type ApnsCredentials = {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKeyBase64: string;
};

export type ApnsMessage = {
  token: string;
  environment: "sandbox" | "production";
  title: string;
  body: string;
  eventId: string;
  eventType: string;
  deepLink?: string | null;
};

export type ApnsResult = {
  ok: boolean;
  retryable: boolean;
  messageId: string | null;
  errorCode: string | null;
  status: number;
  latencyMs: number;
};

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value.replace(/\s+/g, ""));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function privateKeyDer(encoded: string): Uint8Array {
  const decoded = decodeBase64(encoded);
  const text = new TextDecoder().decode(decoded);
  if (!text.includes("BEGIN PRIVATE KEY")) return decoded;
  const body = text
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  return decodeBase64(body);
}

export async function createApnsJwt(
  credentials: Pick<ApnsCredentials, "keyId" | "teamId" | "privateKeyBase64">,
  issuedAt = Math.floor(Date.now() / 1000),
): Promise<string> {
  const header = base64UrlJson({ alg: "ES256", kid: credentials.keyId });
  const claims = base64UrlJson({ iss: credentials.teamId, iat: issuedAt });
  const unsigned = `${header}.${claims}`;
  const keyData = Uint8Array.from(
    privateKeyDer(credentials.privateKeyBase64),
  ).buffer;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  return `${unsigned}.${base64Url(signature)}`;
}

export async function sendApnsMessage(
  credentials: ApnsCredentials,
  authorization: string,
  message: ApnsMessage,
  fetcher: typeof fetch = fetch,
): Promise<ApnsResult> {
  const host = message.environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const started = performance.now();
  const response = await fetcher(
    `${host}/3/device/${encodeURIComponent(message.token)}`,
    {
      method: "POST",
      headers: {
        authorization: `bearer ${authorization}`,
        "apns-topic": credentials.bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: { title: message.title, body: message.body },
          sound: "default",
        },
        collect_event_id: message.eventId,
        type: message.eventType,
        ...(message.deepLink ? { deep_link: message.deepLink } : {}),
      }),
    },
  );
  const latencyMs = Math.max(0, Math.round(performance.now() - started));
  let errorCode: string | null = null;
  if (!response.ok) {
    try {
      const payload = await response.json() as { reason?: unknown };
      if (typeof payload.reason === "string") errorCode = payload.reason;
    } catch {
      errorCode = `http_${response.status}`;
    }
  }
  const retryable = response.status === 429 || response.status >= 500;
  return {
    ok: response.ok,
    retryable,
    messageId: response.headers.get("apns-id"),
    errorCode,
    status: response.status,
    latencyMs,
  };
}
