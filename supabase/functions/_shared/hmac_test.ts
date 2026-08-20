import { assertEquals } from "./test_assert.ts";
import { hmacSha256Hex, verifyTimestampedHmac } from "./hmac.ts";

Deno.test("verifies timestamped webhook HMAC", async () => {
  const timestamp = "1787220000";
  const body = '{"source_uid":"message-1"}';
  const signature = await hmacSha256Hex("secret", `${timestamp}.${body}`);
  assertEquals(
    await verifyTimestampedHmac("secret", timestamp, `v1=${signature}`, body, 1787220000 * 1000),
    true,
  );
  assertEquals(
    await verifyTimestampedHmac("wrong", timestamp, `v1=${signature}`, body, 1787220000 * 1000),
    false,
  );
});
