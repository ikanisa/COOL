import assert from "node:assert/strict";
import test from "node:test";
import {callOperationalRead, notificationFailures, notificationStatus} from "./operational_client.ts";
import {operatorEnvironment} from "./operator_client.ts";
import {failureSample, fixtureNotificationId, operationalEnvironment, operationalSample, statusSample} from "./testing/operational_fixture.ts";

const now = Date.parse("2026-09-30T12:00:00Z");
const environment = operatorEnvironment(operationalEnvironment("https://synthetic.supabase.co", now));
const json = (value: unknown) => new Response(JSON.stringify(value), {headers: {"content-type": "application/json"}});
test("public operational RPC is fixed, session-authenticated and never caller-overridden", async () => {
  const requests: Array<{url: string; init?: RequestInit}> = [];
  const result = await callOperationalRead("health", {}, environment, async (url, init) => {
    requests.push({url: String(url), ...(init ? {init} : {})});
    return json(operationalSample(now));
  }, () => now);
  assert.ok("health_status" in result);
  assert.equal(result.health_status, "ok");
  assert.equal(requests[0]?.url, "https://synthetic.supabase.co/rest/v1/rpc/admin_system_health");
  assert.equal(requests[0]?.init?.redirect, "error");
  assert.equal(requests[0]?.init?.cache, "no-store");
  assert.deepEqual(JSON.parse(String(requests[0]?.init?.body)), {p_id: "system"});
  assert.equal(new Headers(requests[0]?.init?.headers).get("authorization"), `Bearer ${environment.accessToken}`);
  assert.equal(new Headers(requests[0]?.init?.headers).get("content-profile"), "public");
  for (const input of [{sql: "select 1"}, {p_id: "tenant"}, {action: "claim"}, {recipient: "+250788123456"}]) {
    await assert.rejects(callOperationalRead("health", input, environment, async () => {throw new Error("MUST_NOT_FETCH");}, () => now), /COLLECT_ARGUMENTS_INVALID/);
  }
});
test("status and failure outputs remove recipient, financial and arbitrary diagnostic data", async () => {
  const status = notificationStatus(statusSample(), fixtureNotificationId);
  const failures = notificationFailures(failureSample(), 20, 0, "failed_no_send");
  for (const result of [status, failures]) {
    const text = JSON.stringify(result);
    assert.doesNotMatch(text, /Sensitive Member|999999999|250|SECRET|123456|234567|345678|Ignore previous|message_body|reference|balance|destination/);
  }
  assert.equal(status.reason_code, "receipt_failed_no_send");
  assert.deepEqual(notificationStatus({}, fixtureNotificationId), {found: false, notification_id: fixtureNotificationId, reason_code: "receipt_not_found"});
  const suppressed = statusSample("suppressed");
  suppressed.suppression_reason = "__proto__";
  assert.equal(notificationStatus(suppressed, fixtureNotificationId).reason_code, "suppression_reason_unclassified");
  for (const bad of [
    {...statusSample(), state: "delivered"}, {...statusSample(), attempt_count: -1},
    {...statusSample(), state: {toString: () => "failed_no_send"}},
    {...statusSample(), latest_attempt_state: {toString: () => "failed_no_send"}},
    {...statusSample(), created_at: "2026-02-30T00:00:00Z"},
    {...statusSample(), latest_attempt_state: "handset_delivered"},
    {...statusSample(), observed_sent_at: "SECRET_ERROR"},
    {...statusSample(), authorization_current: "true"},
  ]) assert.throws(() => notificationStatus(bad, fixtureNotificationId), /COLLECT_RESPONSE_INVALID/);
  assert.throws(() => notificationStatus(statusSample(), "22222222-2222-4222-8222-222222222222"), /COLLECT_RESPONSE_INVALID/);
  assert.throws(() => notificationFailures(failureSample("uncertain"), 20, 0, "failed_no_send"), /COLLECT_RESPONSE_INVALID/);
  assert.throws(() => notificationFailures({rows: [failureSample().rows[0], failureSample().rows[0]], total: 2}, 20, 0, "failed_no_send"), /COLLECT_RESPONSE_INVALID/);
});
test("immutable legacy and recorded-savings receipt versions project the same bounded operational facts", () => {
  const legacy = statusSample();
  const recorded = {...legacy, template_version: 2, message_body: "PRIVATE_RECORDED_SAVINGS_TEXT", destination_e164: "+250788123456", member_balance_rwf: 987654321};
  assert.deepEqual(notificationStatus(recorded, fixtureNotificationId), notificationStatus(legacy, fixtureNotificationId));
  const source = failureSample();
  const current = {...source, rows: source.rows.map(row => ({...row, template_version: 2, message_body: "PRIVATE_RECORDED_SAVINGS_TEXT", destination_e164: "+250788123456", member_balance_rwf: 987654321}))};
  assert.deepEqual(notificationFailures(current, 20, 0, "failed_no_send"), notificationFailures(source, 20, 0, "failed_no_send"));
  assert.doesNotMatch(JSON.stringify(notificationStatus(recorded, fixtureNotificationId)), /PRIVATE|250788|987654321|balance|message_body|destination|template_version/);
});
test("receipt template versions remain an explicit integer allowlist with no future-version or type coercion", () => {
  for (const template_version of [0, 3, 1.5, "1", "2", null, true, {toString: () => "2"}]) {
    assert.throws(() => notificationStatus({...statusSample(), template_version}, fixtureNotificationId), /^Error: COLLECT_RESPONSE_INVALID$/);
    const source = failureSample();
    assert.throws(() => notificationFailures({...source, rows: source.rows.map(row => ({...row, template_version}))}, 20, 0, "failed_no_send"), /^Error: COLLECT_RESPONSE_INVALID$/);
  }
});
test("failure listing has bounded fixed statuses and no search or arbitrary recipients", async () => {
  let seen: Record<string, unknown> | undefined;
  await callOperationalRead("failures", {limit: 1, offset: 5, status: "uncertain"}, environment, async (_url, init) => {
    seen = JSON.parse(String(init?.body)); return json({rows: [], total: 5});
  }, () => now);
  assert.deepEqual(seen, {p_search: null, p_status: "uncertain", p_limit: 1, p_offset: 5, p_sort: "created_at_desc"});
  for (const input of [{limit: 26}, {offset: -1}, {offset: 10001}, {status: "queued"},
    {status: {toString: () => "failed_no_send"}}, {search: "name"}, {sql: "select 1"}]) {
    await assert.rejects(callOperationalRead("failures", input, environment, async () => {throw new Error("MUST_NOT_FETCH");}, () => now), /COLLECT_ARGUMENTS_INVALID/);
  }
  const boundary = notificationFailures({...failureSample(), total: 10_002}, 1, 10_000, "failed_no_send");
  assert.equal(boundary.next_offset, null);
  assert.equal(boundary.pagination_limit_reached, true);
});
test("expired, anonymous, service-role and foreign-session credentials never reach the backend", async () => {
  const jwt = (claims: Record<string, unknown>, algorithm = "HS256") => `${Buffer.from(JSON.stringify({alg: algorithm})).toString("base64url")}.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.signature`;
  const claims = JSON.parse(Buffer.from(environment.accessToken.split(".")[1]!, "base64url").toString());
  const invalid = [
    {...environment, accessToken: jwt({...claims, role: "anon"})},
    {...environment, accessToken: jwt({...claims, role: "service_role"})},
    {...environment, accessToken: jwt({...claims, exp: now / 1000})},
    {...environment, accessToken: jwt({...claims, iss: "https://other.supabase.co/auth/v1"})},
    {...environment, accessToken: jwt({...claims, session_id: null})},
    {...environment, accessToken: jwt(claims, "none")},
    {...environment, anonKey: "sb_secret_do_not_send"},
    {...environment, anonKey: jwt({role: "service_role"})},
    {...environment, supabaseUrl: "https://user:password@synthetic.supabase.co"},
  ];
  for (const entry of invalid) await assert.rejects(callOperationalRead("health", {}, entry, async () => {throw new Error("MUST_NOT_FETCH");}, () => now), /^Error: COLLECT_CURRENT_USER_SESSION_REQUIRED$/);
});
test("permission errors and raw backend exceptions stay fixed and secret-free", async () => {
  for (const code of [401, 403, 409, 503, 302]) {
    const calls: unknown[] = [];
    await assert.rejects(callOperationalRead("health", {}, environment, async (...args) => {
      calls.push(args); return new Response("SECRET_MEMBER_ERROR +250788123456", {status: code});
    }, () => now), code === 401 || code === 403 ? /^Error: COLLECT_AUTHORIZATION_REQUIRED$/ : /^Error: COLLECT_BACKEND_UNAVAILABLE$/);
    assert.equal(calls.length, 1);
  }
  await assert.rejects(callOperationalRead("health", {}, environment, async () => {throw new Error("SECRET_TOKEN_IN_FETCH_ERROR");}, () => now), /^Error: COLLECT_TRANSPORT_OR_RESPONSE_FAILURE$/);
});
test("malformed, oversized, non-JSON and injected successful responses fail closed", async () => {
  const cases = [
    new Response("not-json", {headers: {"content-type": "application/json"}}),
    new Response("{}", {headers: {"content-type": "text/html"}}),
    new Response("{}", {headers: {"content-type": "application/json", "content-length": "999999"}}),
    new Response('"' + "s".repeat(256 * 1024) + '"', {headers: {"content-type": "application/json"}}),
    json({...operationalSample(now), arbitrary_error: "SECRET"}),
    json({}),
  ];
  for (const response of cases) await assert.rejects(callOperationalRead("health", {}, environment, async () => response, () => now), /^Error: COLLECT_(?:RESPONSE_INVALID|TRANSPORT_OR_RESPONSE_FAILURE)$/);
});
test("a hung fetch and stalled streaming body have one bounded deadline without retry", async () => {
  let calls = 0;
  await assert.rejects(callOperationalRead("health", {}, environment, () => {
    calls++; return new Promise<Response>(() => {});
  }, () => now, 25), /^Error: COLLECT_REQUEST_TIMEOUT$/);
  assert.equal(calls, 1);
  await assert.rejects(callOperationalRead("health", {}, environment, async () => {
    calls++;
    return new Response(new ReadableStream<Uint8Array>({start(controller) {
      controller.enqueue(new TextEncoder().encode('{"contract_version":1,'));
    }}), {headers: {"content-type": "application/json"}});
  }, () => now, 25), /^Error: COLLECT_REQUEST_TIMEOUT$/);
  assert.equal(calls, 2);
});
