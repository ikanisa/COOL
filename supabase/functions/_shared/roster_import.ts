export type RosterImportSource = "text" | "csv";

export type RosterCandidate = {
  source_row: number;
  member_name: string;
  momo_name: string;
  momo_number: string;
  confidence: number;
};

export type RosterPreviewRow = RosterCandidate & {
  issues: string[];
  ready: boolean;
};

export type RosterPreview = {
  rows: RosterPreviewRow[];
  row_count: number;
  ready_count: number;
  error_count: number;
  can_submit: boolean;
  normalized_rows: Array<{
    member_name: string;
    momo_name: string;
    momo_number: string;
  }>;
};

const encoder = new TextEncoder();
const headerAliases = {
  member_name: new Set([
    "member",
    "member name",
    "member_name",
    "display name",
    "display_name",
    "name",
  ]),
  momo_name: new Set([
    "momo name",
    "momo_name",
    "registered momo name",
    "registered_name",
    "account name",
  ]),
  momo_number: new Set([
    "momo number",
    "momo_number",
    "mobile money number",
    "mobile number",
    "phone",
    "phone number",
    "telephone",
  ]),
};

function cleanText(value: unknown): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
}

function normalizedHeader(value: string): string {
  return value.trim().toLowerCase().replace(/[\s_-]+/g, " ");
}

function headerKey(value: string): keyof typeof headerAliases | null {
  const normalized = normalizedHeader(value);
  for (const [key, aliases] of Object.entries(headerAliases)) {
    if (aliases.has(normalized)) return key as keyof typeof headerAliases;
  }
  return null;
}

function splitDelimitedLine(line: string, delimiter: string): string[] {
  const values: string[] = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        value += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === delimiter && !quoted) {
      values.push(value.trim());
      value = "";
    } else {
      value += character;
    }
  }
  if (quoted) throw new Error("Roster contains an unterminated quoted value");
  values.push(value.trim());
  return values;
}

function delimiterFor(line: string): string {
  const candidates = ["\t", ",", ";"];
  return candidates.sort((left, right) =>
    line.split(right).length - line.split(left).length
  )[0];
}

function looksLikePhone(value: string): boolean {
  return /(?:\+?250|0)?7\d{8}/.test(value.replace(/[\s()-]/g, ""));
}

export function canonicalRwandaMomoNumber(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const compact = value.trim().replace(/[\s().-]/g, "");
  const digits = compact.startsWith("+") ? compact.slice(1) : compact;
  if (/^07\d{8}$/.test(digits)) return `+250${digits.slice(1)}`;
  if (/^2507\d{8}$/.test(digits)) return `+${digits}`;
  return null;
}

export function parseRosterText(content: string): RosterCandidate[] {
  if (encoder.encode(content).byteLength > 512_000) {
    throw new Error("Roster text exceeds the 512 KB preview limit");
  }
  const lines = content.split(/\r?\n/).filter((line) => line.trim());
  if (!lines.length) throw new Error("Roster has no member rows");
  if (lines.length > 501) {
    throw new Error("Roster preview is limited to 500 members");
  }
  const delimiter = delimiterFor(lines[0]);
  const first = splitDelimitedLine(lines[0], delimiter);
  const mappedHeaders = first.map(headerKey);
  const hasHeader = mappedHeaders.some((value) => value != null) &&
    !first.some(looksLikePhone);
  const indices = {
    member_name: hasHeader ? mappedHeaders.indexOf("member_name") : 0,
    momo_name: hasHeader ? mappedHeaders.indexOf("momo_name") : 1,
    momo_number: hasHeader ? mappedHeaders.indexOf("momo_number") : 2,
  };
  if (hasHeader && indices.momo_number < 0) {
    throw new Error("Roster header must include a MoMo number column");
  }
  const dataLines = hasHeader ? lines.slice(1) : lines;
  if (!dataLines.length) throw new Error("Roster has no member rows");
  return dataLines.map((line, index) => {
    const values = splitDelimitedLine(line, delimiter);
    const momoName = cleanText(
      indices.momo_name >= 0 ? values[indices.momo_name] : values[0],
    );
    return {
      source_row: index + (hasHeader ? 2 : 1),
      member_name: cleanText(
        indices.member_name >= 0 ? values[indices.member_name] : momoName,
      ) || momoName,
      momo_name: momoName,
      momo_number: cleanText(values[indices.momo_number]),
      confidence: 1,
    };
  });
}

export function normalizeRosterCandidates(value: unknown): RosterPreview {
  if (!Array.isArray(value) || value.length < 1 || value.length > 500) {
    throw new Error("Roster must contain between 1 and 500 candidate rows");
  }
  const seen = new Map<string, number>();
  const rows: RosterPreviewRow[] = value.map((raw, index) => {
    if (typeof raw !== "object" || raw == null || Array.isArray(raw)) {
      return {
        source_row: index + 1,
        member_name: "",
        momo_name: "",
        momo_number: "",
        confidence: 0,
        issues: ["Row is not a member record"],
        ready: false,
      };
    }
    const item = raw as Record<string, unknown>;
    const memberName = cleanText(item.member_name ?? item.name);
    const momoName = cleanText(item.momo_name ?? item.registered_name);
    const phone = canonicalRwandaMomoNumber(item.momo_number ?? item.phone);
    const sourceRow =
      Number.isInteger(item.source_row) && Number(item.source_row) > 0
        ? Number(item.source_row)
        : index + 1;
    const confidenceValue = Number(item.confidence ?? 0);
    const confidence = Number.isFinite(confidenceValue)
      ? Math.max(0, Math.min(1, confidenceValue))
      : 0;
    const issues: string[] = [];
    if (memberName.length < 2 || memberName.length > 120) {
      issues.push("Member name must contain 2 to 120 characters");
    }
    if (momoName.length < 2 || momoName.length > 120) {
      issues.push("Registered MoMo name must contain 2 to 120 characters");
    }
    if (/[\u0000-\u001f\u007f]/.test(memberName + momoName)) {
      issues.push("Names cannot contain control characters");
    }
    if (/^[=+\-@]/.test(memberName) || /^[=+\-@]/.test(momoName)) {
      issues.push("Names cannot begin with spreadsheet formula characters");
    }
    if (!phone) issues.push("Enter a valid full Rwanda MoMo number");
    if (confidence < 0.8) issues.push("Extraction confidence is below 80%");
    if (phone) {
      const firstRow = seen.get(phone);
      if (firstRow != null) {
        issues.push(`MoMo number duplicates source row ${firstRow}`);
      } else {
        seen.set(phone, sourceRow);
      }
    }
    return {
      source_row: sourceRow,
      member_name: memberName,
      momo_name: momoName,
      momo_number: phone ?? cleanText(item.momo_number ?? item.phone),
      confidence,
      issues,
      ready: issues.length === 0,
    };
  });
  const readyRows = rows.filter((row) => row.ready);
  return {
    rows,
    row_count: rows.length,
    ready_count: readyRows.length,
    error_count: rows.length - readyRows.length,
    can_submit: readyRows.length === rows.length,
    normalized_rows: readyRows.map((row) => ({
      member_name: row.member_name,
      momo_name: row.momo_name,
      momo_number: row.momo_number,
    })),
  };
}
