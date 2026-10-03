import { PublicError } from "./production_contract.ts";
import type { RosterCandidate } from "./roster_import.ts";

export const MAX_ROSTER_PROVIDER_BYTES = 1_048_576;
export const MAX_ROSTER_OUTPUT_BYTES = 512_000;
export const MAX_ROSTER_ROWS = 500;
export const MAX_ROSTER_SOURCE_ROW = 2_147_483_647;
export const MAX_ROSTER_NAME_CHARACTERS = 120;
export const MAX_ROSTER_PHONE_CHARACTERS = 32;
const encoder = new TextEncoder();

function invalid(): never {
  throw new PublicError("roster_provider_response_invalid", 502);
}
function tooLarge(): never {
  throw new PublicError("roster_provider_response_too_large", 502);
}
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}
function fields(
  value: Record<string, unknown>,
  allowed: string[],
  required = allowed,
): void {
  if (
    Object.keys(value).some((key) => !allowed.includes(key)) ||
    required.some((key) => !Object.hasOwn(value, key))
  ) invalid();
}
function text(value: unknown, maximumBytes: number, nonempty = true): string {
  if (typeof value !== "string" || (nonempty && !value.trim())) invalid();
  if (
    value.length > maximumBytes || encoder.encode(value).length > maximumBytes
  ) tooLarge();
  return value;
}

/** Secondary bounds also cover direct callers; the HTTP body is bounded first. */
function boundedTree(value: unknown): void {
  const pending: Array<[unknown, number]> = [[value, 0]];
  const seen = new Set<object>();
  let nodes = 0, bytes = 0;
  while (pending.length) {
    const [current, depth] = pending.pop()!;
    if (++nodes > 20_000 || depth > 16) tooLarge();
    if (typeof current === "string") {
      if (current.length > MAX_ROSTER_PROVIDER_BYTES) tooLarge();
      bytes += encoder.encode(current).length;
    } else if (typeof current === "number") {
      if (!Number.isFinite(current)) invalid();
    } else if (current && typeof current === "object") {
      if (seen.has(current)) invalid();
      seen.add(current);
      const children = Object.entries(current);
      if (children.length > 20_000 - nodes - pending.length) tooLarge();
      for (const [key, child] of children) {
        bytes += encoder.encode(key).length;
        pending.push([child, depth + 1]);
      }
    } else if (current !== null && typeof current !== "boolean") invalid();
    if (bytes > MAX_ROSTER_PROVIDER_BYTES) tooLarge();
  }
}

function reasoning(item: Record<string, unknown>): void {
  fields(item, [
    "id",
    "type",
    "summary",
    "content",
    "encrypted_content",
    "status",
  ], ["id", "type", "summary"]);
  text(item.id, 256);
  if (item.status != null && item.status !== "completed") invalid();
  for (
    const [key, expected] of [["summary", "summary_text"], [
      "content",
      "reasoning_text",
    ]]
  ) {
    if (key === "content" && item[key] == null) continue;
    const parts = item[key];
    if (!Array.isArray(parts) || parts.length > 16) invalid();
    for (const raw of parts) {
      const part = record(raw);
      fields(part, ["type", "text"]);
      if (part.type !== expected) invalid();
      text(part.text, 16_384, false);
    }
  }
  if (item.encrypted_content != null) {
    text(item.encrypted_content, MAX_ROSTER_PROVIDER_BYTES);
  }
}

/**
 * The tool-free roster request accepts one completed assistant JSON message,
 * optionally preceded by one bounded reasoning item. Reasoning and all provider
 * metadata are discarded. Never select the first text while ignoring later
 * refusal/tool/alternate-answer items. The REST shape follows OpenAI's official
 * responses.ts types; SDK output_text is only accepted when identical to it.
 */
