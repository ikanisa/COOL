import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {callUnattended} from "./unattended_client.ts";
import {envelope, validResult, validRequest, unattendedAudience, unattendedEndpoint, ensureCodes} from "./unattended_contract.ts";
import {validateOperationResult, ensureCodes as backendCodes} from "../../../supabase/functions/collect-receipt-supervisor/operations_contract.ts";
import {at, id, result, signedFixture} from "./testing/unattended_fixture.ts";
import type {UnattendedRequest, Json} from "./unattended_contract.ts";
const input: UnattendedRequest = {action: "begin_run", requestId: id(2), payload: {}};
const run = {run_id: id(7), fence_version: 1};
const requests: UnattendedRequest[] = [input, {action: "prove_key", requestId: id(3), payload: {}}, {action: "list_events", requestId: id(4), payload: {...run, limit: 5}},
  {action: "ensure_receipt", requestId: id(5), payload: {...run, event_id: id(8), expected_source_version: 1}}, {action: "reconcile_backlog", requestId: id(6), payload: {...run, limit: 5}},
  {action: "complete_run", requestId: id(11), payload: run}, {action: "reconcile_request", requestId: id(12), payload: {target_request_id: id(2)}}];
for (const request of requests) test(`actual Edge P256 v2 ${request.action} shares exact backend contract`, async () => {
  const f = signedFixture(), response = await callUnattended(f.identity, request, f.signer, f.fetcher, f.now);
  assert.equal(validateOperationResult(response, f.identity.principalId, request.requestId, request.action, request.payload), true);
  assert.equal(validResult(response, f.identity, request), true); assert.deepEqual(f.calls(), {http: 1, rpc: 2});
});
test("finite ensure code registry matches current server exactly", () => assert.deepEqual([...ensureCodes], backendCodes));
test("exact signed endpoint/header bytes contain no operator credential", async () => {
  const f = signedFixture(); let signed: Uint8Array | undefined;
  const signer: typeof f.signer = async (bytes, signal) => {signed = bytes; return f.signer(bytes, signal);};
  await callUnattended(f.identity, input, signer, async (url, options) => {
    assert.equal(url, unattendedEndpoint); assert.equal(options?.redirect, "error"); assert.equal(options?.cache, "no-store");
    const headers = new Headers(options?.headers); assert.equal(headers.has("authorization"), false); assert.equal(headers.has("apikey"), false);
    assert.equal(options?.body, new TextDecoder().decode(signed));
    const value = JSON.parse(String(options?.body)); assert.equal(value.audience, unattendedAudience); assert.equal(value.contract_version, 2);
    assert.deepEqual(Object.keys(value), Object.keys(value).sort()); return f.fetcher(url, options);
  }, f.now);
});
for (const [name, bad] of Object.entries({send: {...input, action: "send"}, body: {...input, payload: {body: "private"}}, extra: {...input, token: "private"}, badId: {...input, requestId: "INVALID"},
  sameLookup: {action: "reconcile_request", requestId: id(2), payload: {target_request_id: id(2)}}, wrongFence: {action: "list_events", requestId: id(2), payload: {...run, fence_version: true, limit: 1}},
  sql: {action: "ensure_receipt", requestId: id(2), payload: {...run, event_id: id(8), expected_source_version: 1, sql: "private"}}})) {
  test(`bad ${name} produces no signer or network action`, async () => {
    const f = signedFixture(); let signs = 0;
    await assert.rejects(callUnattended(f.identity, bad as UnattendedRequest, async b => {signs++; return f.signer(b, new AbortController().signal);}, f.fetcher, f.now), /UNATTENDED_ARGUMENTS_INVALID/);
    assert.equal(signs, 0); assert.equal(f.calls().http, 0);
  });
}
for (const [name, patch] of Object.entries({phone: {recipient: "private"}, mode: {mode: "Invented"}, lease: {expires_at: new Date(at + 120001).toISOString()}, badOk: {ok: 1}, stale: {observed_at: new Date(at - 20000).toISOString()}})) {
  test(`unsafe actual Edge result ${name} retains uncertainty without replay`, async () => {
    const f = signedFixture(); f.patch(patch);
    await assert.rejects(callUnattended(f.identity, input, f.signer, f.fetcher, f.now), /^Error: UNATTENDED_OUTCOME_UNKNOWN$/); assert.equal(f.calls().http, 1);
  });
}
test("unverified operations identity proves possession but cannot begin", async () => {
  const f = signedFixture(); f.pending(); await callUnattended(f.identity, requests[1]!, f.signer, f.fetcher, f.now);
  await assert.rejects(callUnattended(f.identity, input, f.signer, f.fetcher, f.now), /UNATTENDED_OUTCOME_UNKNOWN/);
  assert.deepEqual(f.calls(), {http: 2, rpc: 3});
});
test("network failure and arbitrary raw backend diagnostics remain redacted", async () => {
  const f = signedFixture(); let calls = 0;
  await assert.rejects(callUnattended(f.identity, input, f.signer, async () => {calls++; throw Error("private raw credential");}, f.now), /^Error: UNATTENDED_OUTCOME_UNKNOWN$/); assert.equal(calls, 1);
  await assert.rejects(callUnattended(f.identity, input, f.signer, async () => new Response(JSON.stringify({error: "private"}), {status: 403}), f.now), /^Error: UNATTENDED_OUTCOME_UNKNOWN$/);
});
test("signing timeout performs no HTTP and ignores late completion", async () => {
  const f = signedFixture(); await assert.rejects(callUnattended(f.identity, input, async () => new Promise(() => {}), f.fetcher, f.now, 20), /UNATTENDED_SIGNING_UNAVAILABLE/); assert.equal(f.calls().http, 0);
});
test("trickling response has whole-request deadline and no retry", async () => {
  const f = signedFixture(); let calls = 0;
  await assert.rejects(callUnattended(f.identity, input, f.signer, async () => {calls++; return new Response(new ReadableStream({start() {}, cancel() {}}), {headers: {"content-type": "application/json"}});}, f.now, 20), /UNATTENDED_OUTCOME_UNKNOWN/); assert.equal(calls, 1);
});
test("redirected or oversized response is uncertain", async () => {
  const f = signedFixture();
  await assert.rejects(callUnattended(f.identity, input, f.signer, async () => new Response("private", {status: 302}), f.now), /UNATTENDED_OUTCOME_UNKNOWN/);
  await assert.rejects(callUnattended(f.identity, input, f.signer, async () => new Response('"' + "x".repeat(1024 * 1024) + '"', {headers: {"content-type": "application/json"}}), f.now), /UNATTENDED_OUTCOME_UNKNOWN/);
});
for (const [name, patch] of Object.entries({ack: {ok: true}, wrongVersion: {source_version: 2}, arbitraryCode: {code: "secret"}, inventedHandled: {business_handled: true}, receiptExtra: {destination_sha256: "private"}})) {
  test(`strict ensure ${name} does not fabricate ACK`, () => {
    const f = signedFixture(), request = requests[3]!; assert.equal(validResult(result(request, f.identity, at, patch), f.identity, request), false);
  });
}
test("complete actual quota segments remain a count without carrier conclusion", () => {
  const f = signedFixture(), request = requests[5]!, actual = result(request, f.identity, at, {sms_segments: 2});
  assert.equal(validResult(actual, f.identity, request), true); assert.equal(validateOperationResult(actual, f.identity.principalId, request.requestId, request.action, request.payload), true);
});
test("list rejects duplicate, null collection, leaked text and limit overflow", () => {
  const f = signedFixture(), request = requests[2]!, actual = result(request, f.identity), events = actual.events as Json[];
  for (const patched of [[events[0], events[0]], [{...events[0], collection_id: null}], [{...events[0], body: "private"}]]) assert.equal(validResult({...actual, events: patched}, f.identity, request), false);
  assert.equal(validResult({...actual, events: events.concat(events)}, f.identity, {...request, payload: {...run, limit: 1}}), false);
});
test("payload sorting is canonical and contains only existing scoped IDs", () => {
  const f = signedFixture(), request = requests[3]!, value = envelope(f.identity, request, at);
  assert.deepEqual(Object.keys(value.payload), Object.keys(value.payload).sort()); assert.equal(validRequest(request), true);
});

