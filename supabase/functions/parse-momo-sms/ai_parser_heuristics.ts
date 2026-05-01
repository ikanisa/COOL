import type {
  HeuristicParseResult,
  ParsedSms,
  RawSmsRecord,
} from "./ai_parser.ts";

export function tryHeuristicParse(
  record: RawSmsRecord,
): HeuristicParseResult | null {
  const body = collapseWhitespace(record.sms_body);
  if (!body) {
    return null;
  }

  const debitPayment = tryParseDebitPayment(record, body);
  if (debitPayment) {
    return debitPayment;
  }

  const inboundTransfer = tryParseInboundTransfer(record, body);
  if (inboundTransfer) {
    return inboundTransfer;
  }

  return null;
}

function tryParseDebitPayment(
  record: RawSmsRecord,
  body: string,
): HeuristicParseResult | null {
  const paymentMatch = body.match(
    /(?:payment of|your payment of)\s+([0-9][0-9,\s.]*)\s*RWF(?:\s+to\s+(.+?))?\s+(?:was\s+)?(confirmed|completed)\b/i,
  );
  if (!paymentMatch) {
    return null;
  }

  const amount = parseMoneyValue(paymentMatch[1]);
  if (amount == null || amount <= 0) {
    return null;
  }

  const payeeSegment = paymentMatch[2]?.trim() ?? null;
  const merchantCode = extractMerchantCode(payeeSegment ?? body);
  const payeeName = merchantCode ? null : cleanupCounterpartyName(payeeSegment);
  const txId = extractReference(body) ?? record.detected_tx_id;
  const feeAmount = extractLabeledAmount(body, /fee/i) ?? 0;
  const balanceAfter = extractBalance(body);
  const txDateTime = extractBodyDateTime(body) ?? record.sms_received_at;
  const txDate = extractDatePart(txDateTime);
  const txTime = extractTimePart(txDateTime);
  const summaryTarget = merchantCode
    ? `merchant code ${merchantCode}`
    : payeeName ?? "recipient";

  const parsed: ParsedSms = {
    parse_status: "parsed",
    confidence: payeeSegment ? 0.95 : 0.88,
    tx_direction: "debit",
    tx_type: "payment",
    tx_category: merchantCode ? "merchant_payment" : "payment",
    cashflow_bucket: "expense",
    momo_tx_id: txId,
    amount,
    currency: "RWF",
    tx_date: txDate,
    tx_time: txTime,
    tx_datetime_iso: txDateTime,
    payer_name: null,
    payer_number_last3: null,
    payer_number_full: null,
    payee_name: payeeName,
    payee_number_or_code: merchantCode,
    merchant_code: merchantCode,
    fee_amount: feeAmount,
    balance_after: balanceAfter,
    counterparty_name: payeeName ??
      (merchantCode ? `Merchant code ${merchantCode}` : null),
    ai_summary: `Paid ${formatMoney(amount)} RWF to ${summaryTarget}.`,
    recurring_pattern_hint: "unknown",
    narrative: body,
    notes: "Parsed via deterministic MTN payment heuristic.",
  };

  return {
    model: "momo-regex-v1",
    parsed,
    requestPayload: {
      strategy: "debit_payment_confirmation",
      sender: record.sender,
    },
    responsePayload: parsed as unknown as Record<string, unknown>,
  };
}

