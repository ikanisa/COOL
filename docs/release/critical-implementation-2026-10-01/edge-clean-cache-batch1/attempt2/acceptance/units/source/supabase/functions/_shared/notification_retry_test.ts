import { assertEquals } from "./test_assert.ts";
import { providerRetryFloor, retryAfterSeconds } from "./notification_retry.ts";

Deno.test("Retry-After parses seconds and HTTP dates without accepting arbitrary numeric/date strings", () => {
  const now = Date.parse("Tue, 29 Sep 2026 10:00:00 GMT");
  assertEquals(retryAfterSeconds("120", now), 120);
  assertEquals(retryAfterSeconds("Tue, 29 Sep 2026 10:03:00 GMT", now), 180);
  assertEquals(retryAfterSeconds("Tue, 29 Sep 2026 09:59:00 GMT", now), 0);
  for (
    const invalid of [null, "", "-1", "1.5", "garbage", "2026-09-29", "+60"]
  ) assertEquals(retryAfterSeconds(invalid, now), null);
});
Deno.test("oversized Retry-After floors terminalize rather than allowing an early clipped retry", () => {
  assertEquals(retryAfterSeconds("3600"), 3600);
  assertEquals(retryAfterSeconds("3601"), 3601);
  assertEquals(retryAfterSeconds("9".repeat(90)), 3601);
});
Deno.test("provider-specific retry floors respect minimums and ignore permanent/accepted headers", () => {
  assertEquals(providerRetryFloor("fcm", 429, null), 60);
  assertEquals(providerRetryFloor("fcm", 429, "1"), 60);
  assertEquals(providerRetryFloor("fcm", 503, "300"), 300);
  assertEquals(providerRetryFloor("apns", 503, null), 900);
  assertEquals(providerRetryFloor("apns", 500, "1200"), 1200);
  assertEquals(providerRetryFloor("apns", 429, null), 60);
  assertEquals(providerRetryFloor("fcm", 400, "900"), null);
  assertEquals(providerRetryFloor("fcm", 200, "900"), null);
});
