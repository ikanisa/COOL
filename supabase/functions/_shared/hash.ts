const encoder = new TextEncoder();

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function normalizeRwandaPhone(
  input: string | null | undefined,
): string | null {
  if (!input) return null;
  const trimmed = input.trim();
  if (!trimmed) return null;
  let digits = trimmed.replace(/[^\d+]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith("250") && digits.length === 12) return `+${digits}`;
  if (digits.startsWith("0") && digits.length === 10) {
    return `+250${digits.slice(1)}`;
  }
  if (digits.length === 9 && /^[2378]/.test(digits)) return `+250${digits}`;
  return trimmed.startsWith("+") ? trimmed : `+${digits}`;
}

export async function hashPhone(
  input: string | null | undefined,
): Promise<string | null> {
  const normalized = normalizeRwandaPhone(input);
  if (!normalized) return null;
  return sha256Hex(normalized);
}

export function redactSmsForParser(body: string): string {
  return body
    .replace(
      /(balance|solde|ikigega|remaining)[^\n.]{0,80}/gi,
      "[balance redacted]",
    )
    .replace(
      /(new balance|available balance)[^\n.]{0,80}/gi,
      "[balance redacted]",
    )
    .slice(0, 2000);
}
