import {spawn} from "node:child_process";
import {join} from "node:path";
import {keys, uuid, hash, utc, unattendedScope, validIdentity, type Json} from "./unattended_contract.ts";
import {sha256, enrollmentOrigin} from "./unattended_enrollment_contract.ts";
import {loadSchedulerDeployment, schedulerLabel, assertSchedulerExecutionBinding, type Deployment} from "./unattended_deployment.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {runtimeCredentials} from "./runtime_credentials.ts";
import {enrollmentOwner, enrollmentOwnerRpc} from "./unattended_enrollment_owner.ts";
import {validateInstalledEnrollmentProfile} from "./unattended_profile_preparation.ts";
import {schedulerStorageDiagnostics, type StorageDependencies} from "./unattended_scheduler_storage.ts";

export interface LaunchctlResult {code: number | null; uncertain: boolean; stdout: string; stderr: string}
export type Launchctl = (args: readonly string[]) => Promise<LaunchctlResult>;
async function deadline<T>(work: Promise<T>, milliseconds: number, code: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {return await Promise.race([work, new Promise<never>((_, reject) => {timer = setTimeout(() => reject(Error(code)), milliseconds);})]);}
  finally {clearTimeout(timer);}
}
/** Fixed executable, no shell, no inherited credential/proxy/Node environment.
 * Killing a timed-out IPC caller does not prove the daemon rejected its action. */