test("seven actual disposable SQL v2 results reach client strict projection without invented timestamps or ACK", async () => {
  const rows = JSON.parse(await readFile(new URL("../../../supabase/functions/collect-receipt-supervisor/fixtures/observed-operations-v2.json", import.meta.url), "utf8")) as {action: UnattendedRequest["action"]; payload: Json; result: Json}[];
  assert.equal(rows.length, 7);
  const expiry = rows.find(row => row.action === "prove_key")!.result.expires_at as string;
  for (const row of rows) {
    const original = row.action === "reconcile_request" ? row.result.receipt as Json : row.result;
    const f = signedFixture(), identity = {...f.identity, principalId: original.principal_id as string, expiresAt: expiry};
    const request: UnattendedRequest = {action: row.action, requestId: row.action === "reconcile_request" ? id(500) : original.request_id as string, payload: row.payload};
    const response = await callUnattended(identity, request, f.signer, async () => Response.json({contract_version: 2, principal_id: identity.principalId,
      request_id: request.requestId, action: request.action, result: row.result}), () => Date.parse(original.observed_at as string));
    assert.deepEqual(response, row.result); assert.equal(validResult(response, identity, request), true);
    assert.equal(JSON.stringify(response).includes("+250"), false); assert.equal(Object.hasOwn(response, "message_body"), false);
    if (row.action === "complete_run") {assert.equal(response.business_handled, false); assert.equal(response.handled_count, 2); assert.equal(response.deferred_count, 4);}
  }
});
