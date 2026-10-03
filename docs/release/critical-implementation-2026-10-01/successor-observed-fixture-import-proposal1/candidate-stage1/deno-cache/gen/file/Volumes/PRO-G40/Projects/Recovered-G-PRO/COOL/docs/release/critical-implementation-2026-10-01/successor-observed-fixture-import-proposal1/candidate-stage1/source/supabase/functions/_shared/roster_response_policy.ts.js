import { PublicError } from "./production_contract.ts";
export const MAX_ROSTER_PROVIDER_BYTES = 1_048_576;
export const MAX_ROSTER_OUTPUT_BYTES = 512_000;
export const MAX_ROSTER_ROWS = 500;
export const MAX_ROSTER_SOURCE_ROW = 2_147_483_647;
export const MAX_ROSTER_NAME_CHARACTERS = 120;
export const MAX_ROSTER_PHONE_CHARACTERS = 32;
const encoder = new TextEncoder();
function invalid() {
  throw new PublicError("roster_provider_response_invalid", 502);
}
function tooLarge() {
  throw new PublicError("roster_provider_response_too_large", 502);
}
function record(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) invalid();
  return value;
}
function fields(value, allowed, required = allowed) {
  if (Object.keys(value).some((key)=>!allowed.includes(key)) || required.some((key)=>!Object.hasOwn(value, key))) invalid();
}
function text(value, maximumBytes, nonempty = true) {
  if (typeof value !== "string" || nonempty && !value.trim()) invalid();
  if (value.length > maximumBytes || encoder.encode(value).length > maximumBytes) tooLarge();
  return value;
}
/** Secondary bounds also cover direct callers; the HTTP body is bounded first. */ function boundedTree(value) {
  const pending = [
    [
      value,
      0
    ]
  ];
  const seen = new Set();
  let nodes = 0, bytes = 0;
  while(pending.length){
    const [current, depth] = pending.pop();
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
      for (const [key, child] of children){
        bytes += encoder.encode(key).length;
        pending.push([
          child,
          depth + 1
        ]);
      }
    } else if (current !== null && typeof current !== "boolean") invalid();
    if (bytes > MAX_ROSTER_PROVIDER_BYTES) tooLarge();
  }
}
function reasoning(item) {
  fields(item, [
    "id",
    "type",
    "summary",
    "content",
    "encrypted_content",
    "status"
  ], [
    "id",
    "type",
    "summary"
  ]);
  text(item.id, 256);
  if (item.status != null && item.status !== "completed") invalid();
  for (const [key, expected] of [
    [
      "summary",
      "summary_text"
    ],
    [
      "content",
      "reasoning_text"
    ]
  ]){
    if (key === "content" && item[key] == null) continue;
    const parts = item[key];
    if (!Array.isArray(parts) || parts.length > 16) invalid();
    for (const raw of parts){
      const part = record(raw);
      fields(part, [
        "type",
        "text"
      ]);
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
 */ export function rosterResponseText(value) {
  boundedTree(value);
  const response = record(value);
  if (response.object !== "response") invalid();
  text(response.id, 256);
  if (response.status === "incomplete") {
    throw new PublicError("roster_extraction_incomplete", 502);
  }
  if (response.status !== "completed" || response.error != null || response.incomplete_details != null) invalid();
  if (response.tools !== undefined && (!Array.isArray(response.tools) || response.tools.length)) invalid();
  const output = response.output;
  if (!Array.isArray(output) || !output.length || output.length > 2) invalid();
  let result;
  for(let index = 0; index < output.length; index++){
    const item = record(output[index]);
    if (item.type === "reasoning" && index === 0 && output.length === 2) {
      reasoning(item);
      continue;
    }
    fields(item, [
      "id",
      "type",
      "status",
      "role",
      "content",
      "phase"
    ], [
      "id",
      "type",
      "status",
      "role",
      "content"
    ]);
    if (item.type !== "message" || item.role !== "assistant" || item.status !== "completed" || item.phase != null && item.phase !== "final_answer" || result !== undefined) invalid();
    text(item.id, 256);
    if (!Array.isArray(item.content) || item.content.length !== 1) invalid();
    const part = record(item.content[0]);
    if (part.type === "refusal") {
      throw new PublicError("roster_extraction_refused", 422);
    }
    fields(part, [
      "type",
      "text",
      "annotations",
      "logprobs"
    ], [
      "type",
      "text",
      "annotations"
    ]);
    if (part.type !== "output_text" || !Array.isArray(part.annotations) || part.annotations.length || part.logprobs !== undefined && (!Array.isArray(part.logprobs) || part.logprobs.length)) invalid();
    result = text(part.text, MAX_ROSTER_OUTPUT_BYTES);
  }
  if (result === undefined || response.output_text !== undefined && response.output_text !== result) invalid();
  return result;
}
/** Reject duplicate keys and excessive nesting before native JSON decoding. */ function unambiguousJson(value) {
  const containers = [];
  const tokens = /"(?:\\[\s\S]|[^"\\])*"|[{}\[\]]/g;
  try {
    for (const match of value.matchAll(tokens)){
      const token = match[0];
      if (token === "{") containers.push(new Set());
      else if (token === "[") containers.push(null);
      else if (token === "}" || token === "]") containers.pop();
      else {
        let next = match.index + token.length;
        while(/\s/.test(value[next] ?? "") && next < value.length)next++;
        if (value[next] === ":") {
          const keys = containers.at(-1);
          if (!keys) invalid();
          const key = JSON.parse(token);
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
function fieldText(value, maximum) {
  if (typeof value !== "string") invalid();
  // JSON Schema maxLength counts Unicode code points, not UTF-16 code units.
  if ([
    ...value
  ].length > maximum) invalid();
  if (/[\u0000-\u001f\u007f]/.test(value) || /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value)) invalid();
  return value;
}
export function rosterResponseCandidates(value) {
  const decoded = record(unambiguousJson(rosterResponseText(value)));
  fields(decoded, [
    "rows"
  ]);
  if (!Array.isArray(decoded.rows) || !decoded.rows.length || decoded.rows.length > MAX_ROSTER_ROWS) invalid();
  return decoded.rows.map((raw)=>{
    const row = record(raw);
    fields(row, [
      "source_row",
      "member_name",
      "momo_name",
      "momo_number",
      "confidence"
    ]);
    if (typeof row.source_row !== "number" || !Number.isSafeInteger(row.source_row) || row.source_row < 1 || row.source_row > MAX_ROSTER_SOURCE_ROW || typeof row.confidence !== "number" || !Number.isFinite(row.confidence) || row.confidence < 0 || row.confidence > 1) invalid();
    return {
      source_row: row.source_row,
      member_name: fieldText(row.member_name, MAX_ROSTER_NAME_CHARACTERS),
      momo_name: fieldText(row.momo_name, MAX_ROSTER_NAME_CHARACTERS),
      momo_number: fieldText(row.momo_number, MAX_ROSTER_PHONE_CHARACTERS),
      confidence: row.confidence
    };
  });
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX3Jlc3BvbnNlX3BvbGljeS50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBQdWJsaWNFcnJvciB9IGZyb20gXCIuL3Byb2R1Y3Rpb25fY29udHJhY3QudHNcIjtcbmltcG9ydCB0eXBlIHsgUm9zdGVyQ2FuZGlkYXRlIH0gZnJvbSBcIi4vcm9zdGVyX2ltcG9ydC50c1wiO1xuXG5leHBvcnQgY29uc3QgTUFYX1JPU1RFUl9QUk9WSURFUl9CWVRFUyA9IDFfMDQ4XzU3NjtcbmV4cG9ydCBjb25zdCBNQVhfUk9TVEVSX09VVFBVVF9CWVRFUyA9IDUxMl8wMDA7XG5leHBvcnQgY29uc3QgTUFYX1JPU1RFUl9ST1dTID0gNTAwO1xuZXhwb3J0IGNvbnN0IE1BWF9ST1NURVJfU09VUkNFX1JPVyA9IDJfMTQ3XzQ4M182NDc7XG5leHBvcnQgY29uc3QgTUFYX1JPU1RFUl9OQU1FX0NIQVJBQ1RFUlMgPSAxMjA7XG5leHBvcnQgY29uc3QgTUFYX1JPU1RFUl9QSE9ORV9DSEFSQUNURVJTID0gMzI7XG5jb25zdCBlbmNvZGVyID0gbmV3IFRleHRFbmNvZGVyKCk7XG5cbmZ1bmN0aW9uIGludmFsaWQoKTogbmV2ZXIge1xuICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyb3N0ZXJfcHJvdmlkZXJfcmVzcG9uc2VfaW52YWxpZFwiLCA1MDIpO1xufVxuZnVuY3Rpb24gdG9vTGFyZ2UoKTogbmV2ZXIge1xuICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyb3N0ZXJfcHJvdmlkZXJfcmVzcG9uc2VfdG9vX2xhcmdlXCIsIDUwMik7XG59XG5mdW5jdGlvbiByZWNvcmQodmFsdWU6IHVua25vd24pOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPiB7XG4gIGlmICghdmFsdWUgfHwgdHlwZW9mIHZhbHVlICE9PSBcIm9iamVjdFwiIHx8IEFycmF5LmlzQXJyYXkodmFsdWUpKSBpbnZhbGlkKCk7XG4gIHJldHVybiB2YWx1ZSBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbn1cbmZ1bmN0aW9uIGZpZWxkcyhcbiAgdmFsdWU6IFJlY29yZDxzdHJpbmcsIHVua25vd24+LFxuICBhbGxvd2VkOiBzdHJpbmdbXSxcbiAgcmVxdWlyZWQgPSBhbGxvd2VkLFxuKTogdm9pZCB7XG4gIGlmIChcbiAgICBPYmplY3Qua2V5cyh2YWx1ZSkuc29tZSgoa2V5KSA9PiAhYWxsb3dlZC5pbmNsdWRlcyhrZXkpKSB8fFxuICAgIHJlcXVpcmVkLnNvbWUoKGtleSkgPT4gIU9iamVjdC5oYXNPd24odmFsdWUsIGtleSkpXG4gICkgaW52YWxpZCgpO1xufVxuZnVuY3Rpb24gdGV4dCh2YWx1ZTogdW5rbm93biwgbWF4aW11bUJ5dGVzOiBudW1iZXIsIG5vbmVtcHR5ID0gdHJ1ZSk6IHN0cmluZyB7XG4gIGlmICh0eXBlb2YgdmFsdWUgIT09IFwic3RyaW5nXCIgfHwgKG5vbmVtcHR5ICYmICF2YWx1ZS50cmltKCkpKSBpbnZhbGlkKCk7XG4gIGlmIChcbiAgICB2YWx1ZS5sZW5ndGggPiBtYXhpbXVtQnl0ZXMgfHwgZW5jb2Rlci5lbmNvZGUodmFsdWUpLmxlbmd0aCA+IG1heGltdW1CeXRlc1xuICApIHRvb0xhcmdlKCk7XG4gIHJldHVybiB2YWx1ZTtcbn1cblxuLyoqIFNlY29uZGFyeSBib3VuZHMgYWxzbyBjb3ZlciBkaXJlY3QgY2FsbGVyczsgdGhlIEhUVFAgYm9keSBpcyBib3VuZGVkIGZpcnN0LiAqL1xuZnVuY3Rpb24gYm91bmRlZFRyZWUodmFsdWU6IHVua25vd24pOiB2b2lkIHtcbiAgY29uc3QgcGVuZGluZzogQXJyYXk8W3Vua25vd24sIG51bWJlcl0+ID0gW1t2YWx1ZSwgMF1dO1xuICBjb25zdCBzZWVuID0gbmV3IFNldDxvYmplY3Q+KCk7XG4gIGxldCBub2RlcyA9IDAsIGJ5dGVzID0gMDtcbiAgd2hpbGUgKHBlbmRpbmcubGVuZ3RoKSB7XG4gICAgY29uc3QgW2N1cnJlbnQsIGRlcHRoXSA9IHBlbmRpbmcucG9wKCkhO1xuICAgIGlmICgrK25vZGVzID4gMjBfMDAwIHx8IGRlcHRoID4gMTYpIHRvb0xhcmdlKCk7XG4gICAgaWYgKHR5cGVvZiBjdXJyZW50ID09PSBcInN0cmluZ1wiKSB7XG4gICAgICBpZiAoY3VycmVudC5sZW5ndGggPiBNQVhfUk9TVEVSX1BST1ZJREVSX0JZVEVTKSB0b29MYXJnZSgpO1xuICAgICAgYnl0ZXMgKz0gZW5jb2Rlci5lbmNvZGUoY3VycmVudCkubGVuZ3RoO1xuICAgIH0gZWxzZSBpZiAodHlwZW9mIGN1cnJlbnQgPT09IFwibnVtYmVyXCIpIHtcbiAgICAgIGlmICghTnVtYmVyLmlzRmluaXRlKGN1cnJlbnQpKSBpbnZhbGlkKCk7XG4gICAgfSBlbHNlIGlmIChjdXJyZW50ICYmIHR5cGVvZiBjdXJyZW50ID09PSBcIm9iamVjdFwiKSB7XG4gICAgICBpZiAoc2Vlbi5oYXMoY3VycmVudCkpIGludmFsaWQoKTtcbiAgICAgIHNlZW4uYWRkKGN1cnJlbnQpO1xuICAgICAgY29uc3QgY2hpbGRyZW4gPSBPYmplY3QuZW50cmllcyhjdXJyZW50KTtcbiAgICAgIGlmIChjaGlsZHJlbi5sZW5ndGggPiAyMF8wMDAgLSBub2RlcyAtIHBlbmRpbmcubGVuZ3RoKSB0b29MYXJnZSgpO1xuICAgICAgZm9yIChjb25zdCBba2V5LCBjaGlsZF0gb2YgY2hpbGRyZW4pIHtcbiAgICAgICAgYnl0ZXMgKz0gZW5jb2Rlci5lbmNvZGUoa2V5KS5sZW5ndGg7XG4gICAgICAgIHBlbmRpbmcucHVzaChbY2hpbGQsIGRlcHRoICsgMV0pO1xuICAgICAgfVxuICAgIH0gZWxzZSBpZiAoY3VycmVudCAhPT0gbnVsbCAmJiB0eXBlb2YgY3VycmVudCAhPT0gXCJib29sZWFuXCIpIGludmFsaWQoKTtcbiAgICBpZiAoYnl0ZXMgPiBNQVhfUk9TVEVSX1BST1ZJREVSX0JZVEVTKSB0b29MYXJnZSgpO1xuICB9XG59XG5cbmZ1bmN0aW9uIHJlYXNvbmluZyhpdGVtOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPik6IHZvaWQge1xuICBmaWVsZHMoaXRlbSwgW1xuICAgIFwiaWRcIixcbiAgICBcInR5cGVcIixcbiAgICBcInN1bW1hcnlcIixcbiAgICBcImNvbnRlbnRcIixcbiAgICBcImVuY3J5cHRlZF9jb250ZW50XCIsXG4gICAgXCJzdGF0dXNcIixcbiAgXSwgW1wiaWRcIiwgXCJ0eXBlXCIsIFwic3VtbWFyeVwiXSk7XG4gIHRleHQoaXRlbS5pZCwgMjU2KTtcbiAgaWYgKGl0ZW0uc3RhdHVzICE9IG51bGwgJiYgaXRlbS5zdGF0dXMgIT09IFwiY29tcGxldGVkXCIpIGludmFsaWQoKTtcbiAgZm9yIChcbiAgICBjb25zdCBba2V5LCBleHBlY3RlZF0gb2YgW1tcInN1bW1hcnlcIiwgXCJzdW1tYXJ5X3RleHRcIl0sIFtcbiAgICAgIFwiY29udGVudFwiLFxuICAgICAgXCJyZWFzb25pbmdfdGV4dFwiLFxuICAgIF1dXG4gICkge1xuICAgIGlmIChrZXkgPT09IFwiY29udGVudFwiICYmIGl0ZW1ba2V5XSA9PSBudWxsKSBjb250aW51ZTtcbiAgICBjb25zdCBwYXJ0cyA9IGl0ZW1ba2V5XTtcbiAgICBpZiAoIUFycmF5LmlzQXJyYXkocGFydHMpIHx8IHBhcnRzLmxlbmd0aCA+IDE2KSBpbnZhbGlkKCk7XG4gICAgZm9yIChjb25zdCByYXcgb2YgcGFydHMpIHtcbiAgICAgIGNvbnN0IHBhcnQgPSByZWNvcmQocmF3KTtcbiAgICAgIGZpZWxkcyhwYXJ0LCBbXCJ0eXBlXCIsIFwidGV4dFwiXSk7XG4gICAgICBpZiAocGFydC50eXBlICE9PSBleHBlY3RlZCkgaW52YWxpZCgpO1xuICAgICAgdGV4dChwYXJ0LnRleHQsIDE2XzM4NCwgZmFsc2UpO1xuICAgIH1cbiAgfVxuICBpZiAoaXRlbS5lbmNyeXB0ZWRfY29udGVudCAhPSBudWxsKSB7XG4gICAgdGV4dChpdGVtLmVuY3J5cHRlZF9jb250ZW50LCBNQVhfUk9TVEVSX1BST1ZJREVSX0JZVEVTKTtcbiAgfVxufVxuXG4vKipcbiAqIFRoZSB0b29sLWZyZWUgcm9zdGVyIHJlcXVlc3QgYWNjZXB0cyBvbmUgY29tcGxldGVkIGFzc2lzdGFudCBKU09OIG1lc3NhZ2UsXG4gKiBvcHRpb25hbGx5IHByZWNlZGVkIGJ5IG9uZSBib3VuZGVkIHJlYXNvbmluZyBpdGVtLiBSZWFzb25pbmcgYW5kIGFsbCBwcm92aWRlclxuICogbWV0YWRhdGEgYXJlIGRpc2NhcmRlZC4gTmV2ZXIgc2VsZWN0IHRoZSBmaXJzdCB0ZXh0IHdoaWxlIGlnbm9yaW5nIGxhdGVyXG4gKiByZWZ1c2FsL3Rvb2wvYWx0ZXJuYXRlLWFuc3dlciBpdGVtcy4gVGhlIFJFU1Qgc2hhcGUgZm9sbG93cyBPcGVuQUkncyBvZmZpY2lhbFxuICogcmVzcG9uc2VzLnRzIHR5cGVzOyBTREsgb3V0cHV0X3RleHQgaXMgb25seSBhY2NlcHRlZCB3aGVuIGlkZW50aWNhbCB0byBpdC5cbiAqL1xuZXhwb3J0IGZ1bmN0aW9uIHJvc3RlclJlc3BvbnNlVGV4dCh2YWx1ZTogdW5rbm93bik6IHN0cmluZyB7XG4gIGJvdW5kZWRUcmVlKHZhbHVlKTtcbiAgY29uc3QgcmVzcG9uc2UgPSByZWNvcmQodmFsdWUpO1xuICBpZiAocmVzcG9uc2Uub2JqZWN0ICE9PSBcInJlc3BvbnNlXCIpIGludmFsaWQoKTtcbiAgdGV4dChyZXNwb25zZS5pZCwgMjU2KTtcbiAgaWYgKHJlc3BvbnNlLnN0YXR1cyA9PT0gXCJpbmNvbXBsZXRlXCIpIHtcbiAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyb3N0ZXJfZXh0cmFjdGlvbl9pbmNvbXBsZXRlXCIsIDUwMik7XG4gIH1cbiAgaWYgKFxuICAgIHJlc3BvbnNlLnN0YXR1cyAhPT0gXCJjb21wbGV0ZWRcIiB8fCByZXNwb25zZS5lcnJvciAhPSBudWxsIHx8XG4gICAgcmVzcG9uc2UuaW5jb21wbGV0ZV9kZXRhaWxzICE9IG51bGxcbiAgKSBpbnZhbGlkKCk7XG4gIGlmIChcbiAgICByZXNwb25zZS50b29scyAhPT0gdW5kZWZpbmVkICYmXG4gICAgKCFBcnJheS5pc0FycmF5KHJlc3BvbnNlLnRvb2xzKSB8fCByZXNwb25zZS50b29scy5sZW5ndGgpXG4gICkgaW52YWxpZCgpO1xuICBjb25zdCBvdXRwdXQgPSByZXNwb25zZS5vdXRwdXQ7XG4gIGlmICghQXJyYXkuaXNBcnJheShvdXRwdXQpIHx8ICFvdXRwdXQubGVuZ3RoIHx8IG91dHB1dC5sZW5ndGggPiAyKSBpbnZhbGlkKCk7XG4gIGxldCByZXN1bHQ6IHN0cmluZyB8IHVuZGVmaW5lZDtcbiAgZm9yIChsZXQgaW5kZXggPSAwOyBpbmRleCA8IG91dHB1dC5sZW5ndGg7IGluZGV4KyspIHtcbiAgICBjb25zdCBpdGVtID0gcmVjb3JkKG91dHB1dFtpbmRleF0pO1xuICAgIGlmIChpdGVtLnR5cGUgPT09IFwicmVhc29uaW5nXCIgJiYgaW5kZXggPT09IDAgJiYgb3V0cHV0Lmxlbmd0aCA9PT0gMikge1xuICAgICAgcmVhc29uaW5nKGl0ZW0pO1xuICAgICAgY29udGludWU7XG4gICAgfVxuICAgIGZpZWxkcyhpdGVtLCBbXCJpZFwiLCBcInR5cGVcIiwgXCJzdGF0dXNcIiwgXCJyb2xlXCIsIFwiY29udGVudFwiLCBcInBoYXNlXCJdLCBbXG4gICAgICBcImlkXCIsXG4gICAgICBcInR5cGVcIixcbiAgICAgIFwic3RhdHVzXCIsXG4gICAgICBcInJvbGVcIixcbiAgICAgIFwiY29udGVudFwiLFxuICAgIF0pO1xuICAgIGlmIChcbiAgICAgIGl0ZW0udHlwZSAhPT0gXCJtZXNzYWdlXCIgfHwgaXRlbS5yb2xlICE9PSBcImFzc2lzdGFudFwiIHx8XG4gICAgICBpdGVtLnN0YXR1cyAhPT0gXCJjb21wbGV0ZWRcIiB8fFxuICAgICAgKGl0ZW0ucGhhc2UgIT0gbnVsbCAmJiBpdGVtLnBoYXNlICE9PSBcImZpbmFsX2Fuc3dlclwiKSB8fFxuICAgICAgcmVzdWx0ICE9PSB1bmRlZmluZWRcbiAgICApIGludmFsaWQoKTtcbiAgICB0ZXh0KGl0ZW0uaWQsIDI1Nik7XG4gICAgaWYgKCFBcnJheS5pc0FycmF5KGl0ZW0uY29udGVudCkgfHwgaXRlbS5jb250ZW50Lmxlbmd0aCAhPT0gMSkgaW52YWxpZCgpO1xuICAgIGNvbnN0IHBhcnQgPSByZWNvcmQoaXRlbS5jb250ZW50WzBdKTtcbiAgICBpZiAocGFydC50eXBlID09PSBcInJlZnVzYWxcIikge1xuICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicm9zdGVyX2V4dHJhY3Rpb25fcmVmdXNlZFwiLCA0MjIpO1xuICAgIH1cbiAgICBmaWVsZHMocGFydCwgW1widHlwZVwiLCBcInRleHRcIiwgXCJhbm5vdGF0aW9uc1wiLCBcImxvZ3Byb2JzXCJdLCBbXG4gICAgICBcInR5cGVcIixcbiAgICAgIFwidGV4dFwiLFxuICAgICAgXCJhbm5vdGF0aW9uc1wiLFxuICAgIF0pO1xuICAgIGlmIChcbiAgICAgIHBhcnQudHlwZSAhPT0gXCJvdXRwdXRfdGV4dFwiIHx8ICFBcnJheS5pc0FycmF5KHBhcnQuYW5ub3RhdGlvbnMpIHx8XG4gICAgICBwYXJ0LmFubm90YXRpb25zLmxlbmd0aCB8fFxuICAgICAgKHBhcnQubG9ncHJvYnMgIT09IHVuZGVmaW5lZCAmJlxuICAgICAgICAoIUFycmF5LmlzQXJyYXkocGFydC5sb2dwcm9icykgfHwgcGFydC5sb2dwcm9icy5sZW5ndGgpKVxuICAgICkgaW52YWxpZCgpO1xuICAgIHJlc3VsdCA9IHRleHQocGFydC50ZXh0LCBNQVhfUk9TVEVSX09VVFBVVF9CWVRFUyk7XG4gIH1cbiAgaWYgKFxuICAgIHJlc3VsdCA9PT0gdW5kZWZpbmVkIHx8XG4gICAgKHJlc3BvbnNlLm91dHB1dF90ZXh0ICE9PSB1bmRlZmluZWQgJiYgcmVzcG9uc2Uub3V0cHV0X3RleHQgIT09IHJlc3VsdClcbiAgKSBpbnZhbGlkKCk7XG4gIHJldHVybiByZXN1bHQ7XG59XG5cbi8qKiBSZWplY3QgZHVwbGljYXRlIGtleXMgYW5kIGV4Y2Vzc2l2ZSBuZXN0aW5nIGJlZm9yZSBuYXRpdmUgSlNPTiBkZWNvZGluZy4gKi9cbmZ1bmN0aW9uIHVuYW1iaWd1b3VzSnNvbih2YWx1ZTogc3RyaW5nKTogdW5rbm93biB7XG4gIGNvbnN0IGNvbnRhaW5lcnM6IEFycmF5PFNldDxzdHJpbmc+IHwgbnVsbD4gPSBbXTtcbiAgY29uc3QgdG9rZW5zID0gL1wiKD86XFxcXFtcXHNcXFNdfFteXCJcXFxcXSkqXCJ8W3t9XFxbXFxdXS9nO1xuICB0cnkge1xuICAgIGZvciAoY29uc3QgbWF0Y2ggb2YgdmFsdWUubWF0Y2hBbGwodG9rZW5zKSkge1xuICAgICAgY29uc3QgdG9rZW4gPSBtYXRjaFswXTtcbiAgICAgIGlmICh0b2tlbiA9PT0gXCJ7XCIpIGNvbnRhaW5lcnMucHVzaChuZXcgU2V0KCkpO1xuICAgICAgZWxzZSBpZiAodG9rZW4gPT09IFwiW1wiKSBjb250YWluZXJzLnB1c2gobnVsbCk7XG4gICAgICBlbHNlIGlmICh0b2tlbiA9PT0gXCJ9XCIgfHwgdG9rZW4gPT09IFwiXVwiKSBjb250YWluZXJzLnBvcCgpO1xuICAgICAgZWxzZSB7XG4gICAgICAgIGxldCBuZXh0ID0gbWF0Y2guaW5kZXghICsgdG9rZW4ubGVuZ3RoO1xuICAgICAgICB3aGlsZSAoL1xccy8udGVzdCh2YWx1ZVtuZXh0XSA/PyBcIlwiKSAmJiBuZXh0IDwgdmFsdWUubGVuZ3RoKSBuZXh0Kys7XG4gICAgICAgIGlmICh2YWx1ZVtuZXh0XSA9PT0gXCI6XCIpIHtcbiAgICAgICAgICBjb25zdCBrZXlzID0gY29udGFpbmVycy5hdCgtMSk7XG4gICAgICAgICAgaWYgKCFrZXlzKSBpbnZhbGlkKCk7XG4gICAgICAgICAgY29uc3Qga2V5ID0gSlNPTi5wYXJzZSh0b2tlbikgYXMgc3RyaW5nO1xuICAgICAgICAgIGlmIChrZXlzLmhhcyhrZXkpKSBpbnZhbGlkKCk7XG4gICAgICAgICAga2V5cy5hZGQoa2V5KTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgICAgaWYgKGNvbnRhaW5lcnMubGVuZ3RoID4gNCkgdG9vTGFyZ2UoKTtcbiAgICB9XG4gICAgcmV0dXJuIEpTT04ucGFyc2UodmFsdWUpO1xuICB9IGNhdGNoIChlcnJvcikge1xuICAgIGlmIChlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yKSB0aHJvdyBlcnJvcjtcbiAgICBpbnZhbGlkKCk7XG4gIH1cbn1cblxuZnVuY3Rpb24gZmllbGRUZXh0KHZhbHVlOiB1bmtub3duLCBtYXhpbXVtOiBudW1iZXIpOiBzdHJpbmcge1xuICBpZiAodHlwZW9mIHZhbHVlICE9PSBcInN0cmluZ1wiKSBpbnZhbGlkKCk7XG4gIC8vIEpTT04gU2NoZW1hIG1heExlbmd0aCBjb3VudHMgVW5pY29kZSBjb2RlIHBvaW50cywgbm90IFVURi0xNiBjb2RlIHVuaXRzLlxuICBpZiAoWy4uLnZhbHVlXS5sZW5ndGggPiBtYXhpbXVtKSBpbnZhbGlkKCk7XG4gIGlmIChcbiAgICAvW1xcdTAwMDAtXFx1MDAxZlxcdTAwN2ZdLy50ZXN0KHZhbHVlKSB8fFxuICAgIC9bXFx1RDgwMC1cXHVEQkZGXSg/IVtcXHVEQzAwLVxcdURGRkZdKXwoPzwhW1xcdUQ4MDAtXFx1REJGRl0pW1xcdURDMDAtXFx1REZGRl0vdVxuICAgICAgLnRlc3QodmFsdWUpXG4gICkgaW52YWxpZCgpO1xuICByZXR1cm4gdmFsdWU7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiByb3N0ZXJSZXNwb25zZUNhbmRpZGF0ZXModmFsdWU6IHVua25vd24pOiBSb3N0ZXJDYW5kaWRhdGVbXSB7XG4gIGNvbnN0IGRlY29kZWQgPSByZWNvcmQodW5hbWJpZ3VvdXNKc29uKHJvc3RlclJlc3BvbnNlVGV4dCh2YWx1ZSkpKTtcbiAgZmllbGRzKGRlY29kZWQsIFtcInJvd3NcIl0pO1xuICBpZiAoXG4gICAgIUFycmF5LmlzQXJyYXkoZGVjb2RlZC5yb3dzKSB8fCAhZGVjb2RlZC5yb3dzLmxlbmd0aCB8fFxuICAgIGRlY29kZWQucm93cy5sZW5ndGggPiBNQVhfUk9TVEVSX1JPV1NcbiAgKSBpbnZhbGlkKCk7XG4gIHJldHVybiBkZWNvZGVkLnJvd3MubWFwKChyYXcpID0+IHtcbiAgICBjb25zdCByb3cgPSByZWNvcmQocmF3KTtcbiAgICBmaWVsZHMocm93LCBbXG4gICAgICBcInNvdXJjZV9yb3dcIixcbiAgICAgIFwibWVtYmVyX25hbWVcIixcbiAgICAgIFwibW9tb19uYW1lXCIsXG4gICAgICBcIm1vbW9fbnVtYmVyXCIsXG4gICAgICBcImNvbmZpZGVuY2VcIixcbiAgICBdKTtcbiAgICBpZiAoXG4gICAgICB0eXBlb2Ygcm93LnNvdXJjZV9yb3cgIT09IFwibnVtYmVyXCIgfHxcbiAgICAgICFOdW1iZXIuaXNTYWZlSW50ZWdlcihyb3cuc291cmNlX3JvdykgfHwgcm93LnNvdXJjZV9yb3cgPCAxIHx8XG4gICAgICByb3cuc291cmNlX3JvdyA+IE1BWF9ST1NURVJfU09VUkNFX1JPVyB8fFxuICAgICAgdHlwZW9mIHJvdy5jb25maWRlbmNlICE9PSBcIm51bWJlclwiIHx8ICFOdW1iZXIuaXNGaW5pdGUocm93LmNvbmZpZGVuY2UpIHx8XG4gICAgICByb3cuY29uZmlkZW5jZSA8IDAgfHwgcm93LmNvbmZpZGVuY2UgPiAxXG4gICAgKSBpbnZhbGlkKCk7XG4gICAgcmV0dXJuIHtcbiAgICAgIHNvdXJjZV9yb3c6IHJvdy5zb3VyY2Vfcm93LFxuICAgICAgbWVtYmVyX25hbWU6IGZpZWxkVGV4dChyb3cubWVtYmVyX25hbWUsIE1BWF9ST1NURVJfTkFNRV9DSEFSQUNURVJTKSxcbiAgICAgIG1vbW9fbmFtZTogZmllbGRUZXh0KHJvdy5tb21vX25hbWUsIE1BWF9ST1NURVJfTkFNRV9DSEFSQUNURVJTKSxcbiAgICAgIG1vbW9fbnVtYmVyOiBmaWVsZFRleHQocm93Lm1vbW9fbnVtYmVyLCBNQVhfUk9TVEVSX1BIT05FX0NIQVJBQ1RFUlMpLFxuICAgICAgY29uZmlkZW5jZTogcm93LmNvbmZpZGVuY2UsXG4gICAgfTtcbiAgfSk7XG59XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxXQUFXLFFBQVEsMkJBQTJCO0FBR3ZELE9BQU8sTUFBTSw0QkFBNEIsVUFBVTtBQUNuRCxPQUFPLE1BQU0sMEJBQTBCLFFBQVE7QUFDL0MsT0FBTyxNQUFNLGtCQUFrQixJQUFJO0FBQ25DLE9BQU8sTUFBTSx3QkFBd0IsY0FBYztBQUNuRCxPQUFPLE1BQU0sNkJBQTZCLElBQUk7QUFDOUMsT0FBTyxNQUFNLDhCQUE4QixHQUFHO0FBQzlDLE1BQU0sVUFBVSxJQUFJO0FBRXBCLFNBQVM7RUFDUCxNQUFNLElBQUksWUFBWSxvQ0FBb0M7QUFDNUQ7QUFDQSxTQUFTO0VBQ1AsTUFBTSxJQUFJLFlBQVksc0NBQXNDO0FBQzlEO0FBQ0EsU0FBUyxPQUFPLEtBQWM7RUFDNUIsSUFBSSxDQUFDLFNBQVMsT0FBTyxVQUFVLFlBQVksTUFBTSxPQUFPLENBQUMsUUFBUTtFQUNqRSxPQUFPO0FBQ1Q7QUFDQSxTQUFTLE9BQ1AsS0FBOEIsRUFDOUIsT0FBaUIsRUFDakIsV0FBVyxPQUFPO0VBRWxCLElBQ0UsT0FBTyxJQUFJLENBQUMsT0FBTyxJQUFJLENBQUMsQ0FBQyxNQUFRLENBQUMsUUFBUSxRQUFRLENBQUMsU0FDbkQsU0FBUyxJQUFJLENBQUMsQ0FBQyxNQUFRLENBQUMsT0FBTyxNQUFNLENBQUMsT0FBTyxPQUM3QztBQUNKO0FBQ0EsU0FBUyxLQUFLLEtBQWMsRUFBRSxZQUFvQixFQUFFLFdBQVcsSUFBSTtFQUNqRSxJQUFJLE9BQU8sVUFBVSxZQUFhLFlBQVksQ0FBQyxNQUFNLElBQUksSUFBSztFQUM5RCxJQUNFLE1BQU0sTUFBTSxHQUFHLGdCQUFnQixRQUFRLE1BQU0sQ0FBQyxPQUFPLE1BQU0sR0FBRyxjQUM5RDtFQUNGLE9BQU87QUFDVDtBQUVBLGdGQUFnRixHQUNoRixTQUFTLFlBQVksS0FBYztFQUNqQyxNQUFNLFVBQW9DO0lBQUM7TUFBQztNQUFPO0tBQUU7R0FBQztFQUN0RCxNQUFNLE9BQU8sSUFBSTtFQUNqQixJQUFJLFFBQVEsR0FBRyxRQUFRO0VBQ3ZCLE1BQU8sUUFBUSxNQUFNLENBQUU7SUFDckIsTUFBTSxDQUFDLFNBQVMsTUFBTSxHQUFHLFFBQVEsR0FBRztJQUNwQyxJQUFJLEVBQUUsUUFBUSxVQUFVLFFBQVEsSUFBSTtJQUNwQyxJQUFJLE9BQU8sWUFBWSxVQUFVO01BQy9CLElBQUksUUFBUSxNQUFNLEdBQUcsMkJBQTJCO01BQ2hELFNBQVMsUUFBUSxNQUFNLENBQUMsU0FBUyxNQUFNO0lBQ3pDLE9BQU8sSUFBSSxPQUFPLFlBQVksVUFBVTtNQUN0QyxJQUFJLENBQUMsT0FBTyxRQUFRLENBQUMsVUFBVTtJQUNqQyxPQUFPLElBQUksV0FBVyxPQUFPLFlBQVksVUFBVTtNQUNqRCxJQUFJLEtBQUssR0FBRyxDQUFDLFVBQVU7TUFDdkIsS0FBSyxHQUFHLENBQUM7TUFDVCxNQUFNLFdBQVcsT0FBTyxPQUFPLENBQUM7TUFDaEMsSUFBSSxTQUFTLE1BQU0sR0FBRyxTQUFTLFFBQVEsUUFBUSxNQUFNLEVBQUU7TUFDdkQsS0FBSyxNQUFNLENBQUMsS0FBSyxNQUFNLElBQUksU0FBVTtRQUNuQyxTQUFTLFFBQVEsTUFBTSxDQUFDLEtBQUssTUFBTTtRQUNuQyxRQUFRLElBQUksQ0FBQztVQUFDO1VBQU8sUUFBUTtTQUFFO01BQ2pDO0lBQ0YsT0FBTyxJQUFJLFlBQVksUUFBUSxPQUFPLFlBQVksV0FBVztJQUM3RCxJQUFJLFFBQVEsMkJBQTJCO0VBQ3pDO0FBQ0Y7QUFFQSxTQUFTLFVBQVUsSUFBNkI7RUFDOUMsT0FBTyxNQUFNO0lBQ1g7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0dBQ0QsRUFBRTtJQUFDO0lBQU07SUFBUTtHQUFVO0VBQzVCLEtBQUssS0FBSyxFQUFFLEVBQUU7RUFDZCxJQUFJLEtBQUssTUFBTSxJQUFJLFFBQVEsS0FBSyxNQUFNLEtBQUssYUFBYTtFQUN4RCxLQUNFLE1BQU0sQ0FBQyxLQUFLLFNBQVMsSUFBSTtJQUFDO01BQUM7TUFBVztLQUFlO0lBQUU7TUFDckQ7TUFDQTtLQUNEO0dBQUMsQ0FDRjtJQUNBLElBQUksUUFBUSxhQUFhLElBQUksQ0FBQyxJQUFJLElBQUksTUFBTTtJQUM1QyxNQUFNLFFBQVEsSUFBSSxDQUFDLElBQUk7SUFDdkIsSUFBSSxDQUFDLE1BQU0sT0FBTyxDQUFDLFVBQVUsTUFBTSxNQUFNLEdBQUcsSUFBSTtJQUNoRCxLQUFLLE1BQU0sT0FBTyxNQUFPO01BQ3ZCLE1BQU0sT0FBTyxPQUFPO01BQ3BCLE9BQU8sTUFBTTtRQUFDO1FBQVE7T0FBTztNQUM3QixJQUFJLEtBQUssSUFBSSxLQUFLLFVBQVU7TUFDNUIsS0FBSyxLQUFLLElBQUksRUFBRSxRQUFRO0lBQzFCO0VBQ0Y7RUFDQSxJQUFJLEtBQUssaUJBQWlCLElBQUksTUFBTTtJQUNsQyxLQUFLLEtBQUssaUJBQWlCLEVBQUU7RUFDL0I7QUFDRjtBQUVBOzs7Ozs7Q0FNQyxHQUNELE9BQU8sU0FBUyxtQkFBbUIsS0FBYztFQUMvQyxZQUFZO0VBQ1osTUFBTSxXQUFXLE9BQU87RUFDeEIsSUFBSSxTQUFTLE1BQU0sS0FBSyxZQUFZO0VBQ3BDLEtBQUssU0FBUyxFQUFFLEVBQUU7RUFDbEIsSUFBSSxTQUFTLE1BQU0sS0FBSyxjQUFjO0lBQ3BDLE1BQU0sSUFBSSxZQUFZLGdDQUFnQztFQUN4RDtFQUNBLElBQ0UsU0FBUyxNQUFNLEtBQUssZUFBZSxTQUFTLEtBQUssSUFBSSxRQUNyRCxTQUFTLGtCQUFrQixJQUFJLE1BQy9CO0VBQ0YsSUFDRSxTQUFTLEtBQUssS0FBSyxhQUNuQixDQUFDLENBQUMsTUFBTSxPQUFPLENBQUMsU0FBUyxLQUFLLEtBQUssU0FBUyxLQUFLLENBQUMsTUFBTSxHQUN4RDtFQUNGLE1BQU0sU0FBUyxTQUFTLE1BQU07RUFDOUIsSUFBSSxDQUFDLE1BQU0sT0FBTyxDQUFDLFdBQVcsQ0FBQyxPQUFPLE1BQU0sSUFBSSxPQUFPLE1BQU0sR0FBRyxHQUFHO0VBQ25FLElBQUk7RUFDSixJQUFLLElBQUksUUFBUSxHQUFHLFFBQVEsT0FBTyxNQUFNLEVBQUUsUUFBUztJQUNsRCxNQUFNLE9BQU8sT0FBTyxNQUFNLENBQUMsTUFBTTtJQUNqQyxJQUFJLEtBQUssSUFBSSxLQUFLLGVBQWUsVUFBVSxLQUFLLE9BQU8sTUFBTSxLQUFLLEdBQUc7TUFDbkUsVUFBVTtNQUNWO0lBQ0Y7SUFDQSxPQUFPLE1BQU07TUFBQztNQUFNO01BQVE7TUFBVTtNQUFRO01BQVc7S0FBUSxFQUFFO01BQ2pFO01BQ0E7TUFDQTtNQUNBO01BQ0E7S0FDRDtJQUNELElBQ0UsS0FBSyxJQUFJLEtBQUssYUFBYSxLQUFLLElBQUksS0FBSyxlQUN6QyxLQUFLLE1BQU0sS0FBSyxlQUNmLEtBQUssS0FBSyxJQUFJLFFBQVEsS0FBSyxLQUFLLEtBQUssa0JBQ3RDLFdBQVcsV0FDWDtJQUNGLEtBQUssS0FBSyxFQUFFLEVBQUU7SUFDZCxJQUFJLENBQUMsTUFBTSxPQUFPLENBQUMsS0FBSyxPQUFPLEtBQUssS0FBSyxPQUFPLENBQUMsTUFBTSxLQUFLLEdBQUc7SUFDL0QsTUFBTSxPQUFPLE9BQU8sS0FBSyxPQUFPLENBQUMsRUFBRTtJQUNuQyxJQUFJLEtBQUssSUFBSSxLQUFLLFdBQVc7TUFDM0IsTUFBTSxJQUFJLFlBQVksNkJBQTZCO0lBQ3JEO0lBQ0EsT0FBTyxNQUFNO01BQUM7TUFBUTtNQUFRO01BQWU7S0FBVyxFQUFFO01BQ3hEO01BQ0E7TUFDQTtLQUNEO0lBQ0QsSUFDRSxLQUFLLElBQUksS0FBSyxpQkFBaUIsQ0FBQyxNQUFNLE9BQU8sQ0FBQyxLQUFLLFdBQVcsS0FDOUQsS0FBSyxXQUFXLENBQUMsTUFBTSxJQUN0QixLQUFLLFFBQVEsS0FBSyxhQUNqQixDQUFDLENBQUMsTUFBTSxPQUFPLENBQUMsS0FBSyxRQUFRLEtBQUssS0FBSyxRQUFRLENBQUMsTUFBTSxHQUN4RDtJQUNGLFNBQVMsS0FBSyxLQUFLLElBQUksRUFBRTtFQUMzQjtFQUNBLElBQ0UsV0FBVyxhQUNWLFNBQVMsV0FBVyxLQUFLLGFBQWEsU0FBUyxXQUFXLEtBQUssUUFDaEU7RUFDRixPQUFPO0FBQ1Q7QUFFQSw2RUFBNkUsR0FDN0UsU0FBUyxnQkFBZ0IsS0FBYTtFQUNwQyxNQUFNLGFBQXdDLEVBQUU7RUFDaEQsTUFBTSxTQUFTO0VBQ2YsSUFBSTtJQUNGLEtBQUssTUFBTSxTQUFTLE1BQU0sUUFBUSxDQUFDLFFBQVM7TUFDMUMsTUFBTSxRQUFRLEtBQUssQ0FBQyxFQUFFO01BQ3RCLElBQUksVUFBVSxLQUFLLFdBQVcsSUFBSSxDQUFDLElBQUk7V0FDbEMsSUFBSSxVQUFVLEtBQUssV0FBVyxJQUFJLENBQUM7V0FDbkMsSUFBSSxVQUFVLE9BQU8sVUFBVSxLQUFLLFdBQVcsR0FBRztXQUNsRDtRQUNILElBQUksT0FBTyxNQUFNLEtBQUssR0FBSSxNQUFNLE1BQU07UUFDdEMsTUFBTyxLQUFLLElBQUksQ0FBQyxLQUFLLENBQUMsS0FBSyxJQUFJLE9BQU8sT0FBTyxNQUFNLE1BQU0sQ0FBRTtRQUM1RCxJQUFJLEtBQUssQ0FBQyxLQUFLLEtBQUssS0FBSztVQUN2QixNQUFNLE9BQU8sV0FBVyxFQUFFLENBQUMsQ0FBQztVQUM1QixJQUFJLENBQUMsTUFBTTtVQUNYLE1BQU0sTUFBTSxLQUFLLEtBQUssQ0FBQztVQUN2QixJQUFJLEtBQUssR0FBRyxDQUFDLE1BQU07VUFDbkIsS0FBSyxHQUFHLENBQUM7UUFDWDtNQUNGO01BQ0EsSUFBSSxXQUFXLE1BQU0sR0FBRyxHQUFHO0lBQzdCO0lBQ0EsT0FBTyxLQUFLLEtBQUssQ0FBQztFQUNwQixFQUFFLE9BQU8sT0FBTztJQUNkLElBQUksaUJBQWlCLGFBQWEsTUFBTTtJQUN4QztFQUNGO0FBQ0Y7QUFFQSxTQUFTLFVBQVUsS0FBYyxFQUFFLE9BQWU7RUFDaEQsSUFBSSxPQUFPLFVBQVUsVUFBVTtFQUMvQiwyRUFBMkU7RUFDM0UsSUFBSTtPQUFJO0dBQU0sQ0FBQyxNQUFNLEdBQUcsU0FBUztFQUNqQyxJQUNFLHdCQUF3QixJQUFJLENBQUMsVUFDN0IsMEVBQ0csSUFBSSxDQUFDLFFBQ1I7RUFDRixPQUFPO0FBQ1Q7QUFFQSxPQUFPLFNBQVMseUJBQXlCLEtBQWM7RUFDckQsTUFBTSxVQUFVLE9BQU8sZ0JBQWdCLG1CQUFtQjtFQUMxRCxPQUFPLFNBQVM7SUFBQztHQUFPO0VBQ3hCLElBQ0UsQ0FBQyxNQUFNLE9BQU8sQ0FBQyxRQUFRLElBQUksS0FBSyxDQUFDLFFBQVEsSUFBSSxDQUFDLE1BQU0sSUFDcEQsUUFBUSxJQUFJLENBQUMsTUFBTSxHQUFHLGlCQUN0QjtFQUNGLE9BQU8sUUFBUSxJQUFJLENBQUMsR0FBRyxDQUFDLENBQUM7SUFDdkIsTUFBTSxNQUFNLE9BQU87SUFDbkIsT0FBTyxLQUFLO01BQ1Y7TUFDQTtNQUNBO01BQ0E7TUFDQTtLQUNEO0lBQ0QsSUFDRSxPQUFPLElBQUksVUFBVSxLQUFLLFlBQzFCLENBQUMsT0FBTyxhQUFhLENBQUMsSUFBSSxVQUFVLEtBQUssSUFBSSxVQUFVLEdBQUcsS0FDMUQsSUFBSSxVQUFVLEdBQUcseUJBQ2pCLE9BQU8sSUFBSSxVQUFVLEtBQUssWUFBWSxDQUFDLE9BQU8sUUFBUSxDQUFDLElBQUksVUFBVSxLQUNyRSxJQUFJLFVBQVUsR0FBRyxLQUFLLElBQUksVUFBVSxHQUFHLEdBQ3ZDO0lBQ0YsT0FBTztNQUNMLFlBQVksSUFBSSxVQUFVO01BQzFCLGFBQWEsVUFBVSxJQUFJLFdBQVcsRUFBRTtNQUN4QyxXQUFXLFVBQVUsSUFBSSxTQUFTLEVBQUU7TUFDcEMsYUFBYSxVQUFVLElBQUksV0FBVyxFQUFFO01BQ3hDLFlBQVksSUFBSSxVQUFVO0lBQzVCO0VBQ0Y7QUFDRiJ9
// denoCacheMetadata=5785112584728668196,14423845437486761606