export function rosterResponseText(value: unknown): string {
  boundedTree(value);
  const response = record(value);
  if (response.object !== "response") invalid();
  text(response.id, 256);
  if (response.status === "incomplete") {
    throw new PublicError("roster_extraction_incomplete", 502);
  }
  if (
    response.status !== "completed" || response.error != null ||
    response.incomplete_details != null
  ) invalid();
  if (
    response.tools !== undefined &&
    (!Array.isArray(response.tools) || response.tools.length)
  ) invalid();
  const output = response.output;
  if (!Array.isArray(output) || !output.length || output.length > 2) invalid();
  let result: string | undefined;
  for (let index = 0; index < output.length; index++) {
    const item = record(output[index]);
    if (item.type === "reasoning" && index === 0 && output.length === 2) {
      reasoning(item);
      continue;
    }
    fields(item, ["id", "type", "status", "role", "content", "phase"], [
      "id",
      "type",
      "status",
      "role",
      "content",
    ]);
    if (
      item.type !== "message" || item.role !== "assistant" ||
      item.status !== "completed" ||
      (item.phase != null && item.phase !== "final_answer") ||
      result !== undefined
    ) invalid();
    text(item.id, 256);
    if (!Array.isArray(item.content) || item.content.length !== 1) invalid();
    const part = record(item.content[0]);
    if (part.type === "refusal") {
      throw new PublicError("roster_extraction_refused", 422);
    }
    fields(part, ["type", "text", "annotations", "logprobs"], [
      "type",
      "text",
      "annotations",
    ]);
    if (
      part.type !== "output_text" || !Array.isArray(part.annotations) ||
      part.annotations.length ||
      (part.logprobs !== undefined &&
        (!Array.isArray(part.logprobs) || part.logprobs.length))
    ) invalid();
    result = text(part.text, MAX_ROSTER_OUTPUT_BYTES);
  }
  if (
    result === undefined ||
    (response.output_text !== undefined && response.output_text !== result)
  ) invalid();
  return result;
}

/** Reject duplicate keys and excessive nesting before native JSON decoding. */
function unambiguousJson(value: string): unknown {
  const containers: Array<Set<string> | null> = [];
  const tokens = /"(?:\\[\s\S]|[^"\\])*"|[{}\[\]]/g;
  try {
    for (const match of value.matchAll(tokens)) {
      const token = match[0];
      if (token === "{") containers.push(new Set());
      else if (token === "[") containers.push(null);
      else if (token === "}" || token === "]") containers.pop();
      else {
        let next = match.index! + token.length;
        while (/\s/.test(value[next] ?? "") && next < value.length) next++;
        if (value[next] === ":") {
          const keys = containers.at(-1);
          if (!keys) invalid();
          const key = JSON.parse(token) as string;
          if (keys.has(key)) invalid();
          keys.add(key);
        }
      }
      if (containers.length > 4) tooLarge();
    }
    return JSON.parse(value);
  } catch (error) {
    if (error instanceof PublicError) throw error;
    invalid();
  }
}

function fieldText(value: unknown, maximum: number): string {
  if (typeof value !== "string") invalid();
  // JSON Schema maxLength counts Unicode code points, not UTF-16 code units.
  if ([...value].length > maximum) invalid();
  if (
    /[\u0000-\u001f\u007f]/.test(value) ||
    /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u
      .test(value)
  ) invalid();
  return value;
}

export function rosterResponseCandidates(value: unknown): RosterCandidate[] {
  const decoded = record(unambiguousJson(rosterResponseText(value)));
  fields(decoded, ["rows"]);
  if (
    !Array.isArray(decoded.rows) || !decoded.rows.length ||
    decoded.rows.length > MAX_ROSTER_ROWS
  ) invalid();
  return decoded.rows.map((raw) => {
    const row = record(raw);
    fields(row, [
      "source_row",
      "member_name",
      "momo_name",
      "momo_number",
      "confidence",
    ]);
    if (
      typeof row.source_row !== "number" ||
      !Number.isSafeInteger(row.source_row) || row.source_row < 1 ||
      row.source_row > MAX_ROSTER_SOURCE_ROW ||
      typeof row.confidence !== "number" || !Number.isFinite(row.confidence) ||
      row.confidence < 0 || row.confidence > 1
    ) invalid();
    return {
      source_row: row.source_row,
      member_name: fieldText(row.member_name, MAX_ROSTER_NAME_CHARACTERS),
      momo_name: fieldText(row.momo_name, MAX_ROSTER_NAME_CHARACTERS),
      momo_number: fieldText(row.momo_number, MAX_ROSTER_PHONE_CHARACTERS),
      confidence: row.confidence,
    };
  });
}
