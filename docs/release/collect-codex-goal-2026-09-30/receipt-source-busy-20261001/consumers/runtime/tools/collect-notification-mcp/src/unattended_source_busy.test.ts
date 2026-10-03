import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {callUnattended} from "./unattended_client.ts";
import {validResult, ensureCodes, type UnattendedRequest} from "./unattended_contract.ts";
import {validateOperationResult, ensureCodes as backendCodes} from "../../../supabase/functions/collect-receipt-supervisor/operations_contract.ts";
import {id, signedFixture} from "./testing/unattended_fixture.ts";
const actual = JSON.parse(readFileSync(new URL("../../../docs/release/collect-codex-goal-2026-09-30/receipt-source-busy-20261001/accepted-sql/observed-busy-ensure.json", import.meta.url), "utf8"));
const actualRequest: UnattendedRequest = {action: "ensure_receipt", requestId: actual.request_id, payload: {run_id: actual.run_id, fence_version: actual.fence_version, event_id: actual.event_id, expected_source_version: actual.source_version}};
const actualIdentity = {principalId: actual.principal_id, keySha256: "c".repeat(64), expiresAt: new Date(Date.parse(actual.observed_at) + 86400000).toISOString()};
test("actual ordinary-owner SQL SOURCE_BUSY decodes through both closed contracts", () => {
  assert.deepEqual([...ensureCodes], backendCodes);
  assert.equal(validResult(actual, actualIdentity, actualRequest), true);
  assert.equal(validateOperationResult(actual, actual.principal_id, actual.request_id, actualRequest.action, actualRequest.payload), true);
});
test("signed actual Edge handler and MCP client preserve source contention without ACK or retry", async () => {
  const f = signedFixture();
  const request: UnattendedRequest = {action: "ensure_receipt", requestId: id(5), payload: {run_id: id(7), fence_version: 1, event_id: id(8), expected_source_version: 1}};
  // Only opaque route IDs/timestamps belong to the signed transport fixture.
  // These exact business fields originate in the retained actual SQL result.
  f.patch({code: actual.code, ok: actual.ok, business_handled: actual.business_handled, receipt_id: actual.receipt_id});
  const received = await callUnattended(f.identity, request, f.signer, f.fetcher, f.now);
  assert.equal(received.code, "SOURCE_BUSY"); assert.equal(received.business_handled, false); assert.equal(received.receipt_id, null);
  assert.deepEqual(f.calls(), {http: 1, rpc: 2});
});
for (const [name, patch] of Object.entries({falseACK: {ok: true, business_handled: true}, wrongBusiness: {business_handled: true}, fabricatedReceipt: {receipt_id: id(10)}, privateExtra: {destination: "+250788000000"}, arbitraryCode: {code: "SOURCE_BUSY_UNKNOWN"}})) {
  test(`SOURCE_BUSY rejects ${name} in both closed decoders`, () => {
    const unsafe = {...actual, ...patch};
    assert.equal(validResult(unsafe, actualIdentity, actualRequest), false);
    assert.equal(validateOperationResult(unsafe, actual.principal_id, actual.request_id, actualRequest.action, actualRequest.payload), false);
  });
}
