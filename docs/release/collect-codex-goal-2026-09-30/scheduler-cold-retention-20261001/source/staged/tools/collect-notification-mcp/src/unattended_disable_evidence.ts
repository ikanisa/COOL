import {keys, uuid, hash, utc, unattendedScope} from "./unattended_contract.ts";
import {enrollmentOrigin} from "./unattended_enrollment_contract.ts";
import {sha256} from "./unattended_enrollment_contract.ts";
/** Only irreversible local stop evidence can cross an inactive restore latch.
 * This cannot reserve v2 business requests or any enable/bootstrap command. */
export function validEmergencyDisableEvidence(name: string, value: unknown): boolean {
  const match = /^([0-9a-f-]{36})\.(checkpoint|closed|armed|step|outcome)\.json$/.exec(name);
  if (!match || !uuid(match[1])) return false;
  const suffix = match[2], id = match[1];
  if (suffix === "checkpoint") return keys(value, ["contract_version", "kind", "scope", "origin", "action", "request_id", "preparation_sha256", "profile_sha256", "principal_id", "key_sha256", "uid", "label", "created_at", "request_expires_at", "actor_id", "session_id", "activation_request_id"]) &&
    value.contract_version === 1 && value.kind === "local_scheduler_operation" && value.scope === unattendedScope && value.origin === enrollmentOrigin &&
    value.action === "disable" && value.request_id === id && hash(value.preparation_sha256) && hash(value.profile_sha256) && uuid(value.principal_id) && hash(value.key_sha256) &&
    value.uid === process.getuid?.() && value.label === "com.ikanisa.collect.receipt-operations" && utc(value.created_at) && utc(value.request_expires_at) &&
    Date.parse(value.request_expires_at) - Date.parse(value.created_at) === 30000 && value.actor_id === null && value.session_id === null &&
    uuid(value.activation_request_id) && value.activation_request_id !== id;
  if (suffix === "closed") return keys(value, ["contract_version", "request_id", "activation_request_id", "checkpoint_sha256", "preparation_sha256"]) &&
    value.contract_version === 1 && uuid(value.request_id) && value.activation_request_id === id && value.request_id !== id && hash(value.checkpoint_sha256) && hash(value.preparation_sha256);
  if (suffix === "armed" || suffix === "step") return keys(value, ["contract_version", "request_id", "command", "checkpoint_sha256"]) &&
    value.contract_version === 1 && value.request_id === id && value.command === (suffix === "armed" ? "disable" : "bootout") && hash(value.checkpoint_sha256);
  return keys(value, ["contract_version", "request_id", "checkpoint_sha256", "status", "observed_at", "host"]) && value.contract_version === 1 && value.request_id === id &&
    hash(value.checkpoint_sha256) && utc(value.observed_at) && ["SCHEDULER_DISABLE_OBSERVED", "SCHEDULER_OPERATION_UNKNOWN"].includes(String(value.status)) &&
    keys(value.host, ["state", "loaded", "disabled", "process_running"]) && ["absent", "loaded", "running", "disabled", "unknown", "conflicting"].includes(String(value.host.state)) &&
    [value.host.loaded, value.host.disabled, value.host.process_running].every(flag => flag === null || typeof flag === "boolean");
}

/** Schema alone must not let the stop-only path manufacture another claim.
 * Every record joins the retained activation and the exact disable original. */
export async function boundEmergencyDisableEvidence(name: string, value: unknown,
  read: (name: string) => Promise<unknown | null>): Promise<boolean> {
  if (!validEmergencyDisableEvidence(name, value)) return false;
  const suffix = name.split(".")[1], evidence = value as Record<string, unknown>;
  const requestId = evidence.request_id as string;
  const original = suffix === "checkpoint" ? evidence : await read(`${requestId}.checkpoint.json`);
  if (!validEmergencyDisableEvidence(`${requestId}.checkpoint.json`, original)) return false;
  const plan = original as Record<string, unknown>, activationId = plan.activation_request_id as string;
  const activation = await read(`${activationId}.checkpoint.json`);
  if (!keys(activation, Object.keys(plan)) || activation.contract_version !== 1 || activation.kind !== plan.kind || activation.scope !== plan.scope ||
      activation.origin !== plan.origin || activation.action !== "activate" || activation.request_id !== activationId ||
      activation.preparation_sha256 !== plan.preparation_sha256 || activation.profile_sha256 !== plan.profile_sha256 ||
      activation.principal_id !== plan.principal_id || activation.key_sha256 !== plan.key_sha256 || activation.uid !== plan.uid ||
      activation.label !== plan.label || !utc(activation.created_at) || !utc(activation.request_expires_at) ||
      Date.parse(activation.request_expires_at) - Date.parse(activation.created_at) !== 30000 || !uuid(activation.actor_id) ||
      !uuid(activation.session_id) || activation.activation_request_id !== null) return false;
  const claim = await read(`principal-${plan.principal_id}.lock.json`);
  if (!keys(claim, ["contract_version", "request_id", "checkpoint_sha256", "preparation_sha256"]) || claim.contract_version !== 1 ||
      claim.request_id !== activationId || claim.checkpoint_sha256 !== sha256(JSON.stringify(activation)) || claim.preparation_sha256 !== plan.preparation_sha256) return false;
  if (suffix === "checkpoint") return true;
  if (evidence.checkpoint_sha256 !== sha256(JSON.stringify(plan))) return false;
  if (suffix === "closed") return evidence.activation_request_id === activationId && evidence.preparation_sha256 === plan.preparation_sha256;
  const stop = await read(`${activationId}.closed.json`);
  return validEmergencyDisableEvidence(`${activationId}.closed.json`, stop) &&
    (stop as Record<string, unknown>).request_id === requestId && (stop as Record<string, unknown>).checkpoint_sha256 === evidence.checkpoint_sha256 &&
    (stop as Record<string, unknown>).preparation_sha256 === plan.preparation_sha256;
}
