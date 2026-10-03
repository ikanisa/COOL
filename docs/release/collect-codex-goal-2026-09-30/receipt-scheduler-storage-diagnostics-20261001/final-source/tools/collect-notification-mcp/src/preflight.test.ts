import assert from "node:assert/strict";
import test from "node:test";
import { connectionPreflight, runtimeReadiness } from "./preflight.ts";

const now = 1_800_000_000_000;
const jwt = (value: Record<string, unknown>) => `e30.${Buffer.from(JSON.stringify(value)).toString("base64url")}.fixture`;
const environment = {
  COLLECT_SUPABASE_URL: "https://collect.example.test",
  COLLECT_SUPABASE_ANON_KEY: jwt({ role: "anon" }),
  COLLECT_OPERATOR_ACCESS_TOKEN: jwt({ role: "authenticated", iss: "https://collect.example.test/auth/v1", exp: now / 1000 + 3600 }),
};

test("missing runtime reports names only and performs no network request", async () => {
  const result = await connectionPreflight({}, true, async () => { throw new Error("must not fetch"); }, now);
  assert.equal(result.status, "BLOCKED_RUNTIME_CONFIGURATION");
  assert.equal(result.runtime.missing.length, 3);
  assert.equal(result.provider_sends, 0);
});

test("readiness rejects secret keys, non-user tokens, wrong projects and stale sessions", () => {
  const cases = [
    { COLLECT_SUPABASE_ANON_KEY: jwt({ role: "service_role" }) },
    { COLLECT_OPERATOR_ACCESS_TOKEN: jwt({ role: "service_role", iss: "https://collect.example.test/auth/v1", exp: now / 1000 + 3600 }) },
    { COLLECT_OPERATOR_ACCESS_TOKEN: jwt({ role: "authenticated", iss: "https://other.example.test/auth/v1", exp: now / 1000 + 3600 }) },
    { COLLECT_OPERATOR_ACCESS_TOKEN: jwt({ role: "authenticated", iss: "https://collect.example.test/auth/v1", exp: now / 1000 + 59 }) },
    { COLLECT_OPERATOR_ACCESS_TOKEN: "not-a-token" },
    { COLLECT_SUPABASE_URL: "https://operator:secret@collect.example.test/path" },
  ];
  for (const changed of cases) assert.equal(runtimeReadiness({ ...environment, ...changed }, now).ready, false);
  assert.equal(runtimeReadiness(environment, now).ready, true);
  assert.equal(runtimeReadiness({ ...environment, COLLECT_SUPABASE_ANON_KEY: "sb_publishable_fixture" }, now).ready, true);
});

test("default preflight never connects even with complete runtime", async () => {
  let calls = 0;
  const result = await connectionPreflight(environment, false, async () => { calls++; throw new Error(); }, now);
  assert.equal(result.status, "READY_FOR_READ_ONLY_CHECK");
  assert.equal(calls, 0);
  assert.ok(!JSON.stringify(result).includes(environment.COLLECT_OPERATOR_ACCESS_TOKEN));
});

test("live preflight calls only health and one bounded list and redacts private rows", async () => {
  const actions: string[] = [];
  const health = { enabled: false, queued: 1, awaiting_confirmation: 0, send_started: 0, uncertain: 0, suppressed: 0, active_workers: 0 };
  const result = await connectionPreflight(environment, true, async (_input, init) => {
    const body = JSON.parse(String(init?.body));
    actions.push(body.action);
    if (body.action === "list_pending") assert.equal(body.limit, 1);
    return Response.json({ ok: true, result: body.action === "health" ? health : [{ job_id: "private-fixture", destination_masked: "private-phone", amount_rwf: 1500 }] });
  }, now);
  assert.equal(result.status, "PASS_AUTHENTICATED_READ_ONLY");
  assert.deepEqual(actions, ["health", "list_pending"]);
  assert.ok(!JSON.stringify(result).includes("private-"));
  assert.equal(result.queue_mutations, 0);
});

test("remote failures are sanitized and do not trigger a retry", async () => {
  let calls = 0;
  const result = await connectionPreflight(environment, true, async () => { calls++; throw new Error("secret-token-and-phone"); }, now);
  assert.equal(result.status, "BLOCKED_AUTHORIZATION_TRANSPORT_OR_RESPONSE");
  assert.equal(calls, 1);
  assert.ok(!JSON.stringify(result).includes("secret-token"));
});

test("invalid response shape fails closed before listing", async () => {
  let calls = 0;
  const result = await connectionPreflight(environment, true, async () => { calls++; return Response.json({ ok: true, result: { queued: "1" } }); }, now);
  assert.equal(result.status, "BLOCKED_AUTHORIZATION_TRANSPORT_OR_RESPONSE");
  assert.equal(calls, 1);
});
