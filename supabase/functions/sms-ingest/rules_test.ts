import {
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.220.1/assert/mod.ts";

import {
  buildDeviceMessageKey,
  isApprovedSender,
  normalizeIngestionSource,
  parseReceivedAt,
} from "./rules.ts";

Deno.test("isApprovedSender accepts supported Mobile Money aliases only", () => {
  assertEquals(isApprovedSender("M-Money"), true);
  assertEquals(isApprovedSender("MTN MoMo Rwanda"), true);
  assertEquals(isApprovedSender("mobile_money"), true);
  assertEquals(isApprovedSender("Bank Alerts"), false);
});

Deno.test("normalizeIngestionSource lowercases valid values and falls back safely", () => {
  assertEquals(
    normalizeIngestionSource("ANDROID_SMS_INITIAL_SYNC"),
    "android_sms_initial_sync",
  );
  assertEquals(
    normalizeIngestionSource("android_sms_listener_background"),
    "android_sms_listener_background",
  );
  assertEquals(
    normalizeIngestionSource("unexpected-client-value"),
    "android_sms_listener",
  );
  assertEquals(normalizeIngestionSource(null), "android_sms_listener");
});

Deno.test("parseReceivedAt preserves valid timestamps and falls back on invalid input", () => {
  const fallbackNow = new Date("2026-03-15T12:00:00.000Z");

  assertEquals(
    parseReceivedAt("2026-03-10T08:15:00+02:00", fallbackNow),
    "2026-03-10T06:15:00.000Z",
  );
  assertEquals(parseReceivedAt("not-a-date", fallbackNow), fallbackNow.toISOString());
  assertEquals(parseReceivedAt(null, fallbackNow), fallbackNow.toISOString());
});

Deno.test("buildDeviceMessageKey normalizes sender noise and SMS spacing", async () => {
  const first = await buildDeviceMessageKey({
    sender: "M-Money",
    smsBody: "Payment   of  10,000 RWF confirmed",
    smsReceivedAt: "2026-03-10T06:15:00.000Z",
  });
  const second = await buildDeviceMessageKey({
    sender: "m money",
    smsBody: " Payment of 10,000 RWF confirmed ",
    smsReceivedAt: "2026-03-10T06:15:00.000Z",
  });
  const third = await buildDeviceMessageKey({
    sender: "M-Money",
    smsBody: "Payment of 11,000 RWF confirmed",
    smsReceivedAt: "2026-03-10T06:15:00.000Z",
  });

  assertEquals(first, second);
  assertNotEquals(first, third);
});
