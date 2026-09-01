export type ParsedMomoSms = {
  is_mobile_money_payment: boolean;
  network: "mtn_momo" | "airtel_money" | "unknown";
  direction: "incoming" | "outgoing" | "unknown";
  amount_rwf: number | null;
  currency: "RWF" | "unknown";
  transaction_id: string | null;
  sender_phone: string | null;
  detected_user_public_id: string | null;
  confidence: number;
};

const incomingPattern =
  /(?:you have received|received|credited|payment received|wakiriye|wahawe)/i;
const excludedPattern =
  /(?:failed|reversed|reversal|cancelled|pending|declined|you have sent|transferred to|cash.?out|withdraw)/i;
const amountPatterns = [
  /(?:RWF|FRW)\s*([0-9][0-9 ,.]{0,18})/i,
  /([0-9][0-9 ,.]{0,18})\s*(?:RWF|FRW)/i,
];
const transactionPattern =
  /(?:financial\s+transaction\s+id|transaction\s+id|txn|txid|reference|ref)\s*[:#-]?\s*([A-Z0-9][A-Z0-9._/-]{3,63})/i;
const senderPhonePattern =
  /(?:from|sender|payer)(?:\s+number)?\s*[:#-]?\s*(\+?250\s*7[2389](?:[\s-]*\d){7}|07[2389](?:[\s-]*\d){7})/i;
const collectIdPattern =
  /(?:collect\s*id|member\s*id|user\s*id)\s*[:#-]?\s*([0-9]{6})/i;

function parseAmount(body: string): number | null {
  for (const pattern of amountPatterns) {
    const match = body.match(pattern);
    if (!match) continue;
    const digits = match[1].replace(/[^0-9]/g, "");
    const amount = Number(digits);
    if (Number.isSafeInteger(amount) && amount > 0) return amount;
  }
  return null;
}

export function parseMomoSms(sender: string, body: string): ParsedMomoSms {
  const text = `${sender}\n${body}`;
  const network = /airtel/i.test(text)
    ? "airtel_money"
    : /(?:mtn|momo|mobilemoney|mobile money)/i.test(text)
    ? "mtn_momo"
    : "unknown";
  const incoming = incomingPattern.test(body) && !excludedPattern.test(body);
  const amount = parseAmount(body);
  const transactionId =
    body.match(transactionPattern)?.[1]?.trim().replace(/[.,;:]+$/, "") ??
    null;
  const senderPhone = body.match(senderPhonePattern)?.[1]
    ?.replace(/[^0-9+]/g, "") ?? null;
  const publicId = body.match(collectIdPattern)?.[1] ?? null;
  const complete = incoming &&
    amount != null &&
    transactionId != null &&
    (senderPhone != null || publicId != null);
  return {
    is_mobile_money_payment: incoming && amount != null,
    network,
    direction: incoming ? "incoming" : "unknown",
    amount_rwf: amount,
    currency: amount == null ? "unknown" : "RWF",
    transaction_id: transactionId,
    sender_phone: senderPhone,
    detected_user_public_id: publicId,
    confidence: complete ? 0.96 : incoming && amount != null ? 0.78 : 0.25,
  };
}
