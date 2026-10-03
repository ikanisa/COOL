import {createHash} from "node:crypto";
import {UnattendedStore} from "./unattended_store.ts";
import {callUnattended, validSignature} from "./unattended_client.ts";
import type {UnattendedSigner} from "./unattended_client.ts";
import {envelope, validIdentity, validRequest, validResult, keys, object, uuid, utc, hash, unattendedScope, unattendedAudience} from "./unattended_contract.ts";
import type {UnattendedIdentity, UnattendedRequest, Json} from "./unattended_contract.ts";
export const unattendedNegativeLookupHorizonMs = 120_000;
export interface UnattendedOutcome {
  contract_version: 2; scope: typeof unattendedScope; principal_id: string; request_id: string;
  action: UnattendedRequest["action"]; outcome: "recorded" | "unknown" | "not_recorded";
  reason_code: string; result: Json | null; lookup_request_id: string | null;
}
const safe = new Set(["UNATTENDED_JOURNAL_UNAVAILABLE", "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED", "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED",
  "UNATTENDED_OUTCOME_UNKNOWN", "UNATTENDED_LOOKUP_UNAVAILABLE", "UNATTENDED_SIGNING_UNAVAILABLE", "UNATTENDED_RESULT_RECORDED",
  "UNATTENDED_ORIGINAL_REQUEST_NOT_RECORDED", "UNATTENDED_ORIGINAL_REQUEST_IN_PROGRESS", "UNATTENDED_ORIGINAL_REQUEST_WINDOW_OPEN"]);
const reason = (error: unknown, fallback = "UNATTENDED_OUTCOME_UNKNOWN") => error instanceof Error && safe.has(error.message) ? error.message : fallback;
const encoded = (value: unknown) => JSON.stringify(value);
const digest = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");
interface Checkpoint {contract_version: 2; scope: string; audience: string; identity: UnattendedIdentity; request: UnattendedRequest; created_at: string}
interface Armed {contract_version: 2; request_id: string; envelope_sha256: string; issued_at: string; not_recorded_before: string}
function validCheckpoint(value: unknown): value is Checkpoint {
  return keys(value, ["contract_version", "scope", "audience", "identity", "request", "created_at"]) && value.contract_version === 2 &&
    value.scope === unattendedScope && value.audience === unattendedAudience && utc(value.created_at) &&
    validIdentity(value.identity, Date.parse(value.created_at)) && validRequest(value.request);
}
function validArmed(value: unknown, original: Checkpoint): value is Armed {
  try {return keys(value, ["contract_version", "request_id", "envelope_sha256", "issued_at", "not_recorded_before"]) && value.contract_version === 2 &&
    value.request_id === original.request.requestId && hash(value.envelope_sha256) && utc(value.issued_at) && utc(value.not_recorded_before) &&
    Date.parse(value.issued_at) >= Date.parse(original.created_at) && Date.parse(value.issued_at) < Date.parse(original.identity.expiresAt) &&
    Date.parse(value.not_recorded_before) === Date.parse(value.issued_at) + unattendedNegativeLookupHorizonMs &&
    value.envelope_sha256 === digest(Buffer.from(encoded(envelope(original.identity, original.request, Date.parse(value.issued_at)))));
  } catch {return false;}
}
function outcome(original: Checkpoint, status: UnattendedOutcome["outcome"], code: string, result: Json | null = null, lookup: string | null = null): UnattendedOutcome {
  return {contract_version: 2, scope: unattendedScope, principal_id: original.identity.principalId,
    request_id: original.request.requestId, action: original.request.action, outcome: status, reason_code: code, result, lookup_request_id: lookup};
}
/** All actions, including bounded reads, retain the original request before the
 * first HTTP call. A duplicate/restart can inspect or lookup, never replay. */
