export type ParsedMomoSms = {
  is_mobile_money_payment: boolean;
  network: "mtn_momo" | "airtel_money" | "unknown";
  direction: "incoming" | "outgoing" | "unknown";
  amount_rwf: number | null;
  wallet_balance_rwf: number | null;
  currency: "RWF" | "unknown";
  transaction_id: string | null;
  transaction_time: string | null;
  sender_phone: string | null;
  sender_name: string | null;
  payer_last3: string | null;
  detected_user_public_id: string | null;
  confidence: number;
};

const incomingClause = String
  .raw`(?:you have received|payment received|received|credited|wakiriye|wahawe)`;
const excludedPattern =
  /\b(?:failed|reversed|reversal|cancelled|pending|declined|you have sent|transferred to|cash.?out|withdraw(?:al|n)?|promotion|promo|OTP|verification code|one.time password)\b/i;
// Never strip arbitrary punctuation: 1.50 or 1,50 must not become 150 RWF.
const money = String.raw`([0-9][0-9, .\u00a0]*[0-9]|[0-9])`;
const receivedAmountPattern = new RegExp(
  String
    .raw`\b${incomingClause}\s*:?\s*(?:RWF|FRW)\s+${money}(?=\s+(?:from|by|on|at)\b|[.;](?![0-9])|$)|\b${incomingClause}\s*:?\s*${money}\s*(?:RWF|FRW)\b`,
  "gi",
);
const balancePattern = new RegExp(
  String
    .raw`\b(?:(?:your|new|available|current)\s+)*balance\s*(?:is|:|=)?\s*(?:(?:RWF|FRW)\s+${money}(?=[.;](?![0-9])|$|\s+[A-Za-z])|${money}\s*(?:RWF|FRW)\b)`,
  "gi",
);
const transactionPattern =
  /(?:financial\s+transaction\s+id|transaction\s+id|txn|txid|reference|ref)\s*[:#-]?\s*([A-Z0-9][A-Z0-9._/-]{3,63})/i;
const phone = String
  .raw`(?:\+?250\s*7[2389](?:[\s-]*\d){7}|07[2389](?:[\s-]*\d){7})`;
const senderPhonePattern = new RegExp(
  String
    .raw`\b(?:from|sender|payer)(?:\s+number)?\s*[:#-]?\s*(${phone})(?![\d\s-]*\d)`,
  "i",
);
const namedPayerPattern = new RegExp(
  String
    .raw`\bfrom\s+([^()\r\n]{2,120}?)\s*\(\s*(\*{3,}[0-9]{3}|${phone})\s*\)`,
  "i",
);
const collectIdPattern =
  /(?:collect\s*id|member\s*id|user\s*id)\s*[:#-]?\s*([0-9]{6})(?![0-9])/i;

export function normalizeMomoName(value: string): string {
  // easyMO identity contract: no fuzzy matching or accent removal.
  return value.trim().replace(/\s+/g, " ").toUpperCase();
}

export function parseIntegerRwf(value: string): number | null {
  const clean = value.trim().replace(/\u00a0/g, " ");
  if (
    !/^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,3}(?: [0-9]{3})+)$/.test(
      clean,
    )
  ) {
    return null;
  }
  const amount = Number(clean.replace(/[, ]/g, ""));
  return Number.isSafeInteger(amount) && amount >= 0 ? amount : null;
}

function oneAmount(body: string, pattern: RegExp): number | null {
  const matches = [...body.matchAll(pattern)];
  // Multiple receipt/balance clauses are ambiguous even with equal amounts.
  if (matches.length !== 1) return null;
  return parseIntegerRwf(matches[0][1] ?? matches[0][2]);
}

function receiptTime(body: string): string | null {
  const match = body.match(
    /\bat\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})(?!\d)/i,
  );
  if (!match) return null;
  const local = `${match[1]}T${match[2]}`;
  const calendar = new Date(`${local}Z`);
  if (
    !Number.isFinite(calendar.valueOf()) ||
    calendar.toISOString().slice(0, 19) !== local
  ) return null;
  // Rwanda receipts use UTC+02:00, never the host machine's timezone.
  return `${local}+02:00`;
}

export function parseMomoSms(sender: string, body: string): ParsedMomoSms {
  const text = `${sender}\n${body}`;
  const network = /airtel/i.test(text)
    ? "airtel_money"
    : /(?:mtn|momo|m[- ]money|mobile[- ]?money)/i.test(text)
    ? "mtn_momo"
    : "unknown";
  const amount = oneAmount(body, receivedAmountPattern);
  const incoming = amount != null && amount > 0 && !excludedPattern.test(body);
  const walletBalance = oneAmount(body, balancePattern);
  const transactionId =
    body.match(transactionPattern)?.[1]?.trim().replace(/[.,;:]+$/, "") ??
      null;
  const named = body.match(namedPayerPattern);
  const name = named?.[1]?.trim().replace(/\s+/g, " ") ?? null;
  const senderName = name && /\p{L}/u.test(name) && !/\p{Cc}/u.test(name)
    ? name
    : null;
  const masked = named?.[2]?.startsWith("*") ?? false;
  const senderPhone = (masked ? null : named?.[2]) ??
    body.match(senderPhonePattern)?.[1] ?? null;
  const cleanPhone = senderPhone?.replace(/[^0-9+]/g, "") ?? null;
  const last3 = masked ? named![2].slice(-3) : cleanPhone?.slice(-3) ?? null;
  const publicId = body.match(collectIdPattern)?.[1] ?? null;
  const legacyComplete = transactionId != null &&
    (cleanPhone != null || publicId != null);
  const maskedComplete = senderName != null && last3 != null &&
    walletBalance != null;
  const complete = incoming && network !== "unknown" &&
    (legacyComplete || maskedComplete);
  return {
    is_mobile_money_payment: incoming,
    network,
    direction: incoming ? "incoming" : "unknown",
    amount_rwf: amount,
    wallet_balance_rwf: walletBalance,
    currency: amount == null ? "unknown" : "RWF",
    transaction_id: transactionId,
    transaction_time: receiptTime(body),
    sender_phone: cleanPhone,
    sender_name: senderName,
    payer_last3: last3,
    detected_user_public_id: publicId,
    confidence: complete ? 0.96 : incoming ? 0.78 : 0.25,
  };
}
