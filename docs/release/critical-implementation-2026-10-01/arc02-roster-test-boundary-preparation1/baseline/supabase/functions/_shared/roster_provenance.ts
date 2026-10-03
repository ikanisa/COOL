import type { RosterCandidate } from "./roster_import.ts";
import { PublicError, uuid } from "./production_contract.ts";
import { decodeRosterFile, validateRosterFile } from "./roster_file_policy.ts";

export const ROSTER_IMPORT_CONTRACT = 1;
export const ROSTER_AI_CONSENT = "roster-ai-extraction-v1";
export const ROSTER_PROMPT_VERSION = "roster-extraction-v1";
export const MAX_ROSTER_REQUEST_BYTES = 8 * 1024 * 1024;
export const MAX_ROSTER_TEXT_BYTES = 512_000;
export type RosterSourceKind =
  | "text"
  | "csv"
  | "txt"
  | "xlsx"
  | "pdf"
  | "image";
export type RosterSource = {
  requestId: string;
  kind: RosterSourceKind;
  bytes: Uint8Array;
  filename: string | null;
  mime: string;
  detected: string;
  content: string | null;
  derived: Uint8Array | null;
  ai: boolean;
  base64: string | null;
};
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
export function rosterFields(
  value: Record<string, unknown>,
  allowed: string[],
): void {
  if (Object.keys(value).some((key) => !allowed.includes(key))) {
    throw new PublicError("roster_unexpected_field");
  }
}
function text(value: unknown, max: number): string {
  if (
    typeof value !== "string" || !value.trim() ||
    encoder.encode(value).length > max ||
    decoder.decode(encoder.encode(value)) !== value
  ) {
    throw new PublicError("roster_text_invalid");
  }
  return value;
}
function utf8(bytes: Uint8Array): string {
  if (bytes.length > MAX_ROSTER_TEXT_BYTES) {
    throw new PublicError("roster_text_invalid");
  }
  try {
    return text(decoder.decode(bytes), MAX_ROSTER_TEXT_BYTES);
  } catch {
    throw new PublicError("roster_text_invalid");
  }
}
/** No ZIP inflation or workbook parsing. Only bounded outer ZIP framing is
 * checked here; the provided TSV remains explicitly client-derived. */
