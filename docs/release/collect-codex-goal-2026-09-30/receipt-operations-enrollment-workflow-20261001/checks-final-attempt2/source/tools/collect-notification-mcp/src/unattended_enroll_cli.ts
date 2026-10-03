import {pathToFileURL} from "node:url";
import {isAbsolute} from "node:path";
import {runtimeCredentials} from "./runtime_credentials.ts";
import {unattendedKeychainSigner} from "./unattended_client.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {EnrollmentPreparation} from "./unattended_enrollment.ts";
import {enrollmentOwner, enrollmentOwnerRpc, listEnrollmentIdentities} from "./unattended_enrollment_owner.ts";
import {createEnrollmentKey, readEnrollmentKey, validateInstalledEnrollmentProfile} from "./unattended_profile_preparation.ts";
import {uuid, hash, utc, keys} from "./unattended_contract.ts";
import {EnrollmentJournal} from "./unattended_enrollment_journal.ts";
import {localEnrollmentStatus, revokePreparedIdentity} from "./unattended_revocation.ts";
export interface EnrollmentCliOptions {command: "create-key" | "read-key" | "prepare" | "resume" | "reconcile" | "verify" | "list" | "status" | "lookup" | "revoke";
  directory?: string; helper?: string; helperSha?: string; profile?: string; workflowId?: string; enrollId?: string; proofId?: string; activateId?: string;
  requestId?: string; lookupId?: string; expiresAt?: string; limit?: string; beforeCreatedAt?: string; beforePrincipalId?: string; keyTagId?: string; reasonSource?: string}
