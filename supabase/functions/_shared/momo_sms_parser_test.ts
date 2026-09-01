import { assertEquals } from "./test_assert.ts";
import { parseMomoSms } from "./momo_sms_parser.ts";

Deno.test("parses a complete incoming Rwanda MoMo receipt", () => {
  const parsed = parseMomoSms(
    "M-Money",
    "You have received RWF 12,500 from 0788123456. Financial Transaction Id: 12345678901.",
  );
  assertEquals(parsed.direction, "incoming");
  assertEquals(parsed.amount_rwf, 12500);
  assertEquals(parsed.transaction_id, "12345678901");
  assertEquals(parsed.sender_phone, "0788123456");
  assertEquals(parsed.confidence, 0.96);
});

Deno.test("reversed or outgoing messages never become incoming receipts", () => {
  const parsed = parseMomoSms(
    "AirtelMoney",
    "Transaction reversed. You have sent 5,000 RWF to 0732123456. Txn 99887766",
  );
  assertEquals(parsed.direction, "unknown");
  assertEquals(parsed.is_mobile_money_payment, false);
});
