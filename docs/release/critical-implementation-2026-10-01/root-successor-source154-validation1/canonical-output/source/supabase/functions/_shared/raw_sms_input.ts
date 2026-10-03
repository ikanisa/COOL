const encoder = new TextEncoder();

export function boundedRawSmsText(
  value: unknown,
  field: string,
  maxBytes: number,
): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${field} is required`);
  }
  if (encoder.encode(value).byteLength > maxBytes) {
    throw new Error(`${field} exceeds the accepted limit`);
  }
  // Validate without altering the evidence. Parsing may normalize separately.
  return value;
}