export const localLaunchctl: Launchctl = args => new Promise(resolve => {
  if (process.platform !== "darwin" || args.length < 2 || args.length > 3 || !["print", "print-disabled", "enable", "disable", "bootstrap", "bootout"].includes(args[0]!)) {
    resolve({code: null, uncertain: true, stdout: "", stderr: ""}); return;
  }
  const child = spawn("/bin/launchctl", [...args], {stdio: ["ignore", "pipe", "pipe"], env: {PATH: "/usr/bin:/bin", LANG: "C"}});
  let settled = false, size = 0; const out: Buffer[] = [], err: Buffer[] = [];
  const finish = (code: number | null, uncertain: boolean) => {if (settled) return; settled = true; clearTimeout(timer);
    resolve({code, uncertain, stdout: Buffer.concat(out).toString("utf8"), stderr: Buffer.concat(err).toString("utf8")});};
  const timer = setTimeout(() => {child.kill("SIGKILL"); finish(null, true);}, 5000);
  const collect = (rows: Buffer[]) => (chunk: Buffer) => {size += chunk.length; if (size > 16384) {child.kill("SIGKILL"); finish(null, true);} else rows.push(chunk);};
  child.stdout.on("data", collect(out)); child.stderr.on("data", collect(err)); child.on("error", () => finish(null, true));
  child.on("close", (code, signal) => finish(code, signal !== null));
});
export interface HostObservation {state: "absent" | "loaded" | "running" | "disabled" | "unknown" | "conflicting"; loaded: boolean | null; disabled: boolean | null; process_running: boolean | null}
function bounded(result: LaunchctlResult) {
  return result && (result.code === null || Number.isSafeInteger(result.code)) && typeof result.uncertain === "boolean" &&
    typeof result.stdout === "string" && typeof result.stderr === "string" && Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr) <= 16384;
}
function disabledState(result: LaunchctlResult): boolean | null {
  if (!bounded(result) || result.uncertain || result.code !== 0 || !/^\s*disabled services\s*=\s*\{[\s\S]*\}\s*$/.test(result.stdout)) return null;
  const matches = [...result.stdout.matchAll(/^\s*"com\.ikanisa\.collect\.receipt-operations"\s*=>\s*(true|false)\s*$/gm)];
  const declared = [...result.stdout.matchAll(/^\s*"com\.ikanisa\.collect\.receipt-operations"\s*=>/gm)];
  return matches.length !== declared.length || matches.length > 1 ? null : matches.length === 0 ? false : matches[0]![1] === "true";
}
export function projectHostObservation(deployment: Deployment, printed: LaunchctlResult, overrides: LaunchctlResult): HostObservation {
  const unknown: HostObservation = {state: "unknown", loaded: null, disabled: disabledState(overrides), process_running: null};
  if (!bounded(printed) || printed.uncertain) return unknown;
  if (printed.code === 113 && printed.stdout.trim() === "" && printed.stderr.trim() === `Could not find service "${schedulerLabel}" in domain for user gui: ${deployment.manifest.uid}`) return {
    state: unknown.disabled === true ? "disabled" : unknown.disabled === false ? "absent" : "unknown", loaded: false, disabled: unknown.disabled, process_running: false};
  if (printed.code !== 0) return unknown;
  const target = `gui/${deployment.manifest.uid}/${schedulerLabel}`;
  const text = printed.stdout.trim();
  if (!text.startsWith(`${target} = {`) || !text.endsWith("}")) return {...unknown, state: "conflicting"};
  const one = (name: string) => {const matches = [...text.matchAll(new RegExp(`^\\s*${name} = (.+)$`, "gm"))]; return matches.length === 1 ? matches[0]![1]!.trim() : null;};
  const args = [...text.matchAll(/^\s*arguments = \{\s*\n([^}]+)\}/gm)];
  const values = args.length === 1 ? args[0]![1]!.split("\n").map(s => s.trim()).filter(Boolean) : [];
  if (one("path") !== join(deployment.directory, `${schedulerLabel}.plist`) || one("program") !== "/bin/sh" ||
      one("type") !== "LaunchAgent" || JSON.stringify(values) !== JSON.stringify(["/bin/sh", join(deployment.directory, "tick.sh")])) return {...unknown, state: "conflicting"};
  const state = one("state");
  if (!state || !["running", "not running", "waiting", "exited"].includes(state) || unknown.disabled === null) return unknown;
  return {state: unknown.disabled ? "disabled" : state === "running" ? "running" : "loaded", loaded: true,
    disabled: unknown.disabled, process_running: state === "running"};
}
async function observe(deployment: Deployment, launchctl: Launchctl): Promise<HostObservation> {
  const target = `gui/${deployment.manifest.uid}/${schedulerLabel}`;
  const [printed, disabled] = await Promise.all([launchctl(["print", target]), launchctl(["print-disabled", `gui/${deployment.manifest.uid}`])]);
  return projectHostObservation(deployment, printed, disabled);
}
export interface OwnerActivationProof {actor_id: string; session_id: string; profile_sha256: string; helper_sha256: string; principal_id: string; key_sha256: string; identity_expires_at: string; checked_at: string; sample_valid_until: string}
export async function currentSchedulerOwner(deployment: Deployment, environment: NodeJS.ProcessEnv = process.env): Promise<OwnerActivationProof> {
  const runtime = await runtimeCredentials(environment, {allowRefresh: false}), owner = await enrollmentOwner(runtime);
  const proof = await validateInstalledEnrollmentProfile(deployment.manifest.profile_path, enrollmentOwnerRpc(owner));
  return {actor_id: owner.actorId, session_id: owner.sessionId, profile_sha256: proof.profile_sha256, helper_sha256: proof.helper_sha256,
    principal_id: proof.principal_id, key_sha256: proof.key_sha256, identity_expires_at: proof.identity_expires_at,
    checked_at: proof.checked_at, sample_valid_until: proof.sample_valid_until};
}
interface Operation {contract_version: 1; kind: "local_scheduler_operation"; scope: typeof unattendedScope; origin: typeof enrollmentOrigin;
  action: "activate" | "disable"; request_id: string; preparation_sha256: string; profile_sha256: string; principal_id: string; key_sha256: string;
  uid: number; label: typeof schedulerLabel; created_at: string; request_expires_at: string; actor_id: string | null; session_id: string | null; activation_request_id: string | null}
