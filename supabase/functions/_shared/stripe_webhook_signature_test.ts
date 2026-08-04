import { verifyStripeSignature } from "./stripe_webhook_signature.ts";

const secret = "whsec_test_only";
const body = '{"id":"evt_test","type":"payment_intent.succeeded"}';
const now = 1_800_000_000;

async function hmac(payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function expectRejected(run: () => Promise<void>): Promise<void> {
  let rejected = false;
  try {
    await run();
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Expected signature verification to reject");
}

Deno.test("accepts a current valid Stripe signature", async () => {
  const signature = await hmac(`${now}.${body}`);
  await verifyStripeSignature(body, `t=${now},v1=${signature}`, secret, now);
});

Deno.test("accepts any valid v1 signature during secret rotation", async () => {
  const signature = await hmac(`${now}.${body}`);
  await verifyStripeSignature(
    body,
    `t=${now},v1=${"0".repeat(64)},v1=${signature}`,
    secret,
    now,
  );
});

Deno.test("rejects replayed and future-dated signatures", async () => {
  for (const timestamp of [now - 301, now + 301]) {
    const signature = await hmac(`${timestamp}.${body}`);
    await expectRejected(() =>
      verifyStripeSignature(
        body,
        `t=${timestamp},v1=${signature}`,
        secret,
        now,
      )
    );
  }
});

Deno.test("rejects malformed or invalid signatures", async () => {
  await expectRejected(() =>
    verifyStripeSignature(body, `t=${now},v1=not-hex`, secret, now)
  );
  await expectRejected(() =>
    verifyStripeSignature(
      body,
      `t=${now},t=${now},v1=${"0".repeat(64)}`,
      secret,
      now,
    )
  );
});
