import {isAbsolute} from "node:path";
import {EnrollmentJournal} from "./unattended_enrollment_journal.ts";
import type {EnrollmentOutcome} from "./unattended_enrollment_journal.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {keys, uuid, hash, utc, unattendedScope} from "./unattended_contract.ts";
import type {UnattendedSigner} from "./unattended_client.ts";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import type {OwnerRpc} from "./unattended_enrollment_owner.ts";
import {publicKeyMetadata, validReceipt, validIdentityObservation, enrollmentOrigin} from "./unattended_enrollment_contract.ts";
import type {EnrollmentIntent, PublicKeyMetadata} from "./unattended_enrollment_contract.ts";
import {verifyHelper, publishEnrollmentProfile, validateInstalledEnrollmentProfile, prepareProfileDestination, readEnrollmentKey} from "./unattended_profile_preparation.ts";
import type {HelperBinding, KeyReader} from "./unattended_profile_preparation.ts";

export interface EnrollmentPlan {
  contract_version: 3; scope: typeof unattendedScope; origin: typeof enrollmentOrigin; workflow_id: string; actor_id: string; created_at: string;
  enrollment_request_id: string; proof_request_id: string; activation_request_id: string;
  public_key: PublicKeyMetadata; identity_expires_at: string; helper: HelperBinding; profile_path: string; journal_directory: string;
}
export interface EnrollmentPlanInput {workflow_id: string; enrollment_request_id: string; proof_request_id: string; activation_request_id: string;
  identity_expires_at: string; helper: HelperBinding; profile_path: string}
export interface EnrollmentPreparationResult {contract_version: 3; workflow_id: string; status: "ENROLLMENT_UNKNOWN" | "KEY_PROOF_UNKNOWN" | "ACTIVATION_UNKNOWN" | "PROFILE_PREPARED";
  principal_id: string | null; original_request_id: string | null; scheduler_installed: false; scheduler_started: false; profile_sha256: string | null}
function validPlan(value: unknown): value is EnrollmentPlan {
  return keys(value, ["contract_version", "scope", "origin", "workflow_id", "actor_id", "created_at", "enrollment_request_id", "proof_request_id", "activation_request_id", "public_key", "identity_expires_at", "helper", "profile_path", "journal_directory"]) &&
    value.contract_version === 3 && value.scope === unattendedScope && value.origin === enrollmentOrigin && uuid(value.workflow_id) && uuid(value.actor_id) && utc(value.created_at) &&
    uuid(value.enrollment_request_id) && uuid(value.proof_request_id) && uuid(value.activation_request_id) &&
    new Set([value.workflow_id, value.enrollment_request_id, value.proof_request_id, value.activation_request_id]).size === 4 &&
    publicKeyMetadata(value.public_key) && utc(value.identity_expires_at) && Date.parse(value.identity_expires_at) >= Date.parse(value.created_at) + 600_000 &&
    Date.parse(value.identity_expires_at) <= Date.parse(value.created_at) + 30 * 86_400_000 &&
    keys(value.helper, value.helper !== null && typeof value.helper === "object" && Object.hasOwn(value.helper, "key_tag_id") ? ["helper_path", "helper_sha256", "key_tag_id"] : ["helper_path", "helper_sha256"]) &&
    (value.helper.key_tag_id === undefined || uuid(value.helper.key_tag_id)) && typeof value.helper.helper_path === "string" && isAbsolute(value.helper.helper_path) && hash(value.helper.helper_sha256) &&
    typeof value.profile_path === "string" && isAbsolute(value.profile_path) && typeof value.journal_directory === "string" && isAbsolute(value.journal_directory);
}
const prepared = (plan: EnrollmentPlan, status: EnrollmentPreparationResult["status"], principal: string | null = null, request: string | null = null, profileHash: string | null = null): EnrollmentPreparationResult =>
  ({contract_version: 3, workflow_id: plan.workflow_id, status, principal_id: principal, original_request_id: request,
    scheduler_installed: false, scheduler_started: false, profile_sha256: profileHash});

