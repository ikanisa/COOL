export type BankStatementLine = {
  bank_transaction_id: string | null;
  end_to_end_id: string | null;
  transfer_reference: string | null;
  payer_name: string | null;
  amount_minor: number;
  currency: "EUR";
  booked_at: string;
  value_date: string;
};

function parseAmountMinor(value: unknown): number {
  if (typeof value === "number") {
    if (!Number.isFinite(value) || value <= 0) throw new Error("Statement amount is invalid");
    const minor = Math.round(value * 100);
    if (!Number.isSafeInteger(minor)) throw new Error("Statement amount is too large");
    return minor;
  }
  if (typeof value !== "string") throw new Error("Statement amount is required");
  let compact = value.trim().replace(/[€\s'’]/g, "");
  if (!compact || compact.startsWith("-")) throw new Error("Only incoming positive amounts are supported");
  const comma = compact.lastIndexOf(",");
  const dot = compact.lastIndexOf(".");
  if (comma >= 0 && dot >= 0) {
    compact = comma > dot ? compact.replace(/\./g, "").replace(",", ".") : compact.replace(/,/g, "");
  } else if (comma >= 0) {
    compact = compact.length - comma - 1 === 2 ? compact.replace(",", ".") : compact.replace(/,/g, "");
  }
  if (!/^\d+(?:\.\d{1,2})?$/.test(compact)) throw new Error("Statement amount is invalid");
  const minor = Math.round(Number(compact) * 100);
  if (!Number.isSafeInteger(minor) || minor <= 0) throw new Error("Statement amount is invalid");
  return minor;
}

function normalizedDate(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${field} is required`);
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error(`${field} is invalid`);
  return date.toISOString();
}

function dateOnly(value: unknown, fallbackIso?: string): string {
  const raw = typeof value === "string" && value.trim() ? value : fallbackIso;
  if (!raw) throw new Error("value_date is required");
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) throw new Error("value_date is invalid");
  return date.toISOString().slice(0, 10);
}

function clean(value: unknown): string | null {
  if (value == null) return null;
  const text = String(value).trim();
  return text ? text.slice(0, 160) : null;
}

function normalizeObject(value: Record<string, unknown>): BankStatementLine {
  const currency = String(value.currency ?? "EUR").toUpperCase();
  if (currency !== "EUR") throw new Error("Only EUR statement lines are supported");
  const bookedAt = normalizedDate(value.booked_at ?? value.booking_date, "booked_at");
  const amountMinor = value.amount_minor == null
    ? parseAmountMinor(value.amount)
    : Number(value.amount_minor);
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
    throw new Error("amount_minor must be a positive integer");
  }
  const referenceText = clean(value.transfer_reference ?? value.reference);
  const collectReference = referenceText?.match(/\bCOL-[A-Z0-9]{10}\b/i)?.[0].toUpperCase() ?? null;
  return {
    bank_transaction_id: clean(value.bank_transaction_id ?? value.transaction_id)?.toUpperCase() ?? null,
    end_to_end_id: clean(value.end_to_end_id ?? value.e2e_id)?.toUpperCase() ?? null,
    transfer_reference: collectReference,
    payer_name: clean(value.payer_name ?? value.counterparty_name),
    amount_minor: amountMinor,
    currency: "EUR",
    booked_at: bookedAt,
    value_date: dateOnly(value.value_date, bookedAt),
  };
}

function splitCsvLine(line: string): string[] {
  const result: string[] = [];
  let current = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (char === '"') {
      if (quoted && line[index + 1] === '"') {
        current += '"';
        index += 1;
      } else quoted = !quoted;
    } else if (char === "," && !quoted) {
      result.push(current.trim());
      current = "";
    } else current += char;
  }
  result.push(current.trim());
  return result;
}

function parseCsv(content: string): BankStatementLine[] {
  const rows = content.split(/\r?\n/).filter((line) => line.trim());
  if (rows.length < 2) throw new Error("CSV statement has no data lines");
  const headers = splitCsvLine(rows[0]).map((header) => header.trim().toLowerCase());
  return rows.slice(1).map((row) => {
    const values = splitCsvLine(row);
    const record: Record<string, unknown> = {};
    headers.forEach((header, index) => record[header] = values[index] ?? "");
    return normalizeObject(record);
  });
}

function parseMt940(content: string): BankStatementLine[] {
  const chunks = content.split(/(?=:61:)/).filter((chunk) => chunk.startsWith(":61:"));
  return chunks.map((chunk) => {
    const line61 = chunk.match(/^:61:(\d{6})(\d{4})?[CD]([0-9,]+)[A-Z]?(?:N[A-Z0-9]{3})?([^\r\n]*)/m);
    if (!line61) throw new Error("Unsupported MT940 transaction line");
    const year = 2000 + Number(line61[1].slice(0, 2));
    const month = line61[1].slice(2, 4);
    const day = line61[1].slice(4, 6);
    const valueDate = `${year.toString().padStart(4, "0")}-${month}-${day}`;
    const details = chunk.match(/:86:([^]*?)(?=\r?\n:\d{2}[A-Z]?:|$)/)?.[1]?.replace(/\s+/g, " ") ?? "";
    const reference = details.match(/\bCOL-[A-Z0-9]{10}\b/i)?.[0] ?? null;
    return normalizeObject({
      bank_transaction_id: line61[4],
      end_to_end_id: details.match(/(?:EREF|E2E)[+:]?([A-Z0-9./_-]+)/i)?.[1],
      transfer_reference: reference,
      payer_name: details.match(/(?:NAME|SVWZ)[+:]([^+?]{2,80})/i)?.[1],
      amount: line61[3],
      currency: "EUR",
      booked_at: `${valueDate}T12:00:00Z`,
      value_date: valueDate,
    });
  });
}

function decodeXml(value: string): string {
  return value.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&apos;/g, "'");
}

function xmlValue(block: string, tag: string): string | null {
  const match = block.match(new RegExp(`<[^>]*${tag}[^>]*>([^<]*)<\\/[^>]*${tag}>`, "i"));
  return match ? decodeXml(match[1].trim()) : null;
}

function parseCamt053(content: string): BankStatementLine[] {
  const entries = content.match(/<(?:\w+:)?Ntry\b[^>]*>[\s\S]*?<\/(?:\w+:)?Ntry>/gi) ?? [];
  if (!entries.length) throw new Error("CAMT.053 statement has no entries");
  return entries.filter((entry) => xmlValue(entry, "CdtDbtInd")?.toUpperCase() === "CRDT").map((entry) => {
    const amountTag = entry.match(/<(?:\w+:)?Amt\b[^>]*Ccy=["']([^"']+)["'][^>]*>([^<]+)</i);
    const booked = xmlValue(entry, "BookgDt") ?? entry.match(/<(?:\w+:)?BookgDt>[\s\S]*?<(?:\w+:)?Dt>([^<]+)/i)?.[1];
    const value = xmlValue(entry, "ValDt") ?? entry.match(/<(?:\w+:)?ValDt>[\s\S]*?<(?:\w+:)?Dt>([^<]+)/i)?.[1];
    const reference = xmlValue(entry, "Ustrd") ?? xmlValue(entry, "AddtlNtryInf");
    return normalizeObject({
      bank_transaction_id: xmlValue(entry, "AcctSvcrRef"),
      end_to_end_id: xmlValue(entry, "EndToEndId"),
      transfer_reference: reference,
      payer_name: xmlValue(entry, "Nm"),
      amount: amountTag?.[2],
      currency: amountTag?.[1],
      booked_at: `${booked}T12:00:00Z`,
      value_date: value,
    });
  });
}

export function parseBankStatement(format: string, content: string): BankStatementLine[] {
  if (new TextEncoder().encode(content).byteLength > 2_000_000) {
    throw new Error("Statement exceeds the 2 MB ingestion limit");
  }
  const normalizedFormat = format.toLowerCase().replace(/[^a-z0-9.]/g, "");
  let lines: BankStatementLine[];
  if (normalizedFormat === "json") {
    const parsed = JSON.parse(content);
    const values = Array.isArray(parsed) ? parsed : parsed?.lines;
    if (!Array.isArray(values)) throw new Error("JSON statement requires a lines array");
    lines = values.map((value) => {
      if (typeof value !== "object" || value == null || Array.isArray(value)) {
        throw new Error("JSON statement line is invalid");
      }
      return normalizeObject(value as Record<string, unknown>);
    });
  } else if (normalizedFormat === "csv") lines = parseCsv(content);
  else if (normalizedFormat === "mt940" || normalizedFormat === "sta") lines = parseMt940(content);
  else if (normalizedFormat === "camt053" || normalizedFormat === "xml") lines = parseCamt053(content);
  else throw new Error("Supported statement formats are CSV, JSON, MT940, and CAMT.053");
  if (!lines.length || lines.length > 5000) {
    throw new Error("Statement must contain between 1 and 5000 incoming EUR lines");
  }
  return lines;
}

