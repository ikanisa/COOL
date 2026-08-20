import {
  parseProviderFinalityEvent,
  ProviderFinalityPayloadError,
} from "./provider_finality_payload.ts";

const requestId = "10000000-0000-4000-8000-000000000001";
const paymentId = "20000000-0000-4000-8000-000000000001";

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, got ${String(actual)}`);
  }
}

function expectPayloadRejected(run: () => unknown): void {
  try {
    run();
  } catch (error) {
    if (error instanceof ProviderFinalityPayloadError) return;
    throw error;
  }
  throw new Error("Expected provider finality payload to reject");
}

Deno.test("provider finality confirmation payload is strict and normalized", () => {
  const event = parseProviderFinalityEvent(
    JSON.stringify({
      schema_version: 1,
      event_id: requestId,
      event_type: "payment.confirmed",
      payment_id: paymentId,
      provider_network: "MTN_MOMO",
      transaction_id: " TXN-001 ",
      provider_confirmation_id: " CONF-001 ",
      receiver_momo_number_hash: "a".repeat(64),
      amount_rwf: 10_000,
      currency: "RWF",
      occurred_at: "2027-01-15T10:00:00Z",
    }),
    requestId,
  );
  assertEquals(event.eventType, "payment.confirmed");
  if (event.eventType === "payment.confirmed") {
    assertEquals(event.providerNetwork, "mtn_momo");
    assertEquals(event.transactionId, "TXN-001");
    assertEquals(event.amountRwf, 10_000);
  }
});

Deno.test("provider finality payload binds the signed request id", () => {
  expectPayloadRejected(
    () =>
      parseProviderFinalityEvent(
        JSON.stringify({
          schema_version: 1,
          event_id: requestId,
          event_type: "payment.rejected",
          payment_id: paymentId,
          reason: "Provider did not settle the transaction",
        }),
        "30000000-0000-4000-8000-000000000001",
      ),
  );
});

Deno.test("provider finality payload rejects unknown fields", () => {
  expectPayloadRejected(
    () =>
      parseProviderFinalityEvent(
        JSON.stringify({
          schema_version: 1,
          event_id: requestId,
          event_type: "payment.rejected",
          payment_id: paymentId,
          reason: "Provider did not settle the transaction",
          unexpected: true,
        }),
        requestId,
      ),
  );
});
