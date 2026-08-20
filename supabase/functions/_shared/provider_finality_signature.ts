const DEFAULT_TOLERANCE_SECONDS = 300;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class ProviderFinalityAuthError extends Error {
  constructor() {
    super("Provider finality authentication failed");
    this.name = "ProviderFinalityAuthError";
  }
}

function hex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha256(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
  );
}

function constantTimeHexEqual(actual: string, expected: string): boolean {
  if (
    actual.length !== expected.length ||
    !/^[0-9a-f]+$/i.test(actual) ||
    !/^[0-9a-f]+$/i.test(expected)
  ) {
    return false;
  }
  let mismatch = 0;
  for (let index = 0; index < actual.length; index += 1) {
    mismatch |= actual.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return mismatch === 0;
}

function parseSignatures(header: string | null): string[] {
  if (!header || header.length > 300) throw new ProviderFinalityAuthError();
  const signatures = header.split(",").flatMap((part) => {
    const [version, value, ...remainder] = part.trim().split("=");
    if (version !== "v1" || remainder.length > 0 || !value) return [];
    return /^[0-9a-f]{64}$/i.test(value) ? [value.toLowerCase()] : [];
  });
  if (signatures.length === 0 || signatures.length > 4) {
    throw new ProviderFinalityAuthError();
  }
  return signatures;
}

export type VerifiedProviderFinalityRequest = {
  requestId: string;
  timestamp: number;
};

export async function verifyProviderFinalitySignature(
  rawBody: string,
  timestampHeader: string | null,
  requestIdHeader: string | null,
  signatureHeader: string | null,
  secrets: string[],
  nowSeconds = Math.floor(Date.now() / 1000),
  toleranceSeconds = DEFAULT_TOLERANCE_SECONDS,
): Promise<VerifiedProviderFinalityRequest> {
  const timestamp = Number(timestampHeader);
  const requestId = requestIdHeader?.trim().toLowerCase() ?? "";
  if (
    !timestampHeader || !/^[0-9]{10}$/.test(timestampHeader) ||
    !Number.isSafeInteger(timestamp) ||
    !UUID_PATTERN.test(requestId) ||
    !Number.isSafeInteger(nowSeconds) || toleranceSeconds <= 0 ||
    Math.abs(nowSeconds - timestamp) > toleranceSeconds ||
    secrets.length === 0 ||
    secrets.some((secret) => secret.length < 32)
  ) {
    throw new ProviderFinalityAuthError();
  }

  const signatures = parseSignatures(signatureHeader);
  const signedPayload = `${timestamp}.${requestId}.${rawBody}`;
  const expected = await Promise.all(
    [...new Set(secrets)].map((secret) => hmacSha256(secret, signedPayload)),
  );
  let matched = 0;
  for (const candidate of expected) {
    for (const signature of signatures) {
      matched |= constantTimeHexEqual(candidate, signature) ? 1 : 0;
    }
  }
  if (matched !== 1) {
    throw new ProviderFinalityAuthError();
  }

  return { requestId, timestamp };
}

export async function sha256Hex(value: string): Promise<string> {
  return hex(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}
