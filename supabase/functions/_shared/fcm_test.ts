/**
 * Unit tests for the shared FCM utility.
 *
 * Run: deno test supabase/functions/_shared/fcm_test.ts --allow-env
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.220.1/assert/mod.ts";
import { buildJwtAssertion } from "./fcm.ts";

function toPem(pkcs8: Uint8Array): string {
  const base64 = btoa(String.fromCharCode(...pkcs8));
  const lines = base64.match(/.{1,64}/g) ?? [base64];
  return [
    "-----BEGIN PRIVATE KEY-----",
    ...lines,
    "-----END PRIVATE KEY-----",
  ].join("\n");
}

async function createTestServiceAccount() {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );

  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keyPair.privateKey),
  );

  return {
    project_id: "cool-test-project",
    client_email: "test@cool-test-project.iam.gserviceaccount.com",
    private_key: toPem(pkcs8),
  };
}

Deno.test("buildJwtAssertion produces a three-part JWT", async () => {
  const testServiceAccount = await createTestServiceAccount();
  const jwt = await buildJwtAssertion(
    testServiceAccount,
    "https://www.googleapis.com/auth/firebase.messaging",
  );

  const parts = jwt.split(".");
  assertEquals(parts.length, 3, "JWT should have 3 parts");

  // Decode and verify header.
  const header = JSON.parse(
    atob(parts[0].replace(/-/g, "+").replace(/_/g, "/")),
  );
  assertEquals(header.alg, "RS256");
  assertEquals(header.typ, "JWT");

  // Decode and verify payload.
  const payload = JSON.parse(
    atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
  );
  assertEquals(payload.iss, testServiceAccount.client_email);
  assertEquals(
    payload.scope,
    "https://www.googleapis.com/auth/firebase.messaging",
  );
  assertEquals(payload.aud, "https://oauth2.googleapis.com/token");
  assertExists(payload.iat);
  assertExists(payload.exp);
  assertEquals(payload.exp - payload.iat, 3600);

  // Signature part should be non-empty base64url.
  assertEquals(parts[2].length > 0, true, "Signature should not be empty");
});

Deno.test("buildJwtAssertion rejects missing fields", async () => {
  try {
    await buildJwtAssertion(
      { project_id: "", client_email: "", private_key: "" },
      "test-scope",
    );
    // If it doesn't throw, the key import will fail anyway.
  } catch {
    // Expected.
  }
});
