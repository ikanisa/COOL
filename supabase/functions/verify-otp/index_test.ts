import {
  createVerifyOtpHandler,
  type VerifyOtpHandlerDependencies,
} from "./index.ts";
import { HttpError } from "../_shared/auth.ts";

Deno.test("verify-otp hides internal failures from clients", async () => {
  let edgeFailureCalls = 0;
  const handler = createVerifyOtpHandler({
    createAdminClient: () =>
      ({}) as ReturnType<
        VerifyOtpHandlerDependencies["createAdminClient"]
      >,
    isAppCheckEnforced: () => false,
    requireAppCheckToken: async () => "unused-token",
    recordEdgeFunctionFailure: async () => {
      edgeFailureCalls += 1;
    },
  });

  const response = await handler(
    new Request("https://example.com/functions/v1/verify-otp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        phone: "+250781234567",
        code: "123456",
      }),
    }),
  );
  const payload = await response.json();

  if (response.status != 500) {
    throw new Error(`Expected 500 response, received ${response.status}`);
  }

  if (payload.message != "Failed to verify OTP") {
    throw new Error(`Unexpected payload: ${JSON.stringify(payload)}`);
  }

  if (JSON.stringify(payload).includes("is not a function")) {
    throw new Error(
      `Leaked internal error details: ${JSON.stringify(payload)}`,
    );
  }

  if (edgeFailureCalls != 1) {
    throw new Error(
      `Expected one edge failure record, received ${edgeFailureCalls}`,
    );
  }
});

Deno.test("verify-otp rejects missing App Check when enforcement is enabled", async () => {
  const handler = createVerifyOtpHandler({
    createAdminClient: () =>
      ({}) as ReturnType<
        VerifyOtpHandlerDependencies["createAdminClient"]
      >,
    isAppCheckEnforced: () => true,
    requireAppCheckToken: async () => {
      throw new HttpError(401, "Device attestation required.");
    },
    recordEdgeFunctionFailure: async () => {
      throw new Error("Should not record a failure for an auth rejection");
    },
  });

  const response = await handler(
    new Request("https://example.com/functions/v1/verify-otp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        phone: "+250781234567",
        code: "123456",
      }),
    }),
  );
  const payload = await response.json();

  if (response.status != 401) {
    throw new Error(`Expected 401 response, received ${response.status}`);
  }

  if (payload.message != "Device attestation required.") {
    throw new Error(`Unexpected payload: ${JSON.stringify(payload)}`);
  }
});
