/** Synthetic aggregates/opaque IDs only. Never imported by a production module. */
import {createHash, generateKeyPairSync, sign} from "node:crypto";
import {createSupervisorHandler} from "../../../../supabase/functions/collect-receipt-supervisor/handler.ts";
import type {UnattendedIdentity, UnattendedRequest, Json} from "../unattended_contract.ts";
import type {UnattendedSigner} from "../unattended_client.ts";
export const at = Date.parse("2026-10-01T11:00:00Z");
export const id = (n: number) => `99800000-0000-4000-8000-${String(n).padStart(12, "0")}`;
export function result(request: UnattendedRequest, identity: UnattendedIdentity, now = at, patch: Json = {}): Json {
  const base = {contract_version: 2, principal_id: identity.principalId, request_id: request.requestId, action: request.action, observed_at: new Date(now).toISOString()};
  const run = {run_id: request.payload.run_id, fence_version: request.payload.fence_version};
  switch (request.action) {
    case "prove_key": return {...base, expires_at: identity.expiresAt, scope: "rw_receipt_operations", business_handled: false, financial_action: false, send_action: false, ...patch};
    case "begin_run": return {...base, ok: true, code: "RUN_STARTED", run_id: id(7), fence_version: 1, mode: "Dry-run", expires_at: new Date(now + 120000).toISOString(), ...patch};
    case "list_events": return {...base, ...run, events: [{event_id: id(8), source_version: 1, event_kind: "payment_posted", payment_id: id(9), collection_id: id(10), source_state: "posted"}], more: false, ...patch};
    case "ensure_receipt": return {...base, ...run, event_id: request.payload.event_id, source_version: request.payload.expected_source_version, ok: false, code: "DRY_RUN_ELIGIBLE", business_handled: false, receipt_id: null, ...patch};
    case "reconcile_backlog": return {...base, ...run, examined: 0, handled: 0, deferred: 0, ...patch};
    case "complete_run": return {...base, ...run, status: "completed", handled_count: 0, deferred_count: 1, action_count: 0, sms_segments: 0, business_handled: false, ...patch};
    case "reconcile_request": return {contract_version: 2, target_request_id: request.payload.target_request_id, status: "not_recorded", receipt: null, ...patch};
  }
}
export function signedFixture() {
  const pair = generateKeyPairSync("ec", {namedCurve: "prime256v1"}), spki = pair.publicKey.export({format: "der", type: "spki"});
  const identity: UnattendedIdentity = {principalId: id(1), keySha256: createHash("sha256").update(spki).digest("hex"), expiresAt: new Date(at + 86400000).toISOString()};
  let current = at, calls = 0, rpcCalls = 0, active = true, unsafe: Json = {};
  const requests: UnattendedRequest[] = [], seen: Json[] = [];
  const signer: UnattendedSigner = async bytes => ({keySha256: identity.keySha256, signature: sign("sha256", bytes, pair.privateKey).toString("base64")});
  const handler = createSupervisorHandler({now: () => current, rpc: async (name, args) => {
    rpcCalls++;
    if (name === "receipt_supervisor_key_v1") return {data: {contract_version: 1, principal_id: identity.principalId, key_sha256: identity.keySha256,
      public_key_spki_base64: spki.toString("base64"), scope: "rw_receipt_operations", state: active ? "active" : "pending", expires_at: identity.expiresAt}, error: null};
    if (name !== "receipt_operations_execute_v2") throw Error("UNEXPECTED_FIXTURE_RPC");
    const request = {action: args.p_action as UnattendedRequest["action"], requestId: String(args.p_request_id), payload: args.p_payload as Json};
    requests.push(request); const value = result(request, identity, current, unsafe); seen.push(value); return {data: value, error: null};
  }});
  const fetcher: typeof fetch = async (url, options) => {calls++; return handler(new Request(url, options));};
  return {identity, signer, fetcher, now: () => current, setNow: (value: number) => {current = value;}, pending: () => {active = false;},
    patch: (value: Json) => {unsafe = value;}, calls: () => ({http: calls, rpc: rpcCalls}), requests, results: seen};
}