function tryParseInboundTransfer(
  record: RawSmsRecord,
  body: string,
): HeuristicParseResult | null {
  const receivedMatch = body.match(
    /you have received\s+([0-9][0-9,\s.]*)\s*RWF\s+from\s+(.+?)\s+\(([^)]+)\)\s+at\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})/i,
  );
  if (!receivedMatch) {
    return null;
  }

  const amount = parseMoneyValue(receivedMatch[1]);
  if (amount == null || amount <= 0) {
    return null;
  }

  const payerName = cleanupCounterpartyName(receivedMatch[2]);
  const payerMask = receivedMatch[3] ?? "";
  const txDateTime = toIsoDateTime(receivedMatch[4], receivedMatch[5]) ??
    record.sms_received_at;
  const balanceAfter = extractBalance(body);
  const txId = extractReference(body) ?? record.detected_tx_id;
  const parsed: ParsedSms = {
    parse_status: "parsed",
    confidence: 0.95,
    tx_direction: "credit",
    tx_type: "received",
    tx_category: "transfer_in",
    cashflow_bucket: "income",
    momo_tx_id: txId,
    amount,
    currency: "RWF",
    tx_date: receivedMatch[4],
    tx_time: receivedMatch[5],
    tx_datetime_iso: txDateTime,
    payer_name: payerName,
    payer_number_last3: extractLastThreeDigits(payerMask),
    payer_number_full: null,
    payee_name: null,
    payee_number_or_code: null,
    merchant_code: null,
    fee_amount: 0,
    balance_after: balanceAfter,
    counterparty_name: payerName,
    ai_summary: `Received ${formatMoney(amount)} RWF from ${
      payerName ?? "sender"
    }.`,
    recurring_pattern_hint: "unknown",
    narrative: body,
    notes: "Parsed via deterministic MTN inbound transfer heuristic.",
  };

  return {
    model: "momo-regex-v1",
    parsed,
    requestPayload: {
      strategy: "credit_transfer_confirmation",
      sender: record.sender,
    },
    responsePayload: parsed as unknown as Record<string, unknown>,
  };
}

function collapseWhitespace(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

function parseMoneyValue(value: string | null | undefined): number | null {
  if (!value) {
    return null;
  }
  const digits = value.replaceAll(/[^\d]/g, "");
  if (!digits) {
    return null;
  }
  const parsed = Number.parseInt(digits, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function extractLabeledAmount(
  body: string,
  label: RegExp,
): number | null {
  const match = body.match(
    new RegExp(`${label.source}\\s*:?\\s*([0-9][0-9,\\s.]*)\\s*RWF`, "i"),
  );
  return parseMoneyValue(match?.[1]);
}

function extractBalance(body: string): number | null {
  const match = body.match(
    /(?:balance after payment|new balance|available balance|balance)\s*:?[\s]*([0-9][0-9,\s.]*)\s*RWF/i,
  );
  return parseMoneyValue(match?.[1]);
}

function extractMerchantCode(value: string): string | null {
  const match = value.match(/merchant code\s+([0-9]{5,6})/i);
  return match?.[1] ?? null;
}

function cleanupCounterpartyName(
  value: string | null | undefined,
): string | null {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }
  const cleaned = trimmed
    .replace(/\s+(?:was\s+)?(?:confirmed|completed)$/i, "")
    .replace(/\s+on\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?$/i, "")
    .trim();
  return cleaned.length > 0 ? cleaned : null;
}

function extractReference(body: string): string | null {
  const match = body.match(
    /\b(?:tx(?:n)?\s*id|ft\s*id|transaction\s*id)\s*[:#]?\s*([A-Z0-9-]+)/i,
  );
  return match?.[1]?.trim() ?? null;
}

function extractBodyDateTime(body: string): string | null {
  const match = body.match(
    /(?:confirmed|completed)\s+on\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)/i,
  );
  if (!match) {
    return null;
  }

  return toIsoDateTime(match[1], match[2]);
}

function toIsoDateTime(datePart: string, timePart: string): string | null {
  const normalizedTime = timePart.length === 5 ? `${timePart}:00` : timePart;
  const candidate = `${datePart}T${normalizedTime}.000Z`;
  return Number.isNaN(Date.parse(candidate)) ? null : candidate;
}

function extractDatePart(value: string | null | undefined): string | null {
  if (!value) {
    return null;
  }
  const match = value.match(/^(\d{4}-\d{2}-\d{2})/);
  return match?.[1] ?? null;
}

function extractTimePart(value: string | null | undefined): string | null {
  if (!value) {
    return null;
  }
  const match = value.match(/T(\d{2}:\d{2}:\d{2})/);
  return match?.[1] ?? null;
}

function extractLastThreeDigits(
  value: string | null | undefined,
): string | null {
  if (!value) {
    return null;
  }
  const digits = value.replaceAll(/\D/g, "");
  return digits.length >= 3 ? digits.slice(-3) : null;
}

function formatMoney(value: number): string {
  return new Intl.NumberFormat("en-RW", {
    maximumFractionDigits: 0,
  }).format(value);
}
