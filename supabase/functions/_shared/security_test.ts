import {
  constantTimeEquals,
  getReviewOtpConfig,
  isReviewOtpMatch,
  resolveReviewOtp,
} from "./security.ts";

function withEnv(
  entries: Record<string, string | null>,
  run: () => void | Promise<void>,
) {
  const previous = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries(entries)) {
    previous.set(key, Deno.env.get(key));
    if (value == null) {
      Deno.env.delete(key);
    } else {
      Deno.env.set(key, value);
    }
  }

  return Promise.resolve(run()).finally(() => {
    for (const [key, value] of previous.entries()) {
      if (value == null) {
        Deno.env.delete(key);
      } else {
        Deno.env.set(key, value);
      }
    }
  });
}

Deno.test("review OTP helpers normalize configured phone once and match consistently", async () => {
  await withEnv(
    {
      OTP_TEST_PHONE: "+250788767816",
      OTP_TEST_CODE: "123456",
    },
    () => {
      const config = getReviewOtpConfig();
      if (!config) {
        throw new Error("Expected review OTP config to resolve.");
      }

      if (config.normalizedPhone !== "+250788767816") {
        throw new Error(
          `Unexpected normalized phone: ${config.normalizedPhone}`,
        );
      }

      if (resolveReviewOtp("+250788767816") !== "123456") {
        throw new Error("Expected review OTP to resolve for configured phone.");
      }

      if (!isReviewOtpMatch("+250788767816", "123456")) {
        throw new Error(
          "Expected review OTP matcher to accept configured pair.",
        );
      }

      if (isReviewOtpMatch("+250788767816", "654321")) {
        throw new Error("Expected review OTP matcher to reject wrong code.");
      }
    },
  );
});

Deno.test("review OTP helpers disable themselves on invalid config", async () => {
  await withEnv(
    {
      OTP_TEST_PHONE: "invalid",
      OTP_TEST_CODE: "12",
    },
    () => {
      if (getReviewOtpConfig() != null) {
        throw new Error("Expected invalid review OTP config to be ignored.");
      }
      if (resolveReviewOtp("+250788767816") != null) {
        throw new Error("Expected resolveReviewOtp to return null.");
      }
      if (isReviewOtpMatch("+250788767816", "123456")) {
        throw new Error("Expected invalid config to disable matcher.");
      }
    },
  );
});

Deno.test("constantTimeEquals rejects partial and length-mismatched bearer tokens", () => {
  if (!constantTimeEquals("service-role-secret", "service-role-secret")) {
    throw new Error("Expected identical strings to match.");
  }

  if (constantTimeEquals("service-role-secret", "service-role-secrex")) {
    throw new Error("Expected same-length mismatch to be rejected.");
  }

  if (constantTimeEquals("service-role-secret", "service-role")) {
    throw new Error("Expected prefix token to be rejected.");
  }
});
