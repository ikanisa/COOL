const encoder = new TextEncoder();
const headerAliases = {
  member_name: new Set([
    "member",
    "member name",
    "member_name",
    "display name",
    "display_name",
    "name",
    "nom du membre",
    "nom",
    "izina ry'umunyamuryango",
    "jina la mwanachama"
  ]),
  momo_name: new Set([
    "momo name",
    "momo_name",
    "registered momo name",
    "registered_name",
    "account name",
    "nom momo",
    "nom du compte momo",
    "izina rya momo",
    "jina la momo"
  ]),
  momo_number: new Set([
    "momo number",
    "momo_number",
    "mobile money number",
    "mobile number",
    "phone",
    "phone number",
    "telephone",
    "numéro momo",
    "numero momo",
    "numéro de téléphone",
    "nimero ya momo",
    "nambari ya momo"
  ])
};
function cleanText(value) {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
}
function normalizedHeader(value) {
  return value.trim().toLowerCase().replace(/[\s_-]+/g, " ");
}
function headerKey(value) {
  const normalized = normalizedHeader(value);
  for (const [key, aliases] of Object.entries(headerAliases)){
    if (aliases.has(normalized)) return key;
  }
  return null;
}
function splitDelimitedLine(line, delimiter) {
  const values = [];
  let value = "";
  let quoted = false;
  for(let index = 0; index < line.length; index += 1){
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
function delimiterFor(line) {
  const candidates = [
    "\t",
    ",",
    ";"
  ];
  return candidates.sort((left, right)=>line.split(right).length - line.split(left).length)[0];
}
function looksLikePhone(value) {
  return /(?:\+?250|0)?7\d{8}/.test(value.replace(/[\s()-]/g, ""));
}
export function canonicalRwandaMomoNumber(value) {
  if (typeof value !== "string") return null;
  const compact = value.trim().replace(/[\s().-]/g, "");
  const digits = compact.startsWith("+") ? compact.slice(1) : compact;
  if (/^07[2389]\d{7}$/.test(digits)) return `+250${digits.slice(1)}`;
  if (/^2507[2389]\d{7}$/.test(digits)) return `+${digits}`;
  return null;
}
export function parseRosterText(content) {
  if (encoder.encode(content).byteLength > 512_000) {
    throw new Error("Roster text exceeds the 512 KB preview limit");
  }
  const lines = content.split(/\r?\n/).filter((line)=>line.trim());
  if (!lines.length) throw new Error("Roster has no member rows");
  if (lines.length > 501) {
    throw new Error("Roster preview is limited to 500 members");
  }
  const delimiter = delimiterFor(lines[0]);
  const first = splitDelimitedLine(lines[0], delimiter);
  const mappedHeaders = first.map(headerKey);
  const hasHeader = mappedHeaders.some((value)=>value != null) && !first.some(looksLikePhone);
  if (hasHeader && mappedHeaders.some((value, index)=>value !== null && mappedHeaders.indexOf(value) !== index)) {
    throw new Error("Roster contains ambiguous duplicate headers");
  }
  const indices = {
    member_name: hasHeader ? mappedHeaders.indexOf("member_name") : 0,
    momo_name: hasHeader ? mappedHeaders.indexOf("momo_name") : 1,
    momo_number: hasHeader ? mappedHeaders.indexOf("momo_number") : 2
  };
  if (hasHeader && indices.momo_number < 0) {
    throw new Error("Roster header must include a MoMo number column");
  }
  const dataLines = hasHeader ? lines.slice(1) : lines;
  if (!dataLines.length) throw new Error("Roster has no member rows");
  return dataLines.map((line, index)=>{
    const values = splitDelimitedLine(line, delimiter);
    const momoName = cleanText(indices.momo_name >= 0 ? values[indices.momo_name] : values[0]);
    return {
      source_row: index + (hasHeader ? 2 : 1),
      member_name: cleanText(indices.member_name >= 0 ? values[indices.member_name] : momoName) || momoName,
      momo_name: momoName,
      momo_number: cleanText(values[indices.momo_number]),
      confidence: 1
    };
  });
}
export function normalizeRosterCandidates(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 500) {
    throw new Error("Roster must contain between 1 and 500 candidate rows");
  }
  const seen = new Map();
  const rows = value.map((raw, index)=>{
    if (typeof raw !== "object" || raw == null || Array.isArray(raw)) {
      return {
        source_row: index + 1,
        member_name: "",
        momo_name: "",
        momo_number: "",
        confidence: 0,
        issues: [
          "Row is not a member record"
        ],
        ready: false
      };
    }
    const item = raw;
    const memberName = cleanText(item.member_name ?? item.name);
    const momoName = cleanText(item.momo_name ?? item.registered_name);
    const phone = canonicalRwandaMomoNumber(item.momo_number ?? item.phone);
    const sourceRow = Number.isInteger(item.source_row) && Number(item.source_row) > 0 ? Number(item.source_row) : index + 1;
    const confidenceValue = Number(item.confidence ?? 0);
    const confidence = Number.isFinite(confidenceValue) ? Math.max(0, Math.min(1, confidenceValue)) : 0;
    const issues = [];
    if ([
      ...memberName
    ].length < 2 || [
      ...memberName
    ].length > 120) {
      issues.push("Member name must contain 2 to 120 characters");
    }
    if ([
      ...momoName
    ].length < 2 || [
      ...momoName
    ].length > 120) {
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
      ready: issues.length === 0
    };
  });
  const readyRows = rows.filter((row)=>row.ready);
  return {
    rows,
    row_count: rows.length,
    ready_count: readyRows.length,
    error_count: rows.length - readyRows.length,
    can_submit: readyRows.length === rows.length,
    normalized_rows: readyRows.map((row)=>({
        member_name: row.member_name,
        momo_name: row.momo_name,
        momo_number: row.momo_number
      }))
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvcm9zdGVyX2ltcG9ydC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJleHBvcnQgdHlwZSBSb3N0ZXJJbXBvcnRTb3VyY2UgPSBcInRleHRcIiB8IFwiY3N2XCI7XG5cbmV4cG9ydCB0eXBlIFJvc3RlckNhbmRpZGF0ZSA9IHtcbiAgc291cmNlX3JvdzogbnVtYmVyO1xuICBtZW1iZXJfbmFtZTogc3RyaW5nO1xuICBtb21vX25hbWU6IHN0cmluZztcbiAgbW9tb19udW1iZXI6IHN0cmluZztcbiAgY29uZmlkZW5jZTogbnVtYmVyO1xufTtcblxuZXhwb3J0IHR5cGUgUm9zdGVyUHJldmlld1JvdyA9IFJvc3RlckNhbmRpZGF0ZSAmIHtcbiAgaXNzdWVzOiBzdHJpbmdbXTtcbiAgcmVhZHk6IGJvb2xlYW47XG59O1xuXG5leHBvcnQgdHlwZSBSb3N0ZXJQcmV2aWV3ID0ge1xuICByb3dzOiBSb3N0ZXJQcmV2aWV3Um93W107XG4gIHJvd19jb3VudDogbnVtYmVyO1xuICByZWFkeV9jb3VudDogbnVtYmVyO1xuICBlcnJvcl9jb3VudDogbnVtYmVyO1xuICBjYW5fc3VibWl0OiBib29sZWFuO1xuICBub3JtYWxpemVkX3Jvd3M6IEFycmF5PHtcbiAgICBtZW1iZXJfbmFtZTogc3RyaW5nO1xuICAgIG1vbW9fbmFtZTogc3RyaW5nO1xuICAgIG1vbW9fbnVtYmVyOiBzdHJpbmc7XG4gIH0+O1xufTtcblxuY29uc3QgZW5jb2RlciA9IG5ldyBUZXh0RW5jb2RlcigpO1xuY29uc3QgaGVhZGVyQWxpYXNlcyA9IHtcbiAgbWVtYmVyX25hbWU6IG5ldyBTZXQoW1xuICAgIFwibWVtYmVyXCIsXG4gICAgXCJtZW1iZXIgbmFtZVwiLFxuICAgIFwibWVtYmVyX25hbWVcIixcbiAgICBcImRpc3BsYXkgbmFtZVwiLFxuICAgIFwiZGlzcGxheV9uYW1lXCIsXG4gICAgXCJuYW1lXCIsXG4gICAgXCJub20gZHUgbWVtYnJlXCIsXG4gICAgXCJub21cIixcbiAgICBcIml6aW5hIHJ5J3VtdW55YW11cnlhbmdvXCIsXG4gICAgXCJqaW5hIGxhIG13YW5hY2hhbWFcIixcbiAgXSksXG4gIG1vbW9fbmFtZTogbmV3IFNldChbXG4gICAgXCJtb21vIG5hbWVcIixcbiAgICBcIm1vbW9fbmFtZVwiLFxuICAgIFwicmVnaXN0ZXJlZCBtb21vIG5hbWVcIixcbiAgICBcInJlZ2lzdGVyZWRfbmFtZVwiLFxuICAgIFwiYWNjb3VudCBuYW1lXCIsXG4gICAgXCJub20gbW9tb1wiLFxuICAgIFwibm9tIGR1IGNvbXB0ZSBtb21vXCIsXG4gICAgXCJpemluYSByeWEgbW9tb1wiLFxuICAgIFwiamluYSBsYSBtb21vXCIsXG4gIF0pLFxuICBtb21vX251bWJlcjogbmV3IFNldChbXG4gICAgXCJtb21vIG51bWJlclwiLFxuICAgIFwibW9tb19udW1iZXJcIixcbiAgICBcIm1vYmlsZSBtb25leSBudW1iZXJcIixcbiAgICBcIm1vYmlsZSBudW1iZXJcIixcbiAgICBcInBob25lXCIsXG4gICAgXCJwaG9uZSBudW1iZXJcIixcbiAgICBcInRlbGVwaG9uZVwiLFxuICAgIFwibnVtw6lybyBtb21vXCIsXG4gICAgXCJudW1lcm8gbW9tb1wiLFxuICAgIFwibnVtw6lybyBkZSB0w6lsw6lwaG9uZVwiLFxuICAgIFwibmltZXJvIHlhIG1vbW9cIixcbiAgICBcIm5hbWJhcmkgeWEgbW9tb1wiLFxuICBdKSxcbn07XG5cbmZ1bmN0aW9uIGNsZWFuVGV4dCh2YWx1ZTogdW5rbm93bik6IHN0cmluZyB7XG4gIHJldHVybiB0eXBlb2YgdmFsdWUgPT09IFwic3RyaW5nXCIgPyB2YWx1ZS50cmltKCkucmVwbGFjZSgvXFxzKy9nLCBcIiBcIikgOiBcIlwiO1xufVxuXG5mdW5jdGlvbiBub3JtYWxpemVkSGVhZGVyKHZhbHVlOiBzdHJpbmcpOiBzdHJpbmcge1xuICByZXR1cm4gdmFsdWUudHJpbSgpLnRvTG93ZXJDYXNlKCkucmVwbGFjZSgvW1xcc18tXSsvZywgXCIgXCIpO1xufVxuXG5mdW5jdGlvbiBoZWFkZXJLZXkodmFsdWU6IHN0cmluZyk6IGtleW9mIHR5cGVvZiBoZWFkZXJBbGlhc2VzIHwgbnVsbCB7XG4gIGNvbnN0IG5vcm1hbGl6ZWQgPSBub3JtYWxpemVkSGVhZGVyKHZhbHVlKTtcbiAgZm9yIChjb25zdCBba2V5LCBhbGlhc2VzXSBvZiBPYmplY3QuZW50cmllcyhoZWFkZXJBbGlhc2VzKSkge1xuICAgIGlmIChhbGlhc2VzLmhhcyhub3JtYWxpemVkKSkgcmV0dXJuIGtleSBhcyBrZXlvZiB0eXBlb2YgaGVhZGVyQWxpYXNlcztcbiAgfVxuICByZXR1cm4gbnVsbDtcbn1cblxuZnVuY3Rpb24gc3BsaXREZWxpbWl0ZWRMaW5lKGxpbmU6IHN0cmluZywgZGVsaW1pdGVyOiBzdHJpbmcpOiBzdHJpbmdbXSB7XG4gIGNvbnN0IHZhbHVlczogc3RyaW5nW10gPSBbXTtcbiAgbGV0IHZhbHVlID0gXCJcIjtcbiAgbGV0IHF1b3RlZCA9IGZhbHNlO1xuICBmb3IgKGxldCBpbmRleCA9IDA7IGluZGV4IDwgbGluZS5sZW5ndGg7IGluZGV4ICs9IDEpIHtcbiAgICBjb25zdCBjaGFyYWN0ZXIgPSBsaW5lW2luZGV4XTtcbiAgICBpZiAoY2hhcmFjdGVyID09PSAnXCInKSB7XG4gICAgICBpZiAocXVvdGVkICYmIGxpbmVbaW5kZXggKyAxXSA9PT0gJ1wiJykge1xuICAgICAgICB2YWx1ZSArPSAnXCInO1xuICAgICAgICBpbmRleCArPSAxO1xuICAgICAgfSBlbHNlIHtcbiAgICAgICAgcXVvdGVkID0gIXF1b3RlZDtcbiAgICAgIH1cbiAgICB9IGVsc2UgaWYgKGNoYXJhY3RlciA9PT0gZGVsaW1pdGVyICYmICFxdW90ZWQpIHtcbiAgICAgIHZhbHVlcy5wdXNoKHZhbHVlLnRyaW0oKSk7XG4gICAgICB2YWx1ZSA9IFwiXCI7XG4gICAgfSBlbHNlIHtcbiAgICAgIHZhbHVlICs9IGNoYXJhY3RlcjtcbiAgICB9XG4gIH1cbiAgaWYgKHF1b3RlZCkgdGhyb3cgbmV3IEVycm9yKFwiUm9zdGVyIGNvbnRhaW5zIGFuIHVudGVybWluYXRlZCBxdW90ZWQgdmFsdWVcIik7XG4gIHZhbHVlcy5wdXNoKHZhbHVlLnRyaW0oKSk7XG4gIHJldHVybiB2YWx1ZXM7XG59XG5cbmZ1bmN0aW9uIGRlbGltaXRlckZvcihsaW5lOiBzdHJpbmcpOiBzdHJpbmcge1xuICBjb25zdCBjYW5kaWRhdGVzID0gW1wiXFx0XCIsIFwiLFwiLCBcIjtcIl07XG4gIHJldHVybiBjYW5kaWRhdGVzLnNvcnQoKGxlZnQsIHJpZ2h0KSA9PlxuICAgIGxpbmUuc3BsaXQocmlnaHQpLmxlbmd0aCAtIGxpbmUuc3BsaXQobGVmdCkubGVuZ3RoXG4gIClbMF07XG59XG5cbmZ1bmN0aW9uIGxvb2tzTGlrZVBob25lKHZhbHVlOiBzdHJpbmcpOiBib29sZWFuIHtcbiAgcmV0dXJuIC8oPzpcXCs/MjUwfDApPzdcXGR7OH0vLnRlc3QodmFsdWUucmVwbGFjZSgvW1xccygpLV0vZywgXCJcIikpO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gY2Fub25pY2FsUndhbmRhTW9tb051bWJlcih2YWx1ZTogdW5rbm93bik6IHN0cmluZyB8IG51bGwge1xuICBpZiAodHlwZW9mIHZhbHVlICE9PSBcInN0cmluZ1wiKSByZXR1cm4gbnVsbDtcbiAgY29uc3QgY29tcGFjdCA9IHZhbHVlLnRyaW0oKS5yZXBsYWNlKC9bXFxzKCkuLV0vZywgXCJcIik7XG4gIGNvbnN0IGRpZ2l0cyA9IGNvbXBhY3Quc3RhcnRzV2l0aChcIitcIikgPyBjb21wYWN0LnNsaWNlKDEpIDogY29tcGFjdDtcbiAgaWYgKC9eMDdbMjM4OV1cXGR7N30kLy50ZXN0KGRpZ2l0cykpIHJldHVybiBgKzI1MCR7ZGlnaXRzLnNsaWNlKDEpfWA7XG4gIGlmICgvXjI1MDdbMjM4OV1cXGR7N30kLy50ZXN0KGRpZ2l0cykpIHJldHVybiBgKyR7ZGlnaXRzfWA7XG4gIHJldHVybiBudWxsO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gcGFyc2VSb3N0ZXJUZXh0KGNvbnRlbnQ6IHN0cmluZyk6IFJvc3RlckNhbmRpZGF0ZVtdIHtcbiAgaWYgKGVuY29kZXIuZW5jb2RlKGNvbnRlbnQpLmJ5dGVMZW5ndGggPiA1MTJfMDAwKSB7XG4gICAgdGhyb3cgbmV3IEVycm9yKFwiUm9zdGVyIHRleHQgZXhjZWVkcyB0aGUgNTEyIEtCIHByZXZpZXcgbGltaXRcIik7XG4gIH1cbiAgY29uc3QgbGluZXMgPSBjb250ZW50LnNwbGl0KC9cXHI/XFxuLykuZmlsdGVyKChsaW5lKSA9PiBsaW5lLnRyaW0oKSk7XG4gIGlmICghbGluZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoXCJSb3N0ZXIgaGFzIG5vIG1lbWJlciByb3dzXCIpO1xuICBpZiAobGluZXMubGVuZ3RoID4gNTAxKSB7XG4gICAgdGhyb3cgbmV3IEVycm9yKFwiUm9zdGVyIHByZXZpZXcgaXMgbGltaXRlZCB0byA1MDAgbWVtYmVyc1wiKTtcbiAgfVxuICBjb25zdCBkZWxpbWl0ZXIgPSBkZWxpbWl0ZXJGb3IobGluZXNbMF0pO1xuICBjb25zdCBmaXJzdCA9IHNwbGl0RGVsaW1pdGVkTGluZShsaW5lc1swXSwgZGVsaW1pdGVyKTtcbiAgY29uc3QgbWFwcGVkSGVhZGVycyA9IGZpcnN0Lm1hcChoZWFkZXJLZXkpO1xuICBjb25zdCBoYXNIZWFkZXIgPSBtYXBwZWRIZWFkZXJzLnNvbWUoKHZhbHVlKSA9PiB2YWx1ZSAhPSBudWxsKSAmJlxuICAgICFmaXJzdC5zb21lKGxvb2tzTGlrZVBob25lKTtcbiAgaWYgKFxuICAgIGhhc0hlYWRlciAmJlxuICAgIG1hcHBlZEhlYWRlcnMuc29tZSgodmFsdWUsIGluZGV4KSA9PlxuICAgICAgdmFsdWUgIT09IG51bGwgJiYgbWFwcGVkSGVhZGVycy5pbmRleE9mKHZhbHVlKSAhPT0gaW5kZXhcbiAgICApXG4gICkge1xuICAgIHRocm93IG5ldyBFcnJvcihcIlJvc3RlciBjb250YWlucyBhbWJpZ3VvdXMgZHVwbGljYXRlIGhlYWRlcnNcIik7XG4gIH1cbiAgY29uc3QgaW5kaWNlcyA9IHtcbiAgICBtZW1iZXJfbmFtZTogaGFzSGVhZGVyID8gbWFwcGVkSGVhZGVycy5pbmRleE9mKFwibWVtYmVyX25hbWVcIikgOiAwLFxuICAgIG1vbW9fbmFtZTogaGFzSGVhZGVyID8gbWFwcGVkSGVhZGVycy5pbmRleE9mKFwibW9tb19uYW1lXCIpIDogMSxcbiAgICBtb21vX251bWJlcjogaGFzSGVhZGVyID8gbWFwcGVkSGVhZGVycy5pbmRleE9mKFwibW9tb19udW1iZXJcIikgOiAyLFxuICB9O1xuICBpZiAoaGFzSGVhZGVyICYmIGluZGljZXMubW9tb19udW1iZXIgPCAwKSB7XG4gICAgdGhyb3cgbmV3IEVycm9yKFwiUm9zdGVyIGhlYWRlciBtdXN0IGluY2x1ZGUgYSBNb01vIG51bWJlciBjb2x1bW5cIik7XG4gIH1cbiAgY29uc3QgZGF0YUxpbmVzID0gaGFzSGVhZGVyID8gbGluZXMuc2xpY2UoMSkgOiBsaW5lcztcbiAgaWYgKCFkYXRhTGluZXMubGVuZ3RoKSB0aHJvdyBuZXcgRXJyb3IoXCJSb3N0ZXIgaGFzIG5vIG1lbWJlciByb3dzXCIpO1xuICByZXR1cm4gZGF0YUxpbmVzLm1hcCgobGluZSwgaW5kZXgpID0+IHtcbiAgICBjb25zdCB2YWx1ZXMgPSBzcGxpdERlbGltaXRlZExpbmUobGluZSwgZGVsaW1pdGVyKTtcbiAgICBjb25zdCBtb21vTmFtZSA9IGNsZWFuVGV4dChcbiAgICAgIGluZGljZXMubW9tb19uYW1lID49IDAgPyB2YWx1ZXNbaW5kaWNlcy5tb21vX25hbWVdIDogdmFsdWVzWzBdLFxuICAgICk7XG4gICAgcmV0dXJuIHtcbiAgICAgIHNvdXJjZV9yb3c6IGluZGV4ICsgKGhhc0hlYWRlciA/IDIgOiAxKSxcbiAgICAgIG1lbWJlcl9uYW1lOiBjbGVhblRleHQoXG4gICAgICAgIGluZGljZXMubWVtYmVyX25hbWUgPj0gMCA/IHZhbHVlc1tpbmRpY2VzLm1lbWJlcl9uYW1lXSA6IG1vbW9OYW1lLFxuICAgICAgKSB8fCBtb21vTmFtZSxcbiAgICAgIG1vbW9fbmFtZTogbW9tb05hbWUsXG4gICAgICBtb21vX251bWJlcjogY2xlYW5UZXh0KHZhbHVlc1tpbmRpY2VzLm1vbW9fbnVtYmVyXSksXG4gICAgICBjb25maWRlbmNlOiAxLFxuICAgIH07XG4gIH0pO1xufVxuXG5leHBvcnQgZnVuY3Rpb24gbm9ybWFsaXplUm9zdGVyQ2FuZGlkYXRlcyh2YWx1ZTogdW5rbm93bik6IFJvc3RlclByZXZpZXcge1xuICBpZiAoIUFycmF5LmlzQXJyYXkodmFsdWUpIHx8IHZhbHVlLmxlbmd0aCA8IDEgfHwgdmFsdWUubGVuZ3RoID4gNTAwKSB7XG4gICAgdGhyb3cgbmV3IEVycm9yKFwiUm9zdGVyIG11c3QgY29udGFpbiBiZXR3ZWVuIDEgYW5kIDUwMCBjYW5kaWRhdGUgcm93c1wiKTtcbiAgfVxuICBjb25zdCBzZWVuID0gbmV3IE1hcDxzdHJpbmcsIG51bWJlcj4oKTtcbiAgY29uc3Qgcm93czogUm9zdGVyUHJldmlld1Jvd1tdID0gdmFsdWUubWFwKChyYXcsIGluZGV4KSA9PiB7XG4gICAgaWYgKHR5cGVvZiByYXcgIT09IFwib2JqZWN0XCIgfHwgcmF3ID09IG51bGwgfHwgQXJyYXkuaXNBcnJheShyYXcpKSB7XG4gICAgICByZXR1cm4ge1xuICAgICAgICBzb3VyY2Vfcm93OiBpbmRleCArIDEsXG4gICAgICAgIG1lbWJlcl9uYW1lOiBcIlwiLFxuICAgICAgICBtb21vX25hbWU6IFwiXCIsXG4gICAgICAgIG1vbW9fbnVtYmVyOiBcIlwiLFxuICAgICAgICBjb25maWRlbmNlOiAwLFxuICAgICAgICBpc3N1ZXM6IFtcIlJvdyBpcyBub3QgYSBtZW1iZXIgcmVjb3JkXCJdLFxuICAgICAgICByZWFkeTogZmFsc2UsXG4gICAgICB9O1xuICAgIH1cbiAgICBjb25zdCBpdGVtID0gcmF3IGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xuICAgIGNvbnN0IG1lbWJlck5hbWUgPSBjbGVhblRleHQoaXRlbS5tZW1iZXJfbmFtZSA/PyBpdGVtLm5hbWUpO1xuICAgIGNvbnN0IG1vbW9OYW1lID0gY2xlYW5UZXh0KGl0ZW0ubW9tb19uYW1lID8/IGl0ZW0ucmVnaXN0ZXJlZF9uYW1lKTtcbiAgICBjb25zdCBwaG9uZSA9IGNhbm9uaWNhbFJ3YW5kYU1vbW9OdW1iZXIoaXRlbS5tb21vX251bWJlciA/PyBpdGVtLnBob25lKTtcbiAgICBjb25zdCBzb3VyY2VSb3cgPVxuICAgICAgTnVtYmVyLmlzSW50ZWdlcihpdGVtLnNvdXJjZV9yb3cpICYmIE51bWJlcihpdGVtLnNvdXJjZV9yb3cpID4gMFxuICAgICAgICA/IE51bWJlcihpdGVtLnNvdXJjZV9yb3cpXG4gICAgICAgIDogaW5kZXggKyAxO1xuICAgIGNvbnN0IGNvbmZpZGVuY2VWYWx1ZSA9IE51bWJlcihpdGVtLmNvbmZpZGVuY2UgPz8gMCk7XG4gICAgY29uc3QgY29uZmlkZW5jZSA9IE51bWJlci5pc0Zpbml0ZShjb25maWRlbmNlVmFsdWUpXG4gICAgICA/IE1hdGgubWF4KDAsIE1hdGgubWluKDEsIGNvbmZpZGVuY2VWYWx1ZSkpXG4gICAgICA6IDA7XG4gICAgY29uc3QgaXNzdWVzOiBzdHJpbmdbXSA9IFtdO1xuICAgIGlmIChbLi4ubWVtYmVyTmFtZV0ubGVuZ3RoIDwgMiB8fCBbLi4ubWVtYmVyTmFtZV0ubGVuZ3RoID4gMTIwKSB7XG4gICAgICBpc3N1ZXMucHVzaChcIk1lbWJlciBuYW1lIG11c3QgY29udGFpbiAyIHRvIDEyMCBjaGFyYWN0ZXJzXCIpO1xuICAgIH1cbiAgICBpZiAoWy4uLm1vbW9OYW1lXS5sZW5ndGggPCAyIHx8IFsuLi5tb21vTmFtZV0ubGVuZ3RoID4gMTIwKSB7XG4gICAgICBpc3N1ZXMucHVzaChcIlJlZ2lzdGVyZWQgTW9NbyBuYW1lIG11c3QgY29udGFpbiAyIHRvIDEyMCBjaGFyYWN0ZXJzXCIpO1xuICAgIH1cbiAgICBpZiAoL1tcXHUwMDAwLVxcdTAwMWZcXHUwMDdmXS8udGVzdChtZW1iZXJOYW1lICsgbW9tb05hbWUpKSB7XG4gICAgICBpc3N1ZXMucHVzaChcIk5hbWVzIGNhbm5vdCBjb250YWluIGNvbnRyb2wgY2hhcmFjdGVyc1wiKTtcbiAgICB9XG4gICAgaWYgKC9eWz0rXFwtQF0vLnRlc3QobWVtYmVyTmFtZSkgfHwgL15bPStcXC1AXS8udGVzdChtb21vTmFtZSkpIHtcbiAgICAgIGlzc3Vlcy5wdXNoKFwiTmFtZXMgY2Fubm90IGJlZ2luIHdpdGggc3ByZWFkc2hlZXQgZm9ybXVsYSBjaGFyYWN0ZXJzXCIpO1xuICAgIH1cbiAgICBpZiAoIXBob25lKSBpc3N1ZXMucHVzaChcIkVudGVyIGEgdmFsaWQgZnVsbCBSd2FuZGEgTW9NbyBudW1iZXJcIik7XG4gICAgaWYgKGNvbmZpZGVuY2UgPCAwLjgpIGlzc3Vlcy5wdXNoKFwiRXh0cmFjdGlvbiBjb25maWRlbmNlIGlzIGJlbG93IDgwJVwiKTtcbiAgICBpZiAocGhvbmUpIHtcbiAgICAgIGNvbnN0IGZpcnN0Um93ID0gc2Vlbi5nZXQocGhvbmUpO1xuICAgICAgaWYgKGZpcnN0Um93ICE9IG51bGwpIHtcbiAgICAgICAgaXNzdWVzLnB1c2goYE1vTW8gbnVtYmVyIGR1cGxpY2F0ZXMgc291cmNlIHJvdyAke2ZpcnN0Um93fWApO1xuICAgICAgfSBlbHNlIHtcbiAgICAgICAgc2Vlbi5zZXQocGhvbmUsIHNvdXJjZVJvdyk7XG4gICAgICB9XG4gICAgfVxuICAgIHJldHVybiB7XG4gICAgICBzb3VyY2Vfcm93OiBzb3VyY2VSb3csXG4gICAgICBtZW1iZXJfbmFtZTogbWVtYmVyTmFtZSxcbiAgICAgIG1vbW9fbmFtZTogbW9tb05hbWUsXG4gICAgICBtb21vX251bWJlcjogcGhvbmUgPz8gY2xlYW5UZXh0KGl0ZW0ubW9tb19udW1iZXIgPz8gaXRlbS5waG9uZSksXG4gICAgICBjb25maWRlbmNlLFxuICAgICAgaXNzdWVzLFxuICAgICAgcmVhZHk6IGlzc3Vlcy5sZW5ndGggPT09IDAsXG4gICAgfTtcbiAgfSk7XG4gIGNvbnN0IHJlYWR5Um93cyA9IHJvd3MuZmlsdGVyKChyb3cpID0+IHJvdy5yZWFkeSk7XG4gIHJldHVybiB7XG4gICAgcm93cyxcbiAgICByb3dfY291bnQ6IHJvd3MubGVuZ3RoLFxuICAgIHJlYWR5X2NvdW50OiByZWFkeVJvd3MubGVuZ3RoLFxuICAgIGVycm9yX2NvdW50OiByb3dzLmxlbmd0aCAtIHJlYWR5Um93cy5sZW5ndGgsXG4gICAgY2FuX3N1Ym1pdDogcmVhZHlSb3dzLmxlbmd0aCA9PT0gcm93cy5sZW5ndGgsXG4gICAgbm9ybWFsaXplZF9yb3dzOiByZWFkeVJvd3MubWFwKChyb3cpID0+ICh7XG4gICAgICBtZW1iZXJfbmFtZTogcm93Lm1lbWJlcl9uYW1lLFxuICAgICAgbW9tb19uYW1lOiByb3cubW9tb19uYW1lLFxuICAgICAgbW9tb19udW1iZXI6IHJvdy5tb21vX251bWJlcixcbiAgICB9KSksXG4gIH07XG59XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBNEJBLE1BQU0sVUFBVSxJQUFJO0FBQ3BCLE1BQU0sZ0JBQWdCO0VBQ3BCLGFBQWEsSUFBSSxJQUFJO0lBQ25CO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0dBQ0Q7RUFDRCxXQUFXLElBQUksSUFBSTtJQUNqQjtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7R0FDRDtFQUNELGFBQWEsSUFBSSxJQUFJO0lBQ25CO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtHQUNEO0FBQ0g7QUFFQSxTQUFTLFVBQVUsS0FBYztFQUMvQixPQUFPLE9BQU8sVUFB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
// denoCacheMetadata=1922312921411103500,3872057967781063209