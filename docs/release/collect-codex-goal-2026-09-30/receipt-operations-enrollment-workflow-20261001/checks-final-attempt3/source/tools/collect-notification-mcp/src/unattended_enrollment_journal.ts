import {UnattendedStore} from "./unattended_store.ts";
import {keys, uuid, hash, utc, unattendedScope} from "./unattended_contract.ts";
import {enrollmentOrigin, rpcForIntent, sha256, validIntent, validReceipt, validLookup} from "./unattended_enrollment_contract.ts";
import type {EnrollmentIntent, EnrollmentReceipt} from "./unattended_enrollment_contract.ts";
import type {OwnerRpc} from "./unattended_enrollment_owner.ts";

interface Checkpoint {contract_version: 3; origin: string; scope: string; actor_id: string; session_id: string; created_at: string; intent: EnrollmentIntent}
export interface EnrollmentOutcome {contract_version: 3; request_id: string; action: EnrollmentIntent["action"]; outcome: "recorded" | "unknown" | "not_recorded";
  reason_code: "ENROLLMENT_RECORDED" | "ENROLLMENT_OUTCOME_UNKNOWN" | "ENROLLMENT_RECONCILIATION_REQUIRED" | "ENROLLMENT_ORIGINAL_WINDOW_OPEN" |
    "ENROLLMENT_ORIGINAL_NOT_RECORDED" | "ENROLLMENT_ORIGINAL_IN_PROGRESS"; receipt: EnrollmentReceipt | null; lookup_request_id: string | null}
const encoded = (value: unknown) => JSON.stringify(value);
const integrity = () => new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
function validCheckpoint(value: unknown): value is Checkpoint {
  return keys(value, ["contract_version", "origin", "scope", "actor_id", "session_id", "created_at", "intent"]) && value.contract_version === 3 &&
    value.origin === enrollmentOrigin && value.scope === unattendedScope && uuid(value.actor_id) && uuid(value.session_id) && utc(value.created_at) &&
    validIntent(value.intent) && Date.parse(value.intent.request_expires_at) > Date.parse(value.created_at) &&
    Date.parse(value.intent.request_expires_at) <= Date.parse(value.created_at) + 120_000;
}
function outcome(intent: EnrollmentIntent, status: EnrollmentOutcome["outcome"], code: EnrollmentOutcome["reason_code"], receipt: EnrollmentReceipt | null = null, lookup: string | null = null): EnrollmentOutcome {
  return {contract_version: 3, request_id: intent.request_id, action: intent.action, outcome: status, reason_code: code, receipt, lookup_request_id: lookup};
}
/** Private append-only original intents. A process restart never invokes an
 * existing mutation again. Manual lookup retains its own distinct UUID. */