export class UnattendedJournal {
  readonly store: UnattendedStore;
  constructor(directory: string, store = new UnattendedStore(directory)) {this.store = store;}
  private async original(requestId: string) {
    if (!uuid(requestId)) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
    const checkpoint = await this.store.read(`${requestId}.checkpoint.json`);
    if (!validCheckpoint(checkpoint) || checkpoint.request.requestId !== requestId) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
    const armed = await this.store.read(`${requestId}.armed.json`, true);
    if (armed !== null && !validArmed(armed, checkpoint)) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
    return {checkpoint, armed};
  }
  private call(original: Checkpoint, signer: UnattendedSigner, fetcher: typeof fetch, now: () => number, timeoutMs: number, signal?: AbortSignal) {
    let used = false;
    const signing: UnattendedSigner = async (bytes, abort) => {
      abort.throwIfAborted();
      if (await this.store.retained.inactive()) throw Error("UNATTENDED_JOURNAL_UNAVAILABLE");
      const raw: unknown = JSON.parse(new TextDecoder().decode(bytes));
      if (!object(raw) || !utc(raw.issued_at) || Date.parse(raw.issued_at) < Date.parse(original.created_at) ||
          encoded(envelope(original.identity, original.request, Date.parse(raw.issued_at))) !== new TextDecoder().decode(bytes)) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
      const signature = await signer(bytes, abort);
      if (!validSignature(signature, original.identity.keySha256)) throw new Error("UNATTENDED_SIGNING_UNAVAILABLE");
      abort.throwIfAborted();
      const armed: Armed = {contract_version: 2, request_id: original.request.requestId, envelope_sha256: digest(bytes), issued_at: raw.issued_at,
        not_recorded_before: new Date(Date.parse(raw.issued_at) + unattendedNegativeLookupHorizonMs).toISOString()};
      await this.store.publish(`${original.request.requestId}.armed.json`, armed);
      abort.throwIfAborted(); return signature;
    };
    const transport: typeof fetch = async (url, options) => {
      if (used) throw new Error("UNATTENDED_REQUEST_RECONCILIATION_REQUIRED");
      used = true; options?.signal?.throwIfAborted();
      const saved = await this.original(original.request.requestId);
      if (!saved.armed || encoded(saved.checkpoint) !== encoded(original) || typeof options?.body !== "string" ||
          digest(Buffer.from(options.body)) !== saved.armed.envelope_sha256) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
      if (await this.store.retained.inactive()) throw Error("UNATTENDED_JOURNAL_UNAVAILABLE");
      options?.signal?.throwIfAborted(); return fetcher(url, options);
    };
    return callUnattended(original.identity, original.request, signing, transport, now, timeoutMs, signal);
  }
  async once(identity: UnattendedIdentity, request: UnattendedRequest, signer: UnattendedSigner, fetcher: typeof fetch = fetch,
    now: () => number = Date.now, timeoutMs = 5000, signal?: AbortSignal): Promise<UnattendedOutcome> {
    const at = now();
    if (!validIdentity(identity, at) || !validRequest(request) || request.action === "reconcile_request" || typeof signer !== "function" ||
        typeof fetcher !== "function" || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
    const original: Checkpoint = {contract_version: 2, scope: unattendedScope, audience: unattendedAudience,
      identity, request, created_at: new Date(at).toISOString()};
    let reserved = false;
    try {
      signal?.throwIfAborted();
      await this.store.publish(`${request.requestId}.checkpoint.json`, original); reserved = true;
      let result: UnattendedOutcome;
      try {result = outcome(original, "recorded", "UNATTENDED_RESULT_RECORDED", await this.call(original, signer, fetcher, now, timeoutMs, signal));}
      catch (error) {result = outcome(original, "unknown", reason(error));}
      await this.store.publish(`${request.requestId}.outcome.json`, result); return result;
    } catch (error) {
      return outcome(original, "unknown", reason(error, reserved ? "UNATTENDED_OUTCOME_UNKNOWN" : "UNATTENDED_JOURNAL_UNAVAILABLE"));
    }
  }
  /** Historical local evidence only. No signature, credential or network use. */
  async readOriginal(requestId: string): Promise<UnattendedOutcome> {
    const {checkpoint, armed} = await this.original(requestId);
    const result = await this.store.read(`${requestId}.outcome.json`, true);
    if (result !== null && (!keys(result, Object.keys(outcome(checkpoint, "unknown", "UNATTENDED_OUTCOME_UNKNOWN"))) ||
        (result.outcome !== "recorded" && result.outcome !== "unknown") || typeof result.reason_code !== "string" || !safe.has(result.reason_code) ||
        result.lookup_request_id !== null || encoded(result) !== encoded(outcome(checkpoint, result.outcome, result.reason_code, result.result as Json | null)) ||
        (result.outcome === "recorded" && (armed === null || result.reason_code !== "UNATTENDED_RESULT_RECORDED" || !validResult(result.result, checkpoint.identity, checkpoint.request) || !object(result.result) || typeof result.result.observed_at !== "string" ||
          Date.parse(result.result.observed_at) < Date.parse(checkpoint.created_at) - 10000 || Date.parse(result.result.observed_at) >= Date.parse(checkpoint.identity.expiresAt))) ||
        (result.outcome === "unknown" && (result.result !== null || result.reason_code === "UNATTENDED_RESULT_RECORDED")))) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
    const observed = await this.store.read(`${requestId}.lookup.json`, true);
    if (observed !== null) {
      if (!keys(observed, Object.keys(outcome(checkpoint, "unknown", "UNATTENDED_OUTCOME_UNKNOWN"))) || observed.outcome !== "recorded" || observed.reason_code !== "UNATTENDED_RESULT_RECORDED" ||
          !uuid(observed.lookup_request_id) || observed.lookup_request_id === requestId || armed === null ||
          !validResult(observed.result, checkpoint.identity, checkpoint.request) || !object(observed.result) || typeof observed.result.observed_at !== "string" ||
          Date.parse(observed.result.observed_at) < Date.parse(checkpoint.created_at) - 10000 || Date.parse(observed.result.observed_at) >= Date.parse(checkpoint.identity.expiresAt) ||
          encoded(observed) !== encoded(outcome(checkpoint, "recorded", "UNATTENDED_RESULT_RECORDED", observed.result, observed.lookup_request_id)) ||
          (object(result) && result.outcome === "recorded" && encoded(result.result) !== encoded(observed.result))) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
      const lookup = await this.store.read(`${observed.lookup_request_id}.checkpoint.json`), proof = await this.store.read(`${observed.lookup_request_id}.armed.json`);
      if (!validCheckpoint(lookup) || lookup.request.requestId !== observed.lookup_request_id || lookup.request.action !== "reconcile_request" || lookup.request.payload.target_request_id !== requestId ||
          lookup.identity.principalId !== checkpoint.identity.principalId || lookup.identity.keySha256 !== checkpoint.identity.keySha256 || !validArmed(proof, lookup)) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
      return observed as unknown as UnattendedOutcome;
    }
    return result === null ? outcome(checkpoint, "unknown", "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED") : result as unknown as UnattendedOutcome;
  }
  /** Explicit distinct lookup UUID, fresh signature, original target retained.
   * Recorded business_handled is only the server's governed preparation proof;
   * never carrier evidence. Absence before the conservative horizon stays unknown. */
  async reconcile(identity: UnattendedIdentity, targetRequestId: string, lookupRequestId: string, signer: UnattendedSigner,
    fetcher: typeof fetch = fetch, now: () => number = Date.now, timeoutMs = 5000): Promise<UnattendedOutcome> {
    if (!validIdentity(identity, now()) || !uuid(targetRequestId) || !uuid(lookupRequestId) || targetRequestId === lookupRequestId ||
        typeof signer !== "function" || typeof fetcher !== "function" || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
    const original = await this.original(targetRequestId), prior = await this.readOriginal(targetRequestId);
    if (original.checkpoint.request.action === "reconcile_request") throw new Error("UNATTENDED_ARGUMENTS_INVALID");
    if (original.checkpoint.identity.principalId !== identity.principalId || original.checkpoint.identity.keySha256 !== identity.keySha256) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
    const lookup: Checkpoint = {contract_version: 2, scope: unattendedScope, audience: unattendedAudience, identity,
      request: {action: "reconcile_request", requestId: lookupRequestId, payload: {target_request_id: targetRequestId}}, created_at: new Date(now()).toISOString()};
    let reserved = false;
    try {
      await this.store.publish(`${lookupRequestId}.checkpoint.json`, lookup); reserved = true;
      const result = await this.call(lookup, signer, fetcher, now, timeoutMs);
      let observed: UnattendedOutcome;
      if (result.status === "recorded") {
        if (original.armed === null || !validResult(result.receipt, original.checkpoint.identity, original.checkpoint.request) || !object(result.receipt) ||
            typeof result.receipt.observed_at !== "string" || Date.parse(result.receipt.observed_at) < Date.parse(original.checkpoint.created_at) - 10000 ||
            Date.parse(result.receipt.observed_at) >= Date.parse(original.checkpoint.identity.expiresAt)) throw new Error("UNATTENDED_LOOKUP_UNAVAILABLE");
        observed = outcome(original.checkpoint, "recorded", "UNATTENDED_RESULT_RECORDED", result.receipt, lookupRequestId);
      } else if (result.status === "not_recorded") {
        const lookupArmed = await this.store.read(`${lookupRequestId}.armed.json`);
        if (prior.outcome === "recorded" || original.armed === null || !validArmed(lookupArmed, lookup)) throw new Error("UNATTENDED_LOOKUP_UNAVAILABLE");
        const closed = Date.parse(lookupArmed.issued_at) >= Date.parse(original.armed.not_recorded_before) && now() >= Date.parse(original.armed.not_recorded_before);
        observed = outcome(original.checkpoint, closed ? "not_recorded" : "unknown",
          closed ? "UNATTENDED_ORIGINAL_REQUEST_NOT_RECORDED" : "UNATTENDED_ORIGINAL_REQUEST_WINDOW_OPEN", null, lookupRequestId);
      } else observed = outcome(original.checkpoint, "unknown", "UNATTENDED_ORIGINAL_REQUEST_IN_PROGRESS", null, lookupRequestId);
      await this.store.publish(`${lookupRequestId}.lookup.json`, observed);
      if (observed.outcome === "recorded") {
        const existing = await this.store.read(`${targetRequestId}.lookup.json`, true);
        if (existing === null) {
          try {await this.store.publish(`${targetRequestId}.lookup.json`, observed);}
          catch (error) {
            if (!(error instanceof Error) || error.message !== "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED") throw error;
            const first = await this.readOriginal(targetRequestId);
            if (first.outcome !== "recorded" || encoded(first.result) !== encoded(observed.result)) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
          }
        } else {
          const first = await this.readOriginal(targetRequestId);
          if (first.outcome !== "recorded" || encoded(first.result) !== encoded(observed.result)) throw new Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
        }
      }
      return observed;
    } catch (error) {
      const unknown = outcome(original.checkpoint, "unknown", reason(error, "UNATTENDED_LOOKUP_UNAVAILABLE"), null, lookupRequestId);
      if (reserved) await this.store.publish(`${lookupRequestId}.outcome.json`, unknown).catch(() => {});
      return unknown;
    }
  }
}
