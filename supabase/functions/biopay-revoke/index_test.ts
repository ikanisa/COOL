import { HttpError } from "../_shared/auth.ts";
import {
  type BiopayRevokeHandlerDependencies,
  createBiopayRevokeHandler,
} from "./index.ts";

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function buildRequest() {
  return new Request("https://example.com/functions/v1/biopay-revoke", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
      "x-firebase-appcheck": "fresh-token",
    },
    body: JSON.stringify({ reason: "user_request" }),
  });
}

function buildDeps(): BiopayRevokeHandlerDependencies {
  return {
    createAdminClient: () => ({} as ReturnType<
      BiopayRevokeHandlerDependencies["createAdminClient"]
    >),
    createUserClient: () =>
      ({
        auth: {
          getUser: async () => ({
            data: { user: { id: "user-1" } },
            error: null,
          }),
        },
        rpc: async () => ({
          data: {
            profile_id: "profile-1",
            public_id: "public-1",
          },
          error: null,
        }),
      }) as unknown as ReturnType<
        BiopayRevokeHandlerDependencies["createUserClient"]
      >,
    requireAppCheckToken: async () => "fresh-token",
    recordOperationalHealthEvent: async () => undefined,
    recordEdgeFunctionFailure: async () => undefined,
  };
}

Deno.test("biopay-revoke rejects requests without valid App Check attestation", async () => {
  const handler = createBiopayRevokeHandler({
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

Deno.test("biopay-revoke succeeds when App Check attestation is valid", async () => {
  const handler = createBiopayRevokeHandler(buildDeps());
  const response = await handler(buildRequest());
  const payload = await response.json();

  assertEquals(response.status, 200, "should accept attested requests");
  assertEquals(payload.success, true, "should report success");
  assertEquals(
    payload.data.profile_id,
    "profile-1",
    "should return the revoked profile payload",
  );
});