function validOperation(value: unknown, deployment: Deployment, requestId: string): value is Operation {
  return keys(value, ["contract_version", "kind", "scope", "origin", "action", "request_id", "preparation_sha256", "profile_sha256", "principal_id", "key_sha256", "uid", "label", "created_at", "request_expires_at", "actor_id", "session_id", "activation_request_id"]) &&
    value.contract_version === 1 && value.kind === "local_scheduler_operation" && value.scope === unattendedScope && value.origin === enrollmentOrigin &&
    value.request_id === requestId && uuid(requestId) && value.preparation_sha256 === deployment.manifestSha && value.profile_sha256 === deployment.manifest.profile_sha256 &&
    value.principal_id === deployment.manifest.identity.principalId && value.key_sha256 === deployment.manifest.identity.keySha256 && value.uid === deployment.manifest.uid && value.label === schedulerLabel &&
    utc(value.created_at) && utc(value.request_expires_at) && Date.parse(value.request_expires_at) - Date.parse(value.created_at) === 30000 &&
    (value.action === "activate" && uuid(value.actor_id) && uuid(value.session_id) && value.activation_request_id === null ||
      value.action === "disable" && value.actor_id === null && value.session_id === null && uuid(value.activation_request_id));
}
const claimName = (deployment: Deployment) => `principal-${deployment.manifest.identity.principalId}.lock.json`;
const controlStore = (deployment: Deployment) => new UnattendedStore(join(deployment.directory, "control"));
export async function activationOriginal(deployment: Deployment, store = controlStore(deployment)): Promise<Operation | null> {
  const claim = await store.read(claimName(deployment), true); if (claim === null) return null;
  if (!keys(claim, ["contract_version", "request_id", "checkpoint_sha256", "preparation_sha256"]) || claim.contract_version !== 1 ||
      !uuid(claim.request_id) || !hash(claim.checkpoint_sha256) || claim.preparation_sha256 !== deployment.manifestSha) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
  const plan = await store.read(`${claim.request_id}.checkpoint.json`);
  if (!validOperation(plan, deployment, claim.request_id) || plan.action !== "activate" || sha256(JSON.stringify(plan)) !== claim.checkpoint_sha256) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
  return plan;
}
async function disabledOriginal(deployment: Deployment, activation: Operation, store = controlStore(deployment)) {
  const marker = await store.read(`${activation.request_id}.closed.json`, true); if (marker === null) return null;
  if (!keys(marker, ["contract_version", "request_id", "activation_request_id", "checkpoint_sha256", "preparation_sha256"]) || marker.contract_version !== 1 ||
      !uuid(marker.request_id) || marker.activation_request_id !== activation.request_id || marker.preparation_sha256 !== deployment.manifestSha || !hash(marker.checkpoint_sha256)) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
  const plan = await store.read(`${marker.request_id}.checkpoint.json`);
  if (!validOperation(plan, deployment, marker.request_id) || plan.action !== "disable" || plan.activation_request_id !== activation.request_id || sha256(JSON.stringify(plan)) !== marker.checkpoint_sha256) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
  return plan;
}
export async function schedulerTickPermitted(deployment: Deployment): Promise<boolean> {
  const store = controlStore(deployment), activation = await activationOriginal(deployment, store);
  if (!activation || await disabledOriginal(deployment, activation, store)) return false;
  const armed = await store.read(`${activation.request_id}.step.json`, true);
  return keys(armed, ["contract_version", "request_id", "command", "checkpoint_sha256"]) && armed.contract_version === 1 &&
    armed.request_id === activation.request_id && armed.command === "bootstrap" && armed.checkpoint_sha256 === sha256(JSON.stringify(activation));
}
export interface ControlDependencies {launchctl?: Launchctl; owner?: (deployment: Deployment) => Promise<OwnerActivationProof>; now?: () => number;
  launchTimeoutMs?: number; ownerTimeoutMs?: number; executionBinding?: (deployment: Deployment) => Promise<void>; storage?: StorageDependencies}
