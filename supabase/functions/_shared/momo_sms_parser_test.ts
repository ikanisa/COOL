import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseDeterministicMomoSms } from "./momo_sms_parser.ts";

Deno.test("parses high-confidence incoming MoMo SMS variants", () => {
  const cases = [
    {
      sender: "MTN MoMo",
      body:
        "You have received RWF 5,000 from a customer. Financial Transaction Id: ABCD1234.",
      amount: 5000,
      language: "en",
      network: "mtn_momo",
    },
    {
      sender: "Airtel Money",
      body: "Paiement reçu: 2 500 FRW. Référence: FR123456.",
      amount: 2500,
      language: "fr",
      network: "airtel_money",
    },
    {
      sender: "M-Money",
      body: "Konti yawe yakiriye amafaranga 4,500 RWF. TxId RW123456.",
      amount: 4500,
      language: "rw",
      network: "mtn_momo",
    },
  ] as const;

  for (const fixture of cases) {
    const parsed = parseDeterministicMomoSms(fixture.sender, fixture.body);
    assertEquals(parsed?.is_mobile_money_payment, true);
    assertEquals(parsed?.direction, "incoming");
    assertEquals(parsed?.amount_rwf, fixture.amount);
    assertEquals(parsed?.currency, "RWF");
    assertEquals(parsed?.message_language, fixture.language);
    assertEquals(parsed?.network, fixture.network);
  }
});

Deno.test("rejects outgoing and promotional MoMo SMS as payments", () => {
  const outgoing = parseDeterministicMomoSms(
    "MTN MoMo",
    "You have sent RWF 2,000 to a merchant. TxId OUT12345.",
  );
  assertEquals(outgoing?.is_mobile_money_payment, false);
  assertEquals(outgoing?.direction, "outgoing");

  const promotion = parseDeterministicMomoSms(
    "Airtel Money",
    "Promotion: buy a bundle today for only RWF 1,000.",
  );
  assertEquals(promotion?.is_mobile_money_payment, false);
});

Deno.test("defers ambiguous messages to the structured model parser", () => {
  assertEquals(
    parseDeterministicMomoSms(
      "M-Money",
      "You have received 5000. Financial Transaction Id: 123456789.",
    ),
    null,
  );
});
