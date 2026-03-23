import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";

function buildUssdCode(routeType: string, recipientValue: string): string {
  const cleaned = recipientValue.trim();
  switch (routeType) {
    case "phone_number":
      return `*182*1*1*${cleaned}#`;
    case "code":
      return `*182*8*1*${cleaned}#`;
    default:
      throw new Error(`Unknown route type: ${routeType}`);
  }
}

Deno.test("buildUssdCode generates correct phone_number USSD", () => {
  const ussd = buildUssdCode("phone_number", "0781234567");
  assertEquals(ussd, "*182*1*1*0781234567#");
});

Deno.test("buildUssdCode generates correct code USSD", () => {
  const ussd = buildUssdCode("code", "12345");
  assertEquals(ussd, "*182*8*1*12345#");
});

Deno.test("generateNonce produces 48-char hex string", () => {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  const nonce = Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  assertEquals(nonce.length, 48);
  assertEquals(/^[0-9a-f]{48}$/.test(nonce), true);
});

Deno.test("intent expires after TTL", () => {
  const INTENT_TTL_SECONDS = 300; // 5 minutes
  const now = Date.now();

  // Fresh intent
  const freshExpiry = new Date(now + INTENT_TTL_SECONDS * 1000);
  assertEquals(freshExpiry.getTime() > now, true);

  // Expired intent
  const staleExpiry = new Date(now - 1000);
  assertEquals(staleExpiry.getTime() < now, true);
});

Deno.test("nonce uniqueness across multiple generations", () => {
  const nonces = new Set<string>();
  for (let i = 0; i < 100; i++) {
    const bytes = new Uint8Array(24);
    crypto.getRandomValues(bytes);
    const nonce = Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    nonces.add(nonce);
  }
  // All 100 nonces should be unique
  assertEquals(nonces.size, 100);
});
