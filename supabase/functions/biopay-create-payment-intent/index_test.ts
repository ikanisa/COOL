import { HttpError } from "../_shared/auth.ts";
import {
  type BiopayCreatePaymentIntentHandlerDependencies,
  createBiopayCreatePaymentIntentHandler,
} from "./index.ts";

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function buildRequest(body: Record<string, unknown> = {}) {
  return new Request(
    "https://example.com/functions/v1/biopay-create-payment-intent",
    {
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "application/json",
        "x-firebase-appcheck": "fresh-token",
      },
      body: JSON.stringify({
        profile_public_id: "public-1",
        match_score: 0.91,
        ...body,
      }),
    },
  );
}

function buildDeps(): BiopayCreatePaymentIntentHandlerDependencies {
  return {
    createAdminClient: () => ({} as ReturnType<
      BiopayCreatePaymentIntentHandlerDependencies["createAdminClient"]
    >),
    createUserClient: () =>
      ({
        auth: {
          getUser: async () => ({
            data: { user: { id: "user-1" } },
            error: null,
          }),
        },
      }) as BiopayCreatePaymentIntentHandlerDependencies[
        "createUserClient"
      ] extends (...args: never[]) => infer TResult ? TResult : never,
    requireAppCheckToken: async () => "fresh-token",
    fetchActiveProfile: async () => ({
      id: "profile-1",
      user_id: "payee-1",
      recipient_value: "0781234567",
      route_type: "phone_number",
      display_name: "Marie",
      public_id: "public-1",
    }),
    cancelPendingIntents: async () => undefined,
    createPaymentIntent: async () => ({
      id: "intent-1",
      nonce: "nonce-123",
      ussd_code: "*182*1*1*0781234567#",
      expires_at: "2026-04-10T12:05:00.000Z",
    }),
    buildUssdCode: (routeType, recipientValue) =>
      `ussd:${routeType}:${recipientValue}`,
    generateNonce: () => "nonce-123",
    now: () => new Date("2026-04-10T12:00:00.000Z"),
    recordOperationalHealthEvent: async () => undefined,
    recordEdgeFunctionFailure: async () => undefined,
  };
}

Deno.test("biopay-create-payment-intent rejects requests without valid App Check attestation", async () => {
  const handler = createBiopayCreatePaymentIntentHandler({
    ...buildDeps(),
    requireAppCheckToken: async () => {
      throw new HttpError(401, "Device attestation required.");
    },
  });

  const response = await handler(buildRequest());
  const payload = await response.json();

  assertEquals(response.status, 401, "should reject unattested requests");
  assertEquals(
    payload.message,
    "Device attestation required.",
    "should surface attestation failure",
  );
});

Deno.test("biopay-create-payment-intent succeeds when App Check attestation is valid", async () => {
  const operationalEvents: Array<Record<string, unknown>> = [];
  let cancelledUserId: string | null = null;
  let capturedPayload: Record<string, unknown> | null = null;

  const handler = createBiopayCreatePaymentIntentHandler({
    ...buildDeps(),
    cancelPendingIntents: async (_adminClient, userId) => {
      cancelledUserId = userId;
    },
    createPaymentIntent: async (_adminClient, options) => {
      capturedPayload = {
        userId: options.userId,
        profileId: options.profileId,
        matchScore: options.matchScore,
        recipientValue: options.recipientValue,
        routeType: options.routeType,
        ussdCode: options.ussdCode,
        nonce: options.nonce,
        expiresAt: options.expiresAt,
      };
      return {
        id: "intent-1",
        nonce: options.nonce,
        ussd_code: options.ussdCode,
        expires_at: options.expiresAt,
      };
    },
    recordOperationalHealthEvent: async (_adminClient, event) => {
      operationalEvents.push(event as Record<string, unknown>);
    },
  });

  const response = await handler(buildRequest());
  const payload = await response.json();

  assertEquals(response.status, 200, "should accept attested requests");
  assertEquals(payload.success, true, "should report success");
  assertEquals(cancelledUserId, "user-1", "should cancel pending intents");
  assertEquals(
    capturedPayload?.["profileId"],
    "profile-1",
    "should create intent for the resolved profile",
  );
  assertEquals(
    capturedPayload?.["ussdCode"],
    "ussd:phone_number:0781234567",
    "should build the server-side USSD code",
  );
  assertEquals(
    payload.data.display_name,
    "Marie",
    "should return the target display name",
  );
  assertEquals(
    operationalEvents[0]?.["component"],
    "payment_intent",
    "should emit operational telemetry for successful intent creation",
  );
});
