export type MomoSmsParserResult = {
  is_mobile_money_payment: boolean;
  network: "mtn_momo" | "airtel_money" | "unknown";
  direction: "incoming" | "outgoing" | "unknown";
  amount_rwf: number | null;
  currency: "RWF" | "unknown";
  transaction_id: string | null;
  sender_phone: string | null;
  receiver_phone: string | null;
  transaction_time: string | null;
  message_language: "en" | "rw" | "fr" | "unknown";
  detected_user_public_id: string | null;
  balance_mentioned: boolean;
  fees_mentioned: boolean;
  confidence: number;
};

const providerPattern = /momo|m[-\s]?money|mobile\s*money|mtn|airtel/iu;
const incomingPattern =
  /received|credited|cash[ -]?in|deposit(?:ed)?|re(?:c|ç)u|paiement\s+re(?:c|ç)u|versement|d(?:e|é)p(?:o|ô)t|wakiriye|yakiriye|yishyuwe|amafaranga/iu;
const outgoingPattern =
  /you\s+(?:have\s+)?sent|sent\s+to|paid\s+to|cash[ -]?out|withdrawn|retir(?:e|é)|envoy(?:e|é)|woherereje|wishyuye/iu;
const unsafePattern =
  /failed|declined|cancelled|canceled|reversed|reversal|pending|airtime|bundle|loan|promotion|promo\b/iu;

function networkFor(value: string): MomoSmsParserResult["network"] {
  if (/airtel/iu.test(value)) return "airtel_money";
  if (/mtn|momo|m[-\s]?money|mobile\s*money/iu.test(value)) return "mtn_momo";
  return "unknown";
}

function languageFor(value: string): MomoSmsParserResult["message_language"] {
  if (/wakiriye|yakiriye|woherereje|wishyuye|yishyuwe|amafaranga|konti/iu.test(value)) {
    return "rw";
  }
  if (/re(?:c|ç)u|paiement|versement|d(?:e|é)p(?:o|ô)t|envoy(?:e|é)|solde/iu.test(value)) {
    return "fr";
  }
  if (/received|credited|sent|payment|transaction|balance/iu.test(value)) return "en";
  return "unknown";
}

function amountFor(value: string): number | null {
  const patterns = [
    /(?:RWF|FRW)\s*([0-9][0-9\s,.]*)/iu,
    /([0-9][0-9\s,.]*)\s*(?:RWF|FRW)/iu,
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(value);
    const digits = match?.[1]?.replace(/\D/g, "") ?? "";
    if (!digits) continue;
    const amount = Number(digits);
    if (Number.isSafeInteger(amount) && amount > 0) return amount;
  }
  return null;
}

function transactionIdFor(value: string): string | null {
  const match = /(?:financial\s+transaction\s+(?:id|identifier)|transaction\s+(?:id|identifier)|trans(?:action)?\s*id|txn(?:\s*id)?|txid|reference|ref)\s*[:#-]?\s*([a-z0-9][a-z0-9-]{3,63})/iu
    .exec(value);
  return match?.[1] ?? null;
}

function publicIdFor(value: string): string | null {
  const match = /(?:collect|member|user)\s*id\s*[:#-]?\s*([0-9]{6})(?![0-9])/iu
    .exec(value);
  return match?.[1] ?? null;
}

/**
 * Parses only high-confidence MoMo notifications. Ambiguous messages return
 * null and continue through the structured model parser in the Edge Function.
 */
export function parseDeterministicMomoSms(
  rawSender: string,
  rawBody: string,
): MomoSmsParserResult | null {
  const value = `${rawSender}\n${rawBody}`.trim();
  if (!value || !providerPattern.test(value)) return null;

  const amount = amountFor(rawBody);
  const hasCurrency = /(?:RWF|FRW)/iu.test(rawBody);
  const outgoing = outgoingPattern.test(rawBody);
  const unsafe = unsafePattern.test(rawBody);
  const incoming = incomingPattern.test(rawBody) && !outgoing && !unsafe;

  if (!incoming) {
    if (!outgoing && !unsafe) return null;
    return {
      is_mobile_money_payment: false,
      network: networkFor(value),
      direction: outgoing ? "outgoing" : "unknown",
      amount_rwf: amount,
      currency: hasCurrency ? "RWF" : "unknown",
      transaction_id: transactionIdFor(rawBody),
      sender_phone: null,
      receiver_phone: null,
      transaction_time: null,
      message_language: languageFor(rawBody),
      detected_user_public_id: publicIdFor(rawBody),
      balance_mentioned: /balance|solde|ikigega|remaining/iu.test(rawBody),
      fees_mentioned: /fee|fees|frais|ikiguzi/iu.test(rawBody),
      confidence: 0.99,
    };
  }

  if (!hasCurrency || amount == null) return null;
  const transactionId = transactionIdFor(rawBody);
  return {
    is_mobile_money_payment: true,
    network: networkFor(value),
    direction: "incoming",
    amount_rwf: amount,
    currency: "RWF",
    transaction_id: transactionId,
    sender_phone: null,
    receiver_phone: null,
    transaction_time: null,
    message_language: languageFor(rawBody),
    detected_user_public_id: publicIdFor(rawBody),
    balance_mentioned: /balance|solde|ikigega|remaining/iu.test(rawBody),
    fees_mentioned: /fee|fees|frais|ikiguzi/iu.test(rawBody),
    confidence: transactionId == null ? 0.9 : 0.96,
  };
}
