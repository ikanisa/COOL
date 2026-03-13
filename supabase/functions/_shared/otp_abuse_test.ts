import {
  extractClientIp,
  hashOtpRateActorKey,
} from "./otp_abuse.ts";

Deno.test("extractClientIp prefers direct proxy headers", () => {
  const request = new Request("https://example.com", {
    headers: {
      "cf-connecting-ip": "203.0.113.7",
      "x-forwarded-for": "198.51.100.2, 198.51.100.3",
    },
  });

  const ip = extractClientIp(request);

  if (ip != "203.0.113.7") {
    throw new Error(`Expected direct client IP, received ${ip}`);
  }
});

Deno.test("extractClientIp falls back to first forwarded IP", () => {
  const request = new Request("https://example.com", {
    headers: {
      "x-forwarded-for": "198.51.100.2, 198.51.100.3",
    },
  });

  const ip = extractClientIp(request);

  if (ip != "198.51.100.2") {
    throw new Error(`Expected first forwarded IP, received ${ip}`);
  }
});

Deno.test("hashOtpRateActorKey is stable for normalized input", async () => {
  const first = await hashOtpRateActorKey(" 203.0.113.7 ");
  const second = await hashOtpRateActorKey("203.0.113.7");

  if (first != second) {
    throw new Error("Expected hashed actor keys to match");
  }
});

Deno.test("hashOtpRateActorKey keeps send and verify scopes distinct", async () => {
  const sendPhone = await hashOtpRateActorKey("send_phone:+250788123456");
  const verifyPhone = await hashOtpRateActorKey("verify_phone:+250788123456");

  if (sendPhone == verifyPhone) {
    throw new Error("Expected different OTP rate scopes to hash differently");
  }
});