/** A resumable, explicit preparation flow. It never creates a key, schedules a
 * job, sets policy modes, or retries an uncertain original mutation. */
export class EnrollmentPreparation {
  readonly ownerJournal: EnrollmentJournal;
  readonly proofJournal: UnattendedJournal;
  readonly store: UnattendedStore;
  readonly directory: string; readonly actorId: string; readonly sessionId: string; readonly rpc: OwnerRpc;
  readonly signer: UnattendedSigner; readonly reader: KeyReader; readonly fetcher: typeof fetch; readonly now: () => number;
  constructor(directory: string, actorId: string, sessionId: string, rpc: OwnerRpc,
    signer: UnattendedSigner, reader: KeyReader = readEnrollmentKey, fetcher: typeof fetch = fetch, now: () => number = Date.now) {
    this.directory = directory; this.actorId = actorId; this.sessionId = sessionId; this.rpc = rpc;
    this.signer = signer; this.reader = reader; this.fetcher = fetcher; this.now = now;
    this.ownerJournal = new EnrollmentJournal(directory, actorId, sessionId);
    this.proofJournal = new UnattendedJournal(directory); this.store = this.ownerJournal.store;
  }
  async create(input: EnrollmentPlanInput): Promise<EnrollmentPlan> {
    const at = this.now();
    await prepareProfileDestination(input.profile_path);
    await verifyHelper(input.helper);
    const key = await this.reader(input.helper, "read-public");
    const plan: EnrollmentPlan = {contract_version: 3, scope: unattendedScope, origin: enrollmentOrigin, actor_id: this.actorId, created_at: new Date(at).toISOString(),
      workflow_id: input.workflow_id, enrollment_request_id: input.enrollment_request_id, proof_request_id: input.proof_request_id,
      activation_request_id: input.activation_request_id, public_key: key, identity_expires_at: input.identity_expires_at, helper: input.helper,
      profile_path: input.profile_path, journal_directory: this.store.directory};
    if (!validPlan(plan)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    await this.store.publish(`${plan.workflow_id}.run.json`, plan);
    return await this.plan(plan.workflow_id);
  }
  async plan(workflowId: string): Promise<EnrollmentPlan> {
    if (!uuid(workflowId)) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    const plan = await this.store.read(`${workflowId}.run.json`);
    if (!validPlan(plan) || plan.workflow_id !== workflowId || plan.actor_id !== this.actorId || plan.journal_directory !== this.store.directory) throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
    return plan;
  }
  private async ownerStep(plan: EnrollmentPlan, action: EnrollmentIntent["action"], principal: string | null): Promise<EnrollmentOutcome> {
    const requestId = action === "enroll" ? plan.enrollment_request_id : plan.activation_request_id;
    const saved = await this.ownerJournal.intent(requestId);
    if (saved !== null) {
      if (saved.action !== action || saved.key_sha256 !== plan.public_key.key_sha256 || saved.identity_expires_at !== plan.identity_expires_at ||
          saved.principal_id !== principal || saved.public_key_spki_base64 !== (action === "enroll" ? plan.public_key.public_key_spki_base64 : null)) throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
      return this.ownerJournal.readOriginal(requestId);
    }
    const intent: EnrollmentIntent = {action, request_id: requestId, key_sha256: plan.public_key.key_sha256,
      identity_expires_at: plan.identity_expires_at, request_expires_at: new Date(this.now() + 90_000).toISOString(),
      public_key_spki_base64: action === "enroll" ? plan.public_key.public_key_spki_base64 : null, principal_id: principal};
    return this.ownerJournal.once(intent, this.rpc, this.now);
  }
  async resume(workflowId: string): Promise<EnrollmentPreparationResult> {
    const plan = await this.plan(workflowId);
    await verifyHelper(plan.helper);
    const currentKey = await this.reader(plan.helper, "read-public");
    if (!publicKeyMetadata(currentKey) || currentKey.key_sha256 !== plan.public_key.key_sha256 || currentKey.public_key_spki_base64 !== plan.public_key.public_key_spki_base64) throw new Error("ENROLLMENT_KEY_BINDING_REQUIRED");
    if (Date.parse(plan.identity_expires_at) <= this.now() + 15_000) throw new Error("ENROLLMENT_IDENTITY_EXPIRED");
    const enrollment = await this.ownerStep(plan, "enroll", null);
    if (enrollment.outcome !== "recorded" || !validReceipt(enrollment.receipt)) return prepared(plan, "ENROLLMENT_UNKNOWN", null, plan.enrollment_request_id);
    const principal = enrollment.receipt.principal_id;
    const observation = await this.rpc("admin_get_receipt_operations_identity_v3", {p_principal_id: principal});
    if (!validIdentityObservation(observation, principal, this.now()) || !observation.found || observation.identity?.state === "revoked" ||
        observation.identity?.key_sha256 !== plan.public_key.key_sha256 || Date.parse(observation.identity.expires_at) !== Date.parse(plan.identity_expires_at)) throw new Error("ENROLLMENT_IDENTITY_UNAVAILABLE");
    const identity = {principalId: principal, keySha256: plan.public_key.key_sha256, expiresAt: observation.identity.expires_at};
    const proofSaved = await this.store.read(`${plan.proof_request_id}.checkpoint.json`, true);
    const proof = proofSaved === null ? await this.proofJournal.once(identity, {action: "prove_key", requestId: plan.proof_request_id, payload: {}}, this.signer, this.fetcher, this.now) :
      await this.proofJournal.readOriginal(plan.proof_request_id);
    if (proof.principal_id !== principal || proof.request_id !== plan.proof_request_id || proof.action !== "prove_key") throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
    if (proof.outcome !== "recorded") return prepared(plan, "KEY_PROOF_UNKNOWN", principal, plan.proof_request_id);
    const activation = await this.ownerStep(plan, "activate", principal);
    if (activation.outcome !== "recorded" || !validReceipt(activation.receipt)) return prepared(plan, "ACTIVATION_UNKNOWN", principal, plan.activation_request_id);
    const profile: UnattendedProfile = {contract_version: 2, scope: unattendedScope, identity, helper_path: plan.helper.helper_path,
      helper_sha256: plan.helper.helper_sha256, journal_directory: this.store.directory, ...(plan.helper.key_tag_id === undefined ? {} : {key_tag_id: plan.helper.key_tag_id})};
    let verification;
    // Existing exact profiles may be revalidated; publication never overwrites
    // another principal, helper, scope or journal binding.
    try {
      const existing = await loadUnattendedProfile(plan.profile_path);
      if (JSON.stringify(existing) !== JSON.stringify(profile)) throw new Error("ENROLLMENT_PROFILE_CONFLICT");
      verification = await validateInstalledEnrollmentProfile(plan.profile_path, this.rpc, this.reader, this.now);
    } catch (error) {
      if (error instanceof Error && error.message === "ENROLLMENT_PROFILE_CONFLICT") throw error;
      verification = await publishEnrollmentProfile(plan.profile_path, profile, this.rpc, this.reader, this.now);
    }
    return prepared(plan, "PROFILE_PREPARED", principal, null, verification.profile_sha256);
  }
  async reconcile(workflowId: string, targetId: string, lookupId: string) {
    const plan = await this.plan(workflowId);
    if (targetId === plan.enrollment_request_id || targetId === plan.activation_request_id) return this.ownerJournal.reconcile(targetId, lookupId, this.rpc, this.now);
    if (targetId !== plan.proof_request_id) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    const enrollment = await this.ownerJournal.readOriginal(plan.enrollment_request_id);
    if (enrollment.outcome !== "recorded" || !enrollment.receipt) throw new Error("ENROLLMENT_RECONCILIATION_REQUIRED");
    return this.proofJournal.reconcile({principalId: enrollment.receipt.principal_id, keySha256: plan.public_key.key_sha256,
      expiresAt: plan.identity_expires_at}, targetId, lookupId, this.signer, this.fetcher, this.now);
  }
}
