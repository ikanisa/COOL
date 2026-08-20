import { assertEquals } from "./test_assert.ts";
import { parseBankStatement } from "./bank_statement.ts";

Deno.test("parses CSV statement rows", () => {
  const rows = parseBankStatement("csv", [
    "transaction_id,end_to_end_id,reference,payer_name,amount,currency,booked_at,value_date",
    "TX1,E2E1,COL-0123456789,Alice,12.34,EUR,2026-08-20T10:00:00Z,2026-08-20",
  ].join("\n"));
  assertEquals(rows[0].amount_minor, 1234);
  assertEquals(rows[0].transfer_reference, "COL-0123456789");
});

Deno.test("parses JSON statement rows", () => {
  const rows = parseBankStatement("json", JSON.stringify({ lines: [{
    bank_transaction_id: "TX2",
    reference: "COL-ABCDEFGHIJ",
    amount_minor: 500,
    currency: "EUR",
    booked_at: "2026-08-20T11:00:00Z",
    value_date: "2026-08-20",
  }] }));
  assertEquals(rows[0].amount_minor, 500);
});
