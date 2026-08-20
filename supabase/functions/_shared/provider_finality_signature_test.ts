import {
  ProviderFinalityAuthError,
  verifyProviderFinalitySignature,
} from "./provider_finality_signature.ts";

const secret = "controlled-provider-finality-secret-0001";
const requestId = "10000000-0000-4000-8000-000000000001";
const timestamp = 1_800_000_000;
const body = JSON.stringify({ event_id: requestId });

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function expectAuthRejected(run: () => Promise<unknown>): Promise<void> {
  try {
    await run();
  } catch (error) {
    if (error instanceof ProviderFinalityAuthError) return;
    throw error;
  }
  throw new Error("Expected provider finality authentication to reject");
}

async function signature(payload: string, signingSecret = secret) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
  );
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.test("provider finality signature binds timestamp, request id, and body", async () => {
  const digest = await signature(`${timestamp}.${requestId}.${body}`);
  const result = await verifyProviderFinalitySignature(
    body,
    String(timestamp),
    requestId,
    `v1=${digest}`,
    [secret],
    timestamp,
  );
  assertEquals(result, { requestId, timestamp });
});

Deno.test("provider finality signature supports a previous rotation key", async () => {
  const previous = "controlled-provider-finality-secret-previous";
  const digest = await signature(
    `${timestamp}.${requestId}.${body}`,
    previous,
  );
  await verifyProviderFinalitySignature(
    body,
    String(timestamp),
    requestId,
    `v1=${digest}`,
    [secret, previous],
    timestamp,
  );
});

Deno.test("provider finality signature rejects stale and tampered requests", async () => {
  const digest = await signature(`${timestamp}.${requestId}.${body}`);
  await expectAuthRejected(
    () =>
      verifyProviderFinalitySignature(
        `${body} `,
        String(timestamp),
        requestId,
        `v1=${digest}`,
        [secret],
        timestamp,
      ),
  );
  await expectAuthRejected(
    () =>
      verifyProviderFinalitySignature(
        body,
        String(timestamp),
        requestId,
        `v1=${digest}`,
        [secret],
        timestamp + 301,
      ),
  );
  await expectAuthRejected(() =>
    verifyProviderFinalitySignature(
      body,
      String(timestamp),
      requestId,
      `v1=${digest},${"v1=" + "0".repeat(64)}`.repeat(5),
      [secret],
      timestamp,
    )
  );
});
