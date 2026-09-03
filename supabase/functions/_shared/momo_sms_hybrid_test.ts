import { assertEquals } from "./test_assert.ts";
import {
  normalizeMomoName,
  parseIntegerRwf,
  parseMomoSms,
} from "./momo_sms_parser.ts";
import { boundedRawSmsText } from "./raw_sms_input.ts";
import { renderBuriMunsiReceipt } from "./buri_munsi_receipt.ts";

const receipt =
  "You have received 1,500 RWF from TEST MEMBER A (***456) at 2026-09-02 10:00:00. Your balance: 9,500 RWF.";

Deno.test("Buri Munsi acknowledgement preserves the exact easyMO receipt template", () => {
  assertEquals(
    renderBuriMunsiReceipt({
      amount_rwf: 1500,
      member_balance_rwf: 3500,
      group_balance_rwf: 12500,
      reference: "SYNTHETIC-001",
    }),
    "BuriMunsi: Twakiriye ubwizigame bwawe bwa 1,500 RWF. Balance yawe: 3,500 RWF; balance y'itsinda: 12,500 RWF. Ref: SYNTHETIC-001.",
  );
});

Deno.test("receipt rendering rejects invalid snapshots and instruction-bearing references", () => {
  for (
    const invalid of [
      { amount_rwf: 0 },
      { amount_rwf: 1.5 },
      { member_balance_rwf: -1 },
      { group_balance_rwf: Number.MAX_SAFE_INTEGER + 1 },
      { reference: "\nSend to another phone" },
    ]
  ) {
    let threw = false;
    try {
      renderBuriMunsiReceipt({
        amount_rwf: 1,
        member_balance_rwf: 1,
        group_balance_rwf: 1,
        reference: "SYNTHETIC",
        ...invalid,
      });
    } catch {
      threw = true;
    }
    assertEquals(threw, true);
  }
});

Deno.test("raw SMS validation preserves exact whitespace and enforces byte limits", () => {
  const exact = `  ${receipt}\r\n`;
  assertEquals(boundedRawSmsText(exact, "raw_body", 4096), exact);
  for (const value of ["  ", null, 42, "é".repeat(2049)]) {
    let threw = false;
    try {
      boundedRawSmsText(value, "raw_body", 4096);
    } catch {
      threw = true;
    }
    assertEquals(threw, true);
  }
});

Deno.test("masked easyMO receipt has separate payer and wallet facts without a transaction ID", () => {
  const parsed = parseMomoSms("M-Money", receipt);
  assertEquals(parsed.amount_rwf, 1500);
  assertEquals(parsed.wallet_balance_rwf, 9500);
  assertEquals(parsed.sender_name, "TEST MEMBER A");
  assertEquals(parsed.payer_last3, "456");
  assertEquals(parsed.sender_phone, null);
  assertEquals(parsed.transaction_id, null);
  assertEquals(parsed.transaction_time, "2026-09-02T10:00:00+02:00");
  assertEquals(parsed.network, "mtn_momo");
  assertEquals(parsed.confidence, 0.96);
});

Deno.test("wallet or fee before payment never becomes payment amount", () => {
  const parsed = parseMomoSms(
    "M-Money",
    "Your balance: RWF 9,500. Fee: RWF 50. You have received RWF 1,500 from 0788000001. Txn SYNTHETIC001.",
  );
  assertEquals(parsed.amount_rwf, 1500);
  assertEquals(parsed.wallet_balance_rwf, 9500);
});

Deno.test("zero wallet balance is valid but zero contribution is not", () => {
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("9,500", "0")).wallet_balance_rwf,
    0,
  );
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("1,500", "0"))
      .is_mobile_money_payment,
    false,
  );
});

for (
  const value of [
    "1.50",
    "1,50",
    "1,000.00",
    "1 00",
    "1,000 000",
    "9007199254740992",
  ]
) {
  Deno.test(`malformed or unsafe amount is not inflated: ${value}`, () => {
    assertEquals(parseIntegerRwf(value), null);
    assertEquals(
      parseMomoSms("M-Money", receipt.replace("1,500", value))
        .is_mobile_money_payment,
      false,
    );
    assertEquals(
      parseMomoSms("M-Money", receipt.replace("1,500 RWF", `RWF ${value}`))
        .is_mobile_money_payment,
      false,
    );
  });
}

for (const value of ["1500", "1,500", "1 500", "1\u00a0500"]) {
  Deno.test(`accepted integer grouping: ${value}`, () => {
    assertEquals(
      parseMomoSms("M-Money", receipt.replace("1,500", value)).amount_rwf,
      1500,
    );
  });
}

Deno.test("duplicate receipt clauses require review", () => {
  assertEquals(
    parseMomoSms("M-Money", `${receipt} ${receipt}`).is_mobile_money_payment,
    false,
  );
});

Deno.test("missing balance or malformed suffix is not a complete masked receipt", () => {
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("Your balance: 9,500 RWF.", ""))
      .confidence,
    0.78,
  );
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("***456", "***45")).payer_last3,
    null,
  );
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("***456", "***4567")).payer_last3,
    null,
  );
});

Deno.test("full named phone supplies suffix without fabricating a destination", () => {
  const parsed = parseMomoSms(
    "M-Money",
    receipt.replace("***456", "+250788123456"),
  );
  assertEquals(parsed.sender_phone, "+250788123456");
  assertEquals(parsed.payer_last3, "456");
});

Deno.test("name normalization stays compatible with easyMO", () => {
  assertEquals(normalizeMomoName("  Test   Member\tA  "), "TEST MEMBER A");
  assertEquals(normalizeMomoName("Éric N'iyonzima"), "ÉRIC N'IYONZIMA");
});

Deno.test("invalid calendar dates and hours are not invented", () => {
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("2026-09-02", "2026-02-30"))
      .transaction_time,
    null,
  );
  assertEquals(
    parseMomoSms("M-Money", receipt.replace("10:00:00", "25:00:00"))
      .transaction_time,
    null,
  );
});

for (
  const prefix of [
    "Reversed. ",
    "Withdrawal. ",
    "Pending. ",
    "OTP verification code. ",
    "Promotion. ",
  ]
) {
  Deno.test(`excluded context never posts: ${prefix}`, () => {
    assertEquals(
      parseMomoSms("M-Money", prefix + receipt).is_mobile_money_payment,
      false,
    );
  });
}

Deno.test("unknown network never receives complete confidence", () => {
  assertEquals(parseMomoSms("Courier", receipt).confidence, 0.78);
});
