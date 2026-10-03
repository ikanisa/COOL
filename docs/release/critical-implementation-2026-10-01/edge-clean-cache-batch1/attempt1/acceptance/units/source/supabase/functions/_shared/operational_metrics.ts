/** Enum-only telemetry. No recipient, evidence, token or diagnostic payload. */
export const RECEIPT_METRIC_CODES = [
  "receipt_ack_generated",
  "receipt_rejected",
  "receipt_processing_accepted",
  "receipt_processing_deferred",
] as const;
export type ReceiptMetricCode = typeof RECEIPT_METRIC_CODES[number];
export type MetricWriter = (
  code: ReceiptMetricCode,
  durationMs: number | null,
  signal: AbortSignal,
) => Promise<boolean>;

/** A failed/missing/slow metric must never change the durable receipt outcome. */
export async function recordReceiptMetric(
  code: ReceiptMetricCode,
  durationMs: number | null,
  write: MetricWriter,
  deadlineMs = 200,
): Promise<boolean> {
  if (
    !RECEIPT_METRIC_CODES.includes(code) ||
    (durationMs !== null &&
      (!Number.isInteger(durationMs) || durationMs < 0 ||
        durationMs > 120_000)) ||
    !Number.isInteger(deadlineMs) || deadlineMs < 1 || deadlineMs > 250
  ) return false;
  const controller = new AbortController();
  let timer: number | undefined;
  try {
    const deadline = new Promise<false>((resolve) => {
      timer = setTimeout(() => {
        controller.abort();
        resolve(false);
      }, deadlineMs);
    });
    return await Promise.race([
      write(code, durationMs, controller.signal),
      deadline,
    ]) === true;
  } catch {
    return false;
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

export function elapsedReceiptMs(start: number): number | null {
  const value = Math.ceil(performance.now() - start);
  return Number.isFinite(value) && value >= 0 && value <= 120_000
    ? value
    : null;
}
