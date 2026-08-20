export type EvidenceDirection = "incoming" | "outgoing" | "unknown";

export type ParsedBankEvidence = {
  direction: EvidenceDirection;
  amount_minor: number | null;
  currency: "EUR" | "unknown";
  bank_transaction_id: string | null;
  end_to_end_id: string | null;
  transfer_reference: string | null;
  payer_name: string | null;
  payer_account_last4: string | null;
  occurred_at: string;
  confidence: number;
  parser_name: "collect.bank_rules.v1";
  parser_schema_version: "collect.bank_evidence.v1";
  signals: string[];
};

const incomingPattern = /\b(received|incoming|credited|credit received|payment received|transfer received|funds received|virement re[cç]u|paiement re[cç]u|eingang|gutschrift)\b/i;
const outgoingPattern = /\b(sent|outgoing|debited|debit|paid to|transfer sent|payment made|virement envoy[eé]|zahlung gesendet)\b/i;
const failedPattern = /\b(failed|declined|rejected|cancelled|canceled|reversed|returned|pending|unsuccessful)\b/i;
const successPattern = /\b(successful|completed|received|credited|booked|settled|executed)\b/i;
const collectReferencePattern = /\bCOL-[A-Z0-9]{10}\b/i;

function cleanId(value: string | undefined): string | null {
  if (!value) return null;
  const clean = value.trim().replace(/[^A-Za-z0-9./_-]/g, "").toUpperCase();
  return clean.length >= 4 && clean.length <= 128 ? clean : null;
}

function parseEuroAmount(raw: string): number | null {
  const compact = raw.replace(/[\s'’]/g, "");
  const lastComma = compact.lastIndexOf(",");
  const lastDot = compact.lastIndexOf(".");
  let normalized = compact;
  if (lastComma >= 0 && lastDot >= 0) {
    const decimal = lastComma > lastDot ? "," : ".";
    normalized = decimal === ","
      ? compact.replace(/\./g, "").replace(",", ".")
      : compact.replace(/,/g, "");
  } else if (lastComma >= 0) {
    const decimals = compact.length - lastComma - 1;
    normalized = decimals === 2
      ? compact.replace(/\./g, "").replace(",", ".")
      : compact.replace(/,/g, "");
  } else if (lastDot >= 0) {
    const decimals = compact.length - lastDot - 1;
    normalized = decimals === 2 ? compact.replace(/,/g, "") : compact.replace(/\./g, "");
  }
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const minor = Math.round(Number(normalized) * 100);
  return Number.isSafeInteger(minor) && minor > 0 ? minor : null;
}

function extractAmount(text: string): number | null {
  const patterns = [
    /(?:EUR|€)\s*([0-9][0-9\s'’.,]*)/i,
    /([0-9][0-9\s'’.,]*)\s*(?:EUR|€)\b/i,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    const amount = match ? parseEuroAmount(match[1]) : null;
    if (amount != null) return amount;
  }
  return null;
}

function extractOccurredAt(text: string, receivedAt: string): string {
  const iso = text.match(/\b(20\d{2}-\d{2}-\d{2}[T ][0-2]\d:[0-5]\d(?::[0-5]\d)?(?:Z|[+-][0-2]\d:?\d{2})?)\b/);
  if (iso) {
    const parsed = new Date(iso[1].replace(" ", "T"));
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString();
  }
  return new Date(receivedAt).toISOString();
}

function extractPayerName(text: string): string | null {
  const match = text.match(/\b(?:from|payer|sender)\s*[:\-]\s*([\p{L}][\p{L} .'-]{1,78})(?=\s*(?:[,;]|\b(?:IBAN|account|reference|ref|amount|EUR|€)\b|$))/iu);
  return match ? match[1].trim().replace(/\s+/g, " ").slice(0, 80) : null;
}

function extractLast4(text: string): string | null {
  const match = text.match(/\b(?:account|a\/c|iban)(?:\s+(?:ending|last))?\s*(?:in|:|-)?\s*(?:[*xX•]+)?([A-Z0-9]{4})\b/i);
  return match ? match[1].toUpperCase() : null;
}

export function parseBankEvidence(
  rawSender: string,
  rawBody: string,
  receivedAt: string,
): ParsedBankEvidence {
  const text = `${rawSender}\n${rawBody}`.replace(/\0/g, " ");
  const hasFailedSignal = failedPattern.test(text);
  const incoming = incomingPattern.test(text);
  const outgoing = outgoingPattern.test(text);
  const direction: EvidenceDirection = hasFailedSignal
    ? "unknown"
    : incoming && !outgoing
    ? "incoming"
    : outgoing && !incoming
    ? "outgoing"
    : "unknown";
  const amount = extractAmount(text);
  const reference = text.match(collectReferencePattern)?.[0].toUpperCase() ?? null;
  const bankId = cleanId(text.match(/\b(?:transaction(?:\s+id)?|bank\s+reference|txn)\s*[:#-]\s*([A-Z0-9./_-]{4,128})/i)?.[1]);
  const endToEndId = cleanId(text.match(/\b(?:end[- ]to[- ]end(?:\s+id)?|e2e(?:\s+id)?)\s*[:#-]\s*([A-Z0-9./_-]{4,128})/i)?.[1]);
  const hasSuccessSignal = successPattern.test(text) && !hasFailedSignal;
  const signals: string[] = [];
  if (direction === "incoming") signals.push("incoming");
  if (amount != null) signals.push("amount_eur");
  if (reference != null) signals.push("collect_reference");
  if (bankId != null || endToEndId != null) signals.push("bank_identifier");
  if (hasSuccessSignal) signals.push("success");
  const confidence = Math.round(Math.min(1,
    (direction === "incoming" ? 0.25 : 0) +
      (amount != null ? 0.25 : 0) +
      (reference != null ? 0.2 : 0) +
      (bankId != null || endToEndId != null ? 0.2 : 0) +
      (hasSuccessSignal ? 0.1 : 0)) * 100) / 100;

  return {
    direction,
    amount_minor: amount,
    currency: amount == null ? "unknown" : "EUR",
    bank_transaction_id: bankId,
    end_to_end_id: endToEndId,
    transfer_reference: reference,
    payer_name: extractPayerName(text),
    payer_account_last4: extractLast4(text),
    occurred_at: extractOccurredAt(text, receivedAt),
    confidence,
    parser_name: "collect.bank_rules.v1",
    parser_schema_version: "collect.bank_evidence.v1",
    signals,
  };
}
