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
  if (typeof input !== "string") return null;
  const value = input.trim();
  if (!value || value.length > 32 || !/^[+0-9() -]+$/.test(value)) return null;
  let digits = value.replace(/[() -]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  else if (digits.startsWith("00")) digits = digits.slice(2);
  if (/^07[2389][0-9]{7}$/.test(digits)) digits = `250${digits.slice(1)}`;
  else if (/^7[2389][0-9]{7}$/.test(digits)) digits = `250${digits}`;
  return /^2507[2389][0-9]{7}$/.test(digits) ? `+${digits}` : null;
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