export function enrollmentCliOptions(args: string[]): EnrollmentCliOptions {
  const command = args[0];
  const fields: Record<string, keyof EnrollmentCliOptions> = {"--directory": "directory", "--helper": "helper", "--helper-sha": "helperSha", "--profile": "profile",
    "--workflow-id": "workflowId", "--enroll-id": "enrollId", "--proof-id": "proofId", "--activate-id": "activateId", "--request-id": "requestId", "--lookup-id": "lookupId", "--expires-at": "expiresAt",
    "--limit": "limit", "--before-created-at": "beforeCreatedAt", "--before-principal-id": "beforePrincipalId", "--key-tag-id": "keyTagId", "--reason-source": "reasonSource"};
  const expected: Record<string, string[]> = {"create-key": ["directory", "helper", "helperSha", "requestId"], "read-key": ["helper", "helperSha"],
    prepare: ["directory", "helper", "helperSha", "profile", "workflowId", "enrollId", "proofId", "activateId", "expiresAt"],
    resume: ["directory", "workflowId"], reconcile: ["directory", "workflowId", "requestId", "lookupId"], verify: ["profile"],
    list: args.length === 7 ? ["limit", "beforeCreatedAt", "beforePrincipalId"] : ["limit"], status: ["directory", "requestId"], lookup: ["directory", "requestId", "lookupId"],
    revoke: ["directory", "profile", "requestId", "reasonSource"]};
  if (command && ["create-key", "read-key", "prepare"].includes(command) && args.includes("--key-tag-id")) expected[command]!.push("keyTagId");
  const names = command && expected[command];
  if (!names || args.length !== 1 + names.length * 2) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  const value: Record<string, string> = {command};
  for (let index = 1; index < args.length; index += 2) {
    const key = fields[args[index] ?? ""], input = args[index + 1];
    if (!key || !names.includes(key) || Object.hasOwn(value, key) || !input || input.includes("\0")) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
    value[key] = input;
  }
  for (const name of names) {
    const input = value[name];
    if (!input || (name.endsWith("Id") && !uuid(input)) || (["directory", "helper", "profile"].includes(name) && !isAbsolute(input)) ||
        name === "helperSha" && !hash(input) || ["expiresAt", "beforeCreatedAt"].includes(name) && !utc(input) ||
        name === "limit" && (!/^\d{1,2}$/.test(input) || Number(input) < 1 || Number(input) > 25) || name === "reasonSource" && input !== "stdin") throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  }
  if (command === "prepare" && new Set([value.workflowId, value.enrollId, value.proofId, value.activateId]).size !== 4 ||
      ["reconcile", "lookup"].includes(command!) && value.requestId === value.lookupId) throw new Error("ENROLLMENT_ARGUMENTS_INVALID");
  return value as unknown as EnrollmentCliOptions;
}
export async function enrollmentCli(options: EnrollmentCliOptions, environment = process.env) {
  if (options.command === "read-key") return readEnrollmentKey({helper_path: options.helper!, helper_sha256: options.helperSha!, ...(options.keyTagId ? {key_tag_id: options.keyTagId} : {})}, "read-public");
  if (options.command === "status") return localEnrollmentStatus(options.directory!, options.requestId!);
  // Standard governed current-user credentials only. This CLI never sends OTP,
  // signs up, refreshes a rotating token, or reads a service-role credential.
  const runtime = await runtimeCredentials(environment, {allowRefresh: false});
  const owner = await enrollmentOwner(runtime), rpc = enrollmentOwnerRpc(owner);
  if (options.command === "lookup") {
    const result = await new EnrollmentJournal(options.directory!, owner.actorId, owner.sessionId).reconcile(options.requestId!, options.lookupId!, rpc);
    return {contract_version: 3, original_request_id: options.requestId, lookup_request_id: options.lookupId, outcome: result.outcome, reason_code: result.reason_code, scheduler_started: false};
  }
  if (options.command === "revoke") {
    const result = await revokePreparedIdentity(options.directory!, options.profile!, options.requestId!, owner.actorId, owner.sessionId, rpc, await readPrivateReason());
    return {contract_version: 3, original_request_id: options.requestId, outcome: result.outcome, reason_code: result.reason_code,
      identity_state_at_action: result.receipt?.state_at_action ?? null, local_keys_deleted: false, scheduler_started: false};
  }
  if (options.command === "list") return listEnrollmentIdentities(rpc, Number(options.limit), options.beforeCreatedAt ? {created_at: options.beforeCreatedAt, principal_id: options.beforePrincipalId!} : null);
  if (options.command === "create-key") {
    const publicKey = await createEnrollmentKey(options.directory!, options.requestId!, {helper_path: options.helper!, helper_sha256: options.helperSha!, ...(options.keyTagId ? {key_tag_id: options.keyTagId} : {})});
    return {contract_version: 3, status: "KEY_CREATED", request_id: options.requestId, key_sha256: publicKey.key_sha256, scheduler_started: false};
  }
  if (options.command === "verify") return validateInstalledEnrollmentProfile(options.profile!, rpc);
  let helper = options.helper, helperSha = options.helperSha, keyTagId = options.keyTagId;
  if (options.command !== "prepare") {
    const plan = await new UnattendedStore(options.directory!).read(`${options.workflowId}.run.json`);
    if (!keys(plan, ["contract_version", "scope", "origin", "workflow_id", "actor_id", "created_at", "enrollment_request_id", "proof_request_id", "activation_request_id", "public_key", "identity_expires_at", "helper", "profile_path", "journal_directory"]) ||
        !keys(plan.helper, plan.helper !== null && typeof plan.helper === "object" && Object.hasOwn(plan.helper, "key_tag_id") ? ["helper_path", "helper_sha256", "key_tag_id"] : ["helper_path", "helper_sha256"]) ||
        typeof plan.helper.helper_path !== "string" || typeof plan.helper.helper_sha256 !== "string" || plan.helper.key_tag_id !== undefined && !uuid(plan.helper.key_tag_id)) throw new Error("ENROLLMENT_JOURNAL_INTEGRITY_REQUIRED");
    helper = plan.helper.helper_path; helperSha = plan.helper.helper_sha256;
    keyTagId = plan.helper.key_tag_id as string | undefined;
  }
  const flow = new EnrollmentPreparation(options.directory!, owner.actorId, owner.sessionId, rpc, unattendedKeychainSigner(helper!, helperSha!, keyTagId));
  if (options.command === "prepare") await flow.create({workflow_id: options.workflowId!, enrollment_request_id: options.enrollId!, proof_request_id: options.proofId!,
    activation_request_id: options.activateId!, identity_expires_at: options.expiresAt!, helper: {helper_path: helper!, helper_sha256: helperSha!, ...(keyTagId ? {key_tag_id: keyTagId} : {})}, profile_path: options.profile!});
  if (options.command === "reconcile") {
    const result = await flow.reconcile(options.workflowId!, options.requestId!, options.lookupId!);
    return {contract_version: 3, status: result.outcome === "recorded" ? "ORIGINAL_RECORDED" : result.outcome === "not_recorded" ? "ORIGINAL_NOT_RECORDED" : "ORIGINAL_UNKNOWN",
      original_request_id: options.requestId, lookup_request_id: options.lookupId, reason_code: result.reason_code, scheduler_started: false};
  }
  return flow.resume(options.workflowId!);
}
async function readPrivateReason(): Promise<string> {
  return new Promise((resolve, reject) => {
    let length = 0; const chunks: Buffer[] = [];
    const timer = setTimeout(() => finish(), 30_000);
    const finish = (value?: string) => {clearTimeout(timer); process.stdin.removeListener("data", data); process.stdin.removeListener("end", end); process.stdin.pause();
      value === undefined ? reject(new Error("ENROLLMENT_REASON_UNAVAILABLE")) : resolve(value);};
    const end = () => {try {finish(new TextDecoder("utf-8", {fatal: true}).decode(Buffer.concat(chunks)).trim());} catch {finish();}};
    const data = (chunk: Buffer) => {length += chunk.length; if (length > 2000) finish(); else {chunks.push(chunk); if (chunk.includes(10)) end();}};
    process.stdin.on("data", data); process.stdin.once("end", end); process.stdin.resume();
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let options: EnrollmentCliOptions | undefined;
  Promise.resolve().then(() => {options = enrollmentCliOptions(process.argv.slice(2)); return enrollmentCli(options);}).then(result => console.log(JSON.stringify(result))).catch(() => {
    console.error(JSON.stringify({status: "ENROLLMENT_PREPARATION_INCOMPLETE", workflow_id: options?.workflowId ?? null,
      supplied_original_request_ids: [options?.enrollId, options?.proofId, options?.activateId, options?.requestId].filter(value => value !== undefined),
      automatic_replay: false, credentials_printed: false, scheduler_started: false})); process.exitCode = 2;
  });
}