function zipFraming(bytes: Uint8Array): void {
  if (
    bytes.length < 22 || bytes[0] !== 0x50 || bytes[1] !== 0x4b ||
    bytes[2] !== 3 || bytes[3] !== 4
  ) throw new PublicError("roster_type_mismatch");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  for (let p = bytes.length - 22; p >= Math.max(0, bytes.length - 65557); p--) {
    if (view.getUint32(p, true) !== 0x06054b50) continue;
    if (
      p + 22 + view.getUint16(p + 20, true) !== bytes.length ||
      view.getUint16(p + 4, true) !== 0 || view.getUint16(p + 6, true) !== 0 ||
      !view.getUint16(p + 10, true) || view.getUint16(p + 10, true) === 65535 ||
      view.getUint16(p + 8, true) !== view.getUint16(p + 10, true) ||
      view.getUint32(p + 16, true) + view.getUint32(p + 12, true) !== p
    ) throw new PublicError("roster_invalid_file");
    return;
  }
  throw new PublicError("roster_invalid_file");
}
export function readRosterSource(
  payload: Record<string, unknown>,
): RosterSource {
  if (payload.contract_version !== ROSTER_IMPORT_CONTRACT) {
    throw new PublicError("roster_contract_invalid");
  }
  const requestId = uuid(payload.request_id, "roster_request_invalid");
  const base = ["contract_version", "request_id", "source_type"];
  if (payload.source_type === "text") {
    rosterFields(payload, [...base, "content"]);
    const content = text(payload.content, MAX_ROSTER_TEXT_BYTES);
    return {
      requestId,
      kind: "text",
      bytes: encoder.encode(content),
      filename: "pasted-roster.txt",
      mime: "text/plain",
      detected: "utf8_text",
      content,
      derived: null,
      ai: false,
      base64: null,
    };
  }
  const kind = payload.source_type;
  if (!["csv", "txt", "xlsx", "pdf", "image"].includes(String(kind))) {
    throw new PublicError("roster_source_invalid");
  }
  const ai = kind === "pdf" || kind === "image";
  rosterFields(payload, [
    ...base,
    "filename",
    "mime_type",
    "content_base64",
    ...(ai
      ? ["ai_consent", "consent_version"]
      : kind === "xlsx"
      ? ["derived_content"]
      : []),
  ]);
  const filename = text(payload.filename, 160);
  if (!/^[A-Za-z0-9][A-Za-z0-9._ -]{0,159}$/.test(filename)) {
    throw new PublicError("roster_filename_invalid");
  }
  const mime = text(payload.mime_type, 128).trim().toLowerCase();
  const expected = kind === "csv"
    ? ["text/csv"]
    : kind === "txt"
    ? ["text/plain"]
    : kind === "xlsx"
    ? ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"]
    : kind === "pdf"
    ? ["application/pdf"]
    : ["image/png", "image/jpeg", "image/webp"];
  if (!expected.includes(mime)) throw new PublicError("roster_type_mismatch");
  const bytes = decodeRosterFile(payload.content_base64);
  let content: string | null = null,
    derived: Uint8Array | null = null,
    detected = mime;
  if (kind === "csv" || kind === "txt") {
    content = utf8(bytes);
    detected = kind === "csv" ? "utf8_csv" : "utf8_text";
  } else if (kind === "xlsx") {
    zipFraming(bytes);
    content = text(payload.derived_content, MAX_ROSTER_TEXT_BYTES);
    derived = encoder.encode(content);
    detected = "zip_container";
  } else {
    validateRosterFile(bytes, mime);
    if (
      payload.ai_consent !== true ||
      payload.consent_version !== ROSTER_AI_CONSENT
    ) throw new PublicError("roster_ai_consent_required");
  }
  return {
    requestId,
    kind: kind as RosterSourceKind,
    bytes,
    filename,
    mime,
    detected,
    content,
    derived,
    ai,
    base64: payload.content_base64 as string,
  };
}
export async function rosterSha256(bytes: Uint8Array): Promise<string> {
  const copy = new Uint8Array(bytes.length);
  copy.set(bytes);
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", copy.buffer))]
    .map((v) => v.toString(16).padStart(2, "0")).join("");
}
/** This is called only AFTER Auth.getUser has verified the supplied bearer. */
export function rosterSession(
  authorization: string | null,
  verifiedUserId: string,
): { actorId: string; sessionId: string } {
  try {
    if (
      !authorization || authorization.length > 16_384 ||
      !/^Bearer [^ ]+$/i.test(authorization)
    ) throw new Error();
    const parts = authorization.slice(7).split(".");
    if (parts.length !== 3) throw new Error();
    const raw = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(
      decoder.decode(
        Uint8Array.from(
          atob(raw.padEnd(Math.ceil(raw.length / 4) * 4, "=")),
          (c) => c.charCodeAt(0),
        ),
      ),
    );
    const actorId = uuid(verifiedUserId, "authentication_required");
    if (claims.sub !== actorId || claims.role !== "authenticated") {
      throw new Error();
    }
    return {
      actorId,
      sessionId: uuid(claims.session_id, "authentication_required"),
    };
  } catch {
    throw new PublicError("authentication_required", 401);
  }
}

/** Upper byte bound for PostgreSQL JSONB text for our exact flat candidate shape.
 * JSONB inserts separator spaces and expands exponent-form confidence numbers.
 * This is a resource bound, never a replacement for the SQL-issued row hash. */
export function rosterCandidateJsonbBytes(rows: RosterCandidate[]): number {
  let bytes = encoder.encode(JSON.stringify(rows)).length +
    Math.max(0, 10 * rows.length - 1);
  for (const row of rows) {
    const serialized = JSON.stringify(row.confidence);
    const match = /^([0-9])(?:\.([0-9]+))?e-([0-9]+)$/.exec(serialized);
    if (match) {
      const expandedLength = 1 + Number(match[3]) + match[1].length +
        (match[2]?.length ?? 0);
      bytes += Math.max(0, expandedLength - serialized.length);
    }
  }
  return bytes;
}