const boundary = {contract_version: 1, scope: unattendedScope, local_host_evidence: true, sender_actions: 0, credentials_printed: false, automatic_replay: false, cadence_verified: false, carrier_delivery_verified: false};
function projected(status: string, requestId: string | null, state: HostObservation | null = null): Json {return {status, ...boundary, request_id: requestId, host: state};}
function proofValid(value: OwnerActivationProof, deployment: Deployment, now: number) {
  return keys(value, ["actor_id", "session_id", "profile_sha256", "helper_sha256", "principal_id", "key_sha256", "identity_expires_at", "checked_at", "sample_valid_until"]) &&
    uuid(value.actor_id) && uuid(value.session_id) && value.profile_sha256 === deployment.manifest.profile_sha256 && value.helper_sha256 === deployment.manifest.helper_sha256 &&
    value.principal_id === deployment.manifest.identity.principalId && value.key_sha256 === deployment.manifest.identity.keySha256 && value.identity_expires_at === deployment.manifest.identity.expiresAt &&
    utc(value.checked_at) && utc(value.sample_valid_until) && Date.parse(value.sample_valid_until) - Date.parse(value.checked_at) === 60000 &&
    Date.parse(value.checked_at) <= now + 10000 && now < Date.parse(value.sample_valid_until) && Date.parse(value.identity_expires_at) > now + 15000;
}
async function onceCommand(store: UnattendedStore, operation: Operation, suffix: "armed" | "step", command: string,
  args: readonly string[], launchctl: Launchctl, now: () => number) {
  if (now() >= Date.parse(operation.request_expires_at)) throw Error("SCHEDULER_OPERATION_UNKNOWN");
  const claim = {contract_version: 1, request_id: operation.request_id, command, checkpoint_sha256: sha256(JSON.stringify(operation))};
  await store.publish(`${operation.request_id}.${suffix}.json`, claim);
  if (JSON.stringify(await store.read(`${operation.request_id}.${suffix}.json`)) !== JSON.stringify(claim) || now() >= Date.parse(operation.request_expires_at)) throw Error("SCHEDULER_OPERATION_UNKNOWN");
  const result = await launchctl(args);
  if (!bounded(result) || result.uncertain || result.code !== 0) throw Error("SCHEDULER_OPERATION_UNKNOWN");
}
export async function controlScheduler(action: "activate" | "status" | "disable" | "reconcile", directory: string, requestId?: string, lookupId?: string,
  dependencies: ControlDependencies = {}): Promise<Json> {
  const launch = dependencies.launchctl ?? localLaunchctl, now = dependencies.now ?? Date.now;
  const launchBound = dependencies.launchTimeoutMs ?? 5000, ownerBound = dependencies.ownerTimeoutMs ?? 15000;
  const launchctl: Launchctl = args => deadline(launch(args), launchBound, "SCHEDULER_OPERATION_UNKNOWN");
  let deployment: Deployment | undefined, operation: Operation | undefined;
  try {
    if (!Number.isSafeInteger(launchBound) || launchBound < 1 || launchBound > 5000 || !Number.isSafeInteger(ownerBound) || ownerBound < 1 || ownerBound > 15000 ||
        !["activate", "status", "disable", "reconcile"].includes(action) || action !== "status" && !uuid(requestId) || action === "reconcile" && (!uuid(lookupId) || requestId === lookupId)) throw Error("SCHEDULER_ARGUMENTS_INVALID");
    deployment = await deadline(loadSchedulerDeployment(directory, action === "activate"), 30000, "SCHEDULER_DEPLOYMENT_UNVERIFIED");
    const store = controlStore(deployment), target = `gui/${deployment.manifest.uid}/${schedulerLabel}`;
    const activation = await activationOriginal(deployment, store), disabled = activation && await disabledOriginal(deployment, activation, store);
    if (action === "status") {
      const storage = await schedulerStorageDiagnostics(deployment, now(), dependencies.storage);
      let host: HostObservation;
      try {host = await observe(deployment, launchctl);} catch {host = {state: "unknown", loaded: null, disabled: null, process_running: null};}
      return {...projected(disabled ? "SCHEDULER_LOCAL_DISABLED" : activation ? "SCHEDULER_LOCAL_ACTIVATION_RETAINED" : "SCHEDULER_PREPARED_INACTIVE", activation?.request_id ?? null, host), storage};
    }
    if (action === "reconcile") {
      const original = await store.read(`${requestId}.checkpoint.json`);
      if (!validOperation(original, deployment, requestId!)) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
      const host = await observe(deployment, launchctl);
      const status = original.action === "activate" && activation?.request_id === requestId && !disabled && host.loaded === true && host.disabled === false ? "SCHEDULER_ACTIVATION_OBSERVED" :
        original.action === "disable" && disabled?.request_id === requestId && host.loaded === false && host.disabled === true ? "SCHEDULER_DISABLE_OBSERVED" : "SCHEDULER_OPERATION_UNKNOWN";
      const evidence = {contract_version: 1, request_id: lookupId, original_request_id: requestId, checkpoint_sha256: sha256(JSON.stringify(original)), observed_at: new Date(now()).toISOString(), status, host};
      const storage = await schedulerStorageDiagnostics(deployment, now(), dependencies.storage);
      // Investigation remains available when capacity cannot safely retain a
      // new lookup. It neither closes the original nor supplies action proof.
      if (storage.admission_available !== true) return {...projected("SCHEDULER_OPERATION_UNKNOWN", requestId!, host), storage, lookup_retained: false};
      await store.publish(`${lookupId}.lookup.json`, evidence);
      return {...projected(status, requestId!, host), lookup_retained: true};
    }
    if (activation && action === "activate" || disabled) throw Error("SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
    if (action === "disable" && !activation) return projected("SCHEDULER_PREPARED_INACTIVE", requestId!);
    let proof: OwnerActivationProof | null = null;
    if (action === "activate") {
      const storage = await schedulerStorageDiagnostics(deployment, now(), dependencies.storage);
      if (storage.admission_available !== true) return {...projected("SCHEDULER_STORAGE_ADMISSION_REQUIRED", requestId!), storage};
      const before = await observe(deployment, launchctl);
      if (before.state === "unknown" || before.state === "conflicting" || before.loaded !== false) throw Error("SCHEDULER_HOST_UNVERIFIED");
      await (dependencies.executionBinding ?? assertSchedulerExecutionBinding)(deployment);
      if (!validIdentity(deployment.manifest.identity, now())) throw Error("SCHEDULER_IDENTITY_UNAVAILABLE");
      proof = await deadline((dependencies.owner ?? currentSchedulerOwner)(deployment), ownerBound, "SCHEDULER_OWNER_VALIDATION_REQUIRED");
      if (!proofValid(proof, deployment, now())) throw Error("SCHEDULER_OWNER_VALIDATION_REQUIRED");
      const checked = await deadline(loadSchedulerDeployment(directory, true), 30000, "SCHEDULER_DEPLOYMENT_UNVERIFIED"); if (checked.manifestSha !== deployment.manifestSha) throw Error("SCHEDULER_DEPLOYMENT_UNVERIFIED");
      const finalStorage = await schedulerStorageDiagnostics(deployment, now(), dependencies.storage);
      if (finalStorage.admission_available !== true) return {...projected("SCHEDULER_STORAGE_ADMISSION_REQUIRED", requestId!), storage: finalStorage};
    }
    const created = now();
    operation = {contract_version: 1, kind: "local_scheduler_operation", scope: unattendedScope, origin: enrollmentOrigin, action, request_id: requestId!,
      preparation_sha256: deployment.manifestSha, profile_sha256: deployment.manifest.profile_sha256, principal_id: deployment.manifest.identity.principalId,
      key_sha256: deployment.manifest.identity.keySha256, uid: deployment.manifest.uid, label: schedulerLabel, created_at: new Date(created).toISOString(),
      request_expires_at: new Date(created + 30000).toISOString(), actor_id: proof?.actor_id ?? null, session_id: proof?.session_id ?? null,
      activation_request_id: activation?.request_id ?? null};
    await store.publish(`${requestId}.checkpoint.json`, operation);
    if (JSON.stringify(await store.read(`${requestId}.checkpoint.json`)) !== JSON.stringify(operation)) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
    if (action === "activate") {
      await store.publish(claimName(deployment), {contract_version: 1, request_id: requestId, checkpoint_sha256: sha256(JSON.stringify(operation)), preparation_sha256: deployment.manifestSha});
      if (!proofValid(proof!, deployment, now())) throw Error("SCHEDULER_OPERATION_UNKNOWN");
      await onceCommand(store, operation, "armed", "enable", ["enable", target], launchctl, now);
      if (!proofValid(proof!, deployment, now()) || await disabledOriginal(deployment, operation, store)) throw Error("SCHEDULER_OPERATION_UNKNOWN");
      await onceCommand(store, operation, "step", "bootstrap", ["bootstrap", `gui/${deployment.manifest.uid}`, join(directory, `${schedulerLabel}.plist`)], launchctl, now);
    } else {
      // This irreversible-for-this-deployment latch precedes even read-only
      // daemon IPC. An unavailable or conflicting daemon must not keep local
      // future ticks authorized; it only prevents mutating that daemon job.
      await store.publish(`${activation!.request_id}.closed.json`, {contract_version: 1, request_id: requestId, activation_request_id: activation!.request_id,
        checkpoint_sha256: sha256(JSON.stringify(operation)), preparation_sha256: deployment.manifestSha});
      const retained = await disabledOriginal(deployment, activation!, store);
      if (!retained || JSON.stringify(retained) !== JSON.stringify(operation)) throw Error("SCHEDULER_LOCAL_INTEGRITY_REQUIRED");
      const before = await observe(deployment, launchctl);
      if (before.state === "unknown" || before.state === "conflicting") throw Error("SCHEDULER_HOST_UNVERIFIED");
      await onceCommand(store, operation, "armed", "disable", ["disable", target], launchctl, now);
      await onceCommand(store, operation, "step", "bootout", ["bootout", target], launchctl, now);
    }
    const host = await observe(deployment, launchctl);
    const status = action === "activate" && host.loaded === true && host.disabled === false ? "SCHEDULER_ACTIVATION_OBSERVED" :
      action === "disable" && host.loaded === false && host.disabled === true ? "SCHEDULER_DISABLE_OBSERVED" : "SCHEDULER_OPERATION_UNKNOWN";
    await store.publish(`${requestId}.outcome.json`, {contract_version: 1, request_id: requestId, checkpoint_sha256: sha256(JSON.stringify(operation)), status, observed_at: new Date(now()).toISOString(), host});
    return projected(status, requestId!, host);
  } catch (error) {
    const allowed = new Set(["SCHEDULER_ARGUMENTS_INVALID", "SCHEDULER_DEPLOYMENT_UNVERIFIED", "SCHEDULER_LOCAL_INTEGRITY_REQUIRED", "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED",
      "SCHEDULER_HOST_UNVERIFIED", "SCHEDULER_IDENTITY_UNAVAILABLE", "SCHEDULER_OWNER_VALIDATION_REQUIRED", "SCHEDULER_EXECUTION_BINDING_REQUIRED"]);
    return projected(operation ? "SCHEDULER_OPERATION_UNKNOWN" : error instanceof Error && allowed.has(error.message) ? error.message : "SCHEDULER_CONTROL_UNAVAILABLE", uuid(requestId) ? requestId : null);
  }
}
