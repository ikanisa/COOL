import { normalizePhone } from "./phone.ts";

const encoder = new TextEncoder();

function requireSecret(name: string, fallback?: string): string {
  const value = Deno.env.get(name) ?? fallback;
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }

  return value;
}

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function hmacSha256(secret: string, value: string): Promise<Uint8Array> {
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
    encoder.encode(value),
  );

  return new Uint8Array(signature);
}

export async function hmacSha256Hex(
  secret: string,
  value: string,
): Promise<string> {
  const signature = await hmacSha256(secret, value);
  return bytesToHex(signature);
}

export async function verifyHmacSha256Hex(options: {
  secret: string;
  value: string;
  signature: string | null | undefined;
}): Promise<boolean> {
  const provided = options.signature?.trim().toLowerCase()
    .replace(/^sha256=/, "");
  if (!provided) {
    return false;
  }

  const expected = await hmacSha256Hex(options.secret, options.value);
  if (provided.length != expected.length) {
    return false;
  }

  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  }

  return mismatch === 0;
}

export function generateOtpCode(): string {
  const randomValue = crypto.getRandomValues(new Uint32Array(1))[0];
  return (randomValue % 1000000).toString().padStart(6, "0");
}

export async function hashOtpCode(
  phone: string,
  code: string,
): Promise<string> {
  const secret = requireSecret("OTP_CODE_HASH_SECRET");

  const signature = await hmacSha256(secret, `${phone}:${code}`);
  return bytesToHex(signature);
}

export async function derivePhonePassword(phone: string): Promise<string> {
  const secret = requireSecret("AUTH_PHONE_PASSWORD_SECRET");

  const signature = await hmacSha256(secret, `cool-auth:${phone}`);
  return `Cool!${bytesToHex(signature)}`;
}

export async function derivePhoneEmail(phone: string): Promise<string> {
  const secret = requireSecret("AUTH_PHONE_PASSWORD_SECRET");

  const signature = await hmacSha256(secret, `cool-email:${phone}`);
  return `wa-${bytesToHex(signature).slice(0, 32)}@auth.cool.local`;
}

type ReviewOtpConfig = {
  normalizedPhone: string;
  code: string;
};

export function getReviewOtpConfig(): ReviewOtpConfig | null {
  const configuredPhone = Deno.env.get("OTP_TEST_PHONE")?.trim();
  const configuredCode = Deno.env.get("OTP_TEST_CODE")?.trim();
  if (!configuredPhone || !configuredCode) {
    return null;
  }

  if (!/^\d{6}$/.test(configuredCode)) {
    console.error("OTP_TEST_CODE must be exactly 6 digits.");
    return null;
  }

  try {
    return {
      normalizedPhone: normalizePhone(configuredPhone),
      code: configuredCode,
    };
  } catch (error) {
    console.error("OTP_TEST_PHONE is invalid.", error);
    return null;
  }
}

export function resolveReviewOtp(normalizedPhone: string): string | null {
  const config = getReviewOtpConfig();
  if (!config) {
    return null;
  }
  return config.normalizedPhone === normalizedPhone ? config.code : null;
}

export function isReviewOtpMatch(
  normalizedPhone: string,
  code: string,
): boolean {
  const config = getReviewOtpConfig();
  if (!config) {
    return false;
  }
  return config.normalizedPhone === normalizedPhone && config.code === code;
}
