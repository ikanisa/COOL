import { assertEquals } from "./test_assert.ts";
import { parseBankEvidence } from "./bank_evidence.ts";

Deno.test("parses strict incoming EUR bank evidence", () => {
  const parsed = parseBankEvidence(
    "Revolut",
    "Transfer received and completed. EUR 1,234.56 from: Alice Example; transaction ID: TX-998877; End-to-end ID: E2E-123456; reference COL-AB12CD34EF; account ending 9Z8Y",
    "2026-08-20T10:00:00Z",
  );
  assertEquals(parsed.direction, "incoming");
  assertEquals(parsed.amount_minor, 123456);
  assertEquals(parsed.currency, "EUR");
  assertEquals(parsed.bank_transaction_id, "TX-998877");
  assertEquals(parsed.end_to_end_id, "E2E-123456");
  assertEquals(parsed.transfer_reference, "COL-AB12CD34EF");
  assertEquals(parsed.payer_account_last4, "9Z8Y");
  assertEquals(parsed.confidence, 1);
});

Deno.test("supports European decimal formatting", () => {
  const parsed = parseBankEvidence(
    "Bank",
    "Incoming payment received: 1.234,56 EUR. Txn: ABCD1234. Ref COL-0123456789",
    "2026-08-20T10:00:00Z",
  );
  assertEquals(parsed.amount_minor, 123456);
  assertEquals(parsed.confidence, 1);
});

Deno.test("never treats pending or reversed evidence as settlement", () => {
  for (const body of [
    "Incoming EUR 10.00 pending. Txn: ABCD1234. Ref COL-0123456789",
    "EUR 10.00 received but reversed. Txn: ABCD1234. Ref COL-0123456789",
  ]) {
    const parsed = parseBankEvidence("Bank", body, "2026-08-20T10:00:00Z");
    assertEquals(parsed.direction, "unknown");
    assertEquals(parsed.confidence < 0.9, true);
  }
});

Deno.test("missing reference remains review-only", () => {
  const parsed = parseBankEvidence(
    "Bank",
    "Incoming payment received EUR 10.00. Transaction ID: ABCD1234",
    "2026-08-20T10:00:00Z",
  );
  assertEquals(parsed.transfer_reference, null);
  assertEquals(parsed.confidence, 0.8);
});
