import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  elapsedReceiptMs,
  ReceiptMetricCode,
  recordReceiptMetric,
} from "./operational_metrics.ts";

Deno.test("telemetry passes only bounded enum and integer fields", async () => {
  const seen: unknown[] = [];
  assert(
    await recordReceiptMetric(
      "receipt_ack_generated",
      12,
      async (code, ms, signal) => {
        seen.push(code, ms, signal.aborted);
        return true;
      },
    ),
  );
  assertEquals(seen, ["receipt_ack_generated", 12, false]);
  assert(
    await recordReceiptMetric(
      "receipt_processing_deferred",
      null,
      async () => true,
    ),
  );
});
Deno.test("private/arbitrary metric names and invalid durations never invoke writer", async () => {
  let calls = 0;
  const writer = async () => {
    calls++;
    return true;
  };
  assertEquals(
    await recordReceiptMetric(
      "secret-phone-250788123456" as ReceiptMetricCode,
      1,
      writer,
    ),
    false,
  );
  for (const ms of [-1, 0.5, 120001, NaN, Infinity]) {
    assertEquals(
      await recordReceiptMetric("receipt_rejected", ms, writer),
      false,
    );
  }
  assertEquals(calls, 0);
});
Deno.test("missing malformed false and exceptional metric ACK cannot report a sample", async () => {
  for (const result of [null, {}, "true", false]) {
    assertEquals(
      await recordReceiptMetric(
        "receipt_ack_generated",
        0,
        async () => result as boolean,
      ),
      false,
    );
  }
  assertEquals(
    await recordReceiptMetric("receipt_ack_generated", 0, () => {
      throw new Error("secret-provider-credential-canary");
    }),
    false,
  );
});
Deno.test("a slow writer is aborted and ignored at bounded deadline", async () => {
  let aborted = false;
  const started = performance.now();
  const result = await recordReceiptMetric(
    "receipt_ack_generated",
    0,
    (_code, _ms, signal) =>
      new Promise<boolean>((_resolve, reject) => {
        signal.addEventListener("abort", () => {
          aborted = true;
          reject(new Error("synthetic timeout"));
        }, { once: true });
      }),
    20,
  );
  assertEquals(result, false);
  assert(aborted);
  assert(performance.now() - started < 1000);
});
Deno.test("elapsed duration outside the bounded window stays unmeasured", () => {
  assertEquals(elapsedReceiptMs(performance.now() + 1000), null);
  assertEquals(elapsedReceiptMs(performance.now() - 121000), null);
  assertEquals(elapsedReceiptMs(NaN), null);
  assert(Number.isInteger(elapsedReceiptMs(performance.now())));
});