export class EnrollmentJournal {
  readonly store: UnattendedStore;
  readonly actorId: string;
  readonly sessionId: string;
  constructor(directory: string, actorId: string, sessionId: string, store = new UnattendedStore(directory)) {
    if (!uuid(actorId) || !uuid(sessionId)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID"); this.store = store; this.actorId = actorId; this.sessionId = sessionId;
  }
  private async original(requestId: string): Promise<Checkpoint> {
    if (!uuid(requestId)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    const value = await this.store.read(`${requestId}.checkpoint.json`);
    if (!validCheckpoint(value) || value.actor_id !== this.actorId || value.intent.request_id !== requestId) throw integrity();
    return value;
  }
  async intent(requestId: string): Promise<EnrollmentIntent | null> {
    const value = await this.store.read(`${requestId}.checkpoint.json`, true);
    return value === null ? null : (await this.original(requestId)).intent;
  }
  private async armed(original: Checkpoint) {
    const value = await this.store.read(`${original.intent.request_id}.armed.json`);
    if (!keys(value, ["contract_version", "request_id", "input_sha256", "intent_sha256", "request_expires_at"]) || value.contract_version !== 3 ||
        value.request_id !== original.intent.request_id || value.request_expires_at !== original.intent.request_expires_at ||
        value.intent_sha256 !== sha256(encoded(original.intent)) || !hash(value.input_sha256) ||
        (original.intent.action !== "revoke" && value.input_sha256 !== sha256(encoded(rpcForIntent(original.intent))))) throw integrity();
    return value;
  }
  async once(intent: EnrollmentIntent, rpc: OwnerRpc, now: () => number = Date.now, reason?: string): Promise<EnrollmentOutcome> {
    const at = now();
    if (!validIntent(intent) || Date.parse(intent.request_expires_at) <= at || Date.parse(intent.request_expires_at) > at + 120_000 ||
        intent.action !== "revoke" && Date.parse(intent.identity_expires_at) <= at + 15_000 || typeof rpc !== "function") throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    const call = rpcForIntent(intent, reason);
    const original: Checkpoint = {contract_version: 3, origin: enrollmentOrigin, scope: unattendedScope, actor_id: this.actorId, session_id: this.sessionId,
      created_at: new Date(at).toISOString(), intent};
    // A persistence/collision error occurs before transport, and is never
    // interpreted as permission to retry an original on a different UUID.
    await this.store.publish(`${intent.request_id}.checkpoint.json`, original);
    await this.store.publish(`${intent.request_id}.armed.json`, {contract_version: 3, request_id: intent.request_id,
      input_sha256: sha256(encoded(call)), intent_sha256: sha256(encoded(intent)), request_expires_at: intent.request_expires_at});
    if (encoded(await this.original(intent.request_id)) !== encoded(original)) throw integrity();
    await this.armed(original);
    let result: EnrollmentOutcome;
    try {
      if (now() >= Date.parse(intent.request_expires_at)) throw Error();
      const value = await rpc(call.name, call.input);
      if (!validReceipt(value, intent) || Date.parse(value.recorded_at) < at - 10_000 || Date.parse(value.recorded_at) > now() + 10_000) throw Error();
      result = outcome(intent, "recorded", "ENROLLMENT_RECORDED", value);
    } catch {result = outcome(intent, "unknown", "ENROLLMENT_OUTCOME_UNKNOWN");}
    try {await this.store.publish(`${intent.request_id}.outcome.json`, result); return result;}
    catch {return outcome(intent, "unknown", "ENROLLMENT_RECONCILIATION_REQUIRED");}
  }
  async readOriginal(requestId: string): Promise<EnrollmentOutcome> {
    const original = await this.original(requestId), intent = original.intent;
    const value = await this.store.read(`${requestId}.outcome.json`, true);
    if (value !== null) {
      if (!keys(value, Object.keys(outcome(intent, "unknown", "ENROLLMENT_OUTCOME_UNKNOWN"))) || value.lookup_request_id !== null ||
          (value.outcome !== "recorded" && value.outcome !== "unknown") ||
          encoded(value) !== encoded(outcome(intent, value.outcome, value.outcome === "recorded" ? "ENROLLMENT_RECORDED" : "ENROLLMENT_OUTCOME_UNKNOWN", value.receipt as EnrollmentReceipt | null))) throw integrity();
      if (value.outcome === "recorded") {
        await this.armed(original);
        if (!validReceipt(value.receipt, intent) || Date.parse(value.receipt.recorded_at) < Date.parse(original.created_at) - 10_000) throw integrity();
      } else if (value.receipt !== null) throw integrity();
    }
    const lookup = await this.store.read(`${requestId}.lookup.json`, true);
    if (lookup !== null) {
      if (!keys(lookup, ["lookup_request_id", "observation"]) || !uuid(lookup.lookup_request_id) || lookup.lookup_request_id === requestId ||
          !keys(lookup.observation, ["contract_version", "request_id", "action", "status", "checked_at", "sample_valid_until", "request_expires_at", "receipt"]) ||
          !utc(lookup.observation.checked_at) || !validLookup(lookup.observation, intent, Date.parse(lookup.observation.checked_at)) || lookup.observation.status === "in_progress") throw integrity();
      const evidence = await this.store.read(`${lookup.lookup_request_id}.outcome.json`), claim = await this.store.read(`${lookup.lookup_request_id}.checkpoint.json`);
      if (encoded(evidence) !== encoded(lookup) || !keys(claim, ["contract_version", "actor_id", "session_id", "request_id", "target_request_id", "intent_sha256", "created_at"]) ||
          claim.contract_version !== 3 || claim.actor_id !== this.actorId || !uuid(claim.session_id) || claim.request_id !== lookup.lookup_request_id ||
          claim.target_request_id !== requestId || claim.intent_sha256 !== sha256(encoded(intent)) || !utc(claim.created_at) ||
          Date.parse(lookup.observation.checked_at) < Date.parse(claim.created_at) - 10_000) throw integrity();
      await this.armed(original);
      if (value !== null && value.outcome === "recorded" && (lookup.observation.status !== "recorded" || encoded(value.receipt) !== encoded(lookup.observation.receipt))) throw integrity();
      if (lookup.observation.status === "recorded" && (!validReceipt(lookup.observation.receipt, intent) || Date.parse(lookup.observation.receipt.recorded_at) < Date.parse(original.created_at) - 10_000)) throw integrity();
      if (lookup.observation.status === "recorded") return outcome(intent, "recorded", "ENROLLMENT_RECORDED", lookup.observation.receipt as EnrollmentReceipt, lookup.lookup_request_id);
      if (Date.parse(lookup.observation.checked_at) < Date.parse(intent.request_expires_at)) throw integrity();
      return outcome(intent, "not_recorded", "ENROLLMENT_ORIGINAL_NOT_RECORDED", null, lookup.lookup_request_id);
    }
    if (value === null) return outcome(intent, "unknown", "ENROLLMENT_RECONCILIATION_REQUIRED");
    return value as unknown as EnrollmentOutcome;
  }
  async reconcile(targetId: string, lookupId: string, rpc: OwnerRpc, now: () => number = Date.now): Promise<EnrollmentOutcome> {
    if (!uuid(targetId) || !uuid(lookupId) || targetId === lookupId) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    const original = await this.original(targetId), prior = await this.readOriginal(targetId), intent = original.intent, at = now();
    await this.store.publish(`${lookupId}.checkpoint.json`, {contract_version: 3, actor_id: this.actorId, session_id: this.sessionId,
      request_id: lookupId, target_request_id: targetId, intent_sha256: sha256(encoded(intent)), created_at: new Date(at).toISOString()});
    try {
      const observation = await rpc("admin_get_receipt_operations_enrollment_request_v3", {p_request_id: targetId});
      if (!validLookup(observation, intent, now()) || Date.parse(observation.checked_at) < at - 10_000) throw Error();
      const evidence = {lookup_request_id: lookupId, observation};
      await this.store.publish(`${lookupId}.outcome.json`, evidence);
      if (observation.status === "in_progress") return outcome(intent, "unknown", "ENROLLMENT_ORIGINAL_IN_PROGRESS", null, lookupId);
      if (observation.status === "not_recorded" && (now() < Date.parse(intent.request_expires_at) || Date.parse(observation.checked_at) < Date.parse(intent.request_expires_at))) {
        if (prior.outcome !== "unknown") throw Error();
        return outcome(intent, "unknown", "ENROLLMENT_ORIGINAL_WINDOW_OPEN", null, lookupId);
      }
      if (prior.outcome === "recorded" && (observation.status !== "recorded" || encoded(prior.receipt) !== encoded(observation.receipt)) ||
          prior.outcome === "not_recorded" && observation.status !== "not_recorded") throw Error();
      await this.armed(original);
      const existing = await this.store.read(`${targetId}.lookup.json`, true);
      if (existing === null) {
        try {await this.store.publish(`${targetId}.lookup.json`, evidence);}
        catch {const first = await this.readOriginal(targetId); if (first.outcome !== (observation.status === "recorded" ? "recorded" : "not_recorded") || encoded(first.receipt) !== encoded(observation.receipt)) throw Error();}
      }
      const saved = await this.readOriginal(targetId);
      if (saved.outcome !== (observation.status === "recorded" ? "recorded" : "not_recorded") || encoded(saved.receipt) !== encoded(observation.receipt)) throw Error();
      return saved;
    } catch {return outcome(intent, "unknown", "ENROLLMENT_RECONCILIATION_REQUIRED", null, lookupId);}
  }
}
