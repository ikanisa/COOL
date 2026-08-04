const DEFAULT_TOLERANCE_SECONDS = 300;

type StripeSignature = {
  timestamp: number;
  signatures: string[];
};

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

function parseStripeSignature(header: string): StripeSignature {
  const timestamps: string[] = [];
  const signatures: string[] = [];

  for (const part of header.split(",")) {
    const separator = part.indexOf("=");
    if (separator < 1) continue;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (key === "t") timestamps.push(value);
    if (key === "v1") signatures.push(value);
  }

  const timestamp = Number(timestamps[0]);
  if (
    timestamps.length !== 1 || !Number.isSafeInteger(timestamp) ||
    timestamp < 0 || signatures.length === 0
  ) {
    throw new Error("Invalid Stripe signature");
  }
  return { timestamp, signatures };
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

export async function verifyStripeSignature(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
  toleranceSeconds = DEFAULT_TOLERANCE_SECONDS,
): Promise<void> {
  if (!signatureHeader) throw new Error("Missing Stripe signature");
  if (!Number.isSafeInteger(nowSeconds) || toleranceSeconds <= 0) {
    throw new Error("Invalid Stripe signature verification settings");
  }

  const { timestamp, signatures } = parseStripeSignature(signatureHeader);
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) {
    throw new Error("Stripe signature timestamp outside tolerance");
  }

  const computed = await hmacSha256(secret, `${timestamp}.${rawBody}`);
  if (
    !signatures.some((candidate) => constantTimeHexEqual(computed, candidate))
  ) {
    throw new Error("Invalid Stripe signature");
  }
}
