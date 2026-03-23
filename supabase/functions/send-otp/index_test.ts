import {
  createSendOtpHandler,
  type SendOtpHandlerDependencies,
} from "./index.ts";

Deno.test("send-otp hides internal failures from clients", async () => {
  let edgeFailureCalls = 0;
  const handler = createSendOtpHandler({
    createAdminClient: () =>
      ({}) as ReturnType<
        SendOtpHandlerDependencies["createAdminClient"]
      >,
    recordEdgeFunctionFailure: async () => {
      edgeFailureCalls += 1;
    },
    sendOtpTemplate: async () => {
      throw new Error("should not reach send template");
    },
  });

  const response = await handler(
    new Request("https://example.com/functions/v1/send-otp", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone: "+250781234567" }),
    }),
  );
  const payload = await response.json();

  if (response.status != 500) {
    throw new Error(`Expected 500 response, received ${response.status}`);
  }

  if (payload.message != "Failed to send OTP") {
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
