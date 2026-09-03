import assert from "node:assert/strict";
import test from "node:test";

import { callNotificationOperator, validatedSupabaseUrl } from "./operator_client.ts";

const environment = {
  supabaseUrl: "https://collect.example.test",
  anonKey: "anon-test",
  accessToken: "operator-test",
};

test("client sends only the selected command through the operator edge boundary", async () => {
  const result = await callNotificationOperator(
    "health",
    {},
    environment,
    async (input, init) => {
      assert.equal(
        String(input),
        "https://collect.example.test/functions/v1/collect-notification-operator",
      );
      assert.equal(init?.method, "POST");
      assert.equal(init?.redirect, "error");
      assert.equal(init?.cache, "no-store");
      assert.ok(init?.signal instanceof AbortSignal);
      assert.equal(
        (init?.headers as Record<string, string>).Authorization,
        "Bearer operator-test",
      );
      assert.deepEqual(JSON.parse(String(init?.body)), { action: "health" });
      return new Response(
        JSON.stringify({ ok: true, result: { queued: 0 } }),
        { status: 200 },
      );
    },
  );
  assert.deepEqual(result, { queued: 0 });
});

test("client rejects action overrides and unknown operations before transport", async () => {
  let calls = 0;
  const fetcher = async () => { calls++; return Response.json({ ok: true, result: {} }); };
  await assert.rejects(callNotificationOperator("health", { action: "claim" }, environment, fetcher), /overridden/);
  await assert.rejects(callNotificationOperator("execute_sql", {}, environment, fetcher), /Unsupported/);
  assert.equal(calls, 0);
});

test("credentials are sent only to a configured origin without embedded user info or paths", () => {
  assert.equal(validatedSupabaseUrl("https://collect.example.test/"), "https://collect.example.test");
  assert.equal(validatedSupabaseUrl("http://127.0.0.1:54321"), "http://127.0.0.1:54321");
  for (const value of ["http://collect.example.test", "https://user:pass@collect.example.test", "https://collect.example.test/path", "https://collect.example.test?token=value", "https://collect.example.test#fragment", "file:///tmp"]) {
    assert.throws(() => validatedSupabaseUrl(value));
  }
});

test("client fails closed on authorization or backend errors", async () => {
  await assert.rejects(
    callNotificationOperator(
      "get_claimed",
      {},
      environment,
      async () => new Response(JSON.stringify({ error: "Current claim required" }), {
        status: 409,
      }),
    ),
    /Current claim required/,
  );
});
