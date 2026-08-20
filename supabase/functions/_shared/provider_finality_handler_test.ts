import {
  handleProviderFinalityRequest,
  ProviderFinalityHandlerDependencies,
} from "./provider_finality_handler.ts";

const secret = "controlled-provider-finality-handler-secret";
const requestId = "10000000-0000-4000-8000-000000000001";
const paymentId = "20000000-0000-4000-8000-000000000001";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function hmac(payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
  );
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function body(): string {
  return JSON.stringify({
    schema_version: 1,
    event_id: requestId,
    event_type: "payment.confirmed",
    payment_id: paymentId,
    provider_network: "mtn_momo",
    transaction_id: "TXN-001",
    provider_confirmation_id: "CONF-001",
    receiver_momo_number_hash: "a".repeat(64),
    amount_rwf: 10_000,
    currency: "RWF",
    occurred_at: "2027-01-15T10:00:00Z",
  });
}

async function signedRequest(
  rawBody = body(),
  signatureBody = rawBody,
): Promise<Request> {
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = await hmac(`${timestamp}.${requestId}.${signatureBody}`);
  return new Request("http://localhost/functions/v1/provider-finality", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-provider-finality-timestamp": String(timestamp),
      "x-provider-finality-request-id": requestId,
      "x-provider-finality-signature": `v1=${signature}`,
    },
    body: rawBody,
  });
}

function dependencies(
  processEvent: ProviderFinalityHandlerDependencies["processEvent"],
): ProviderFinalityHandlerDependencies {
  return { currentSecret: secret, processEvent };
}

Deno.test("provider finality handler sends a verified confirmation to one RPC", async () => {
  const calls: Record<string, unknown>[] = [];
  const response = await handleProviderFinalityRequest(
    await signedRequest(),
    dependencies((arguments_) => {
      calls.push(arguments_);
      return Promise.resolve({
        data: { payment_id: paymentId, replayed: false },
        error: null,
      });
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    received: true,
    request_id: requestId,
    payment_id: paymentId,
    replayed: false,
  });
  assertEquals(calls.length, 1);
  assertEquals(calls[0].p_event_type, "payment.confirmed");
  assertEquals(calls[0].p_payment_id, paymentId);
  assertEquals(calls[0].p_transaction_id, "TXN-001");
  assertEquals(calls[0].p_amount_rwf, 10_000);
});

Deno.test("provider finality handler rejects tampering before the RPC", async () => {
  let calls = 0;
  const response = await handleProviderFinalityRequest(
    await signedRequest(`${body()} `, body()),
    dependencies(() => {
      calls += 1;
      return Promise.resolve({ data: null, error: null });
    }),
  );
  assertEquals(response.status, 401);
  assertEquals(calls, 0);
});

Deno.test("provider finality handler maps strict payload errors to 400", async () => {
  const invalidBody = JSON.stringify({
    schema_version: 2,
    event_id: requestId,
    event_type: "payment.confirmed",
    payment_id: paymentId,
  });
  const response = await handleProviderFinalityRequest(
    await signedRequest(invalidBody),
    dependencies(() => Promise.resolve({ data: null, error: null })),
  );
  assertEquals(response.status, 400);
});

Deno.test("provider finality handler hides database errors behind 409", async () => {
  const originalError = console.error;
  console.error = () => undefined;
  try {
    const response = await handleProviderFinalityRequest(
      await signedRequest(),
      dependencies(() =>
        Promise.resolve({
          data: null,
          error: { code: "P0001", message: "sensitive database detail" },
        })
      ),
    );
    assertEquals(response.status, 409);
    assertEquals(await response.json(), {
      error: "Provider finality event rejected",
    });
  } finally {
    console.error = originalError;
  }
});

Deno.test("provider finality handler rejects method and declared oversize", async () => {
  const methodResponse = await handleProviderFinalityRequest(
    new Request("http://localhost", { method: "GET" }),
    dependencies(() => Promise.resolve({ data: null, error: null })),
  );
  assertEquals(methodResponse.status, 405);

  const sizeResponse = await handleProviderFinalityRequest(
    new Request("http://localhost", {
      method: "POST",
      headers: { "content-length": String(64 * 1024 + 1) },
      body: "{}",
    }),
    dependencies(() => Promise.resolve({ data: null, error: null })),
  );
  assertEquals(sizeResponse.status, 413);
});
