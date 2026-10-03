import {pathToFileURL} from "node:url";
import {loadSchedulerDeployment, selectedSchedulerPath, assertSchedulerExecutionBinding, type Deployment} from "./unattended_deployment.ts";
import {schedulerTickPermitted} from "./unattended_scheduler_control.ts";
import {runSchedulerTick} from "./unattended_scheduler.ts";
import {unattendedScope, validIdentity, type Json} from "./unattended_contract.ts";
import {schedulerStorageDiagnostics, beginSchedulerTickDiagnostic, endSchedulerTickDiagnostic, finiteSchedulerTickProjection, type StorageDependencies} from "./unattended_scheduler_storage.ts";

/** No operator credentials are loaded on this unattended path. Immutable local
 * bindings guard drift; current service identity, policy/lease/quota authority
 * is independently enforced by every existing signed backend operation. */
export async function runPreparedSchedulerTick(args: readonly string[], dependencies: {
  tick?: typeof runSchedulerTick; now?: () => number; executionBinding?: (deployment: Deployment) => Promise<void>;
  storage?: StorageDependencies;
} = {}): Promise<Json> {
  const boundary = {contract_version: 1, scope: unattendedScope, sender_actions: 0, credentials_printed: false, automatic_replay: false};
  try {
    if (args.length !== 2 || args[0] !== "--deployment" || !selectedSchedulerPath(args[1])) throw Error("SCHEDULER_ARGUMENTS_INVALID");
    const deployment = await loadSchedulerDeployment(args[1], true), now = dependencies.now ?? Date.now;
    await (dependencies.executionBinding ?? assertSchedulerExecutionBinding)(deployment);
    if (!validIdentity(deployment.manifest.identity, now())) throw Error("SCHEDULER_IDENTITY_UNAVAILABLE");
    if (!await schedulerTickPermitted(deployment)) return {status: "SCHEDULER_LOCAL_INACTIVE", ...boundary, business_handled: false};
    const storage = await schedulerStorageDiagnostics(deployment, now(), dependencies.storage);
    if (storage.admission_available !== true) return {status: "SCHEDULER_STORAGE_ADMISSION_REQUIRED", ...boundary, business_handled: false, storage};
    let started;
    try {started = await beginSchedulerTickDiagnostic(deployment, now());}
    catch {throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");}
    let result: Json;
    try {result = await (dependencies.tick ?? runSchedulerTick)(["--tick", "--profile", deployment.manifest.profile_path,
      "--interval-seconds", String(deployment.manifest.interval_seconds), "--max-events", String(deployment.manifest.max_events)]);}
    catch {result = {status: "TICK_OUTCOME_UNCONFIRMED", ...boundary, business_handled: null};}
    try {await endSchedulerTickDiagnostic(deployment, started, result, now());}
    catch {throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");}
    return result;
  } catch (error) {
    const allowed = new Set(["SCHEDULER_ARGUMENTS_INVALID", "SCHEDULER_DEPLOYMENT_UNVERIFIED", "SCHEDULER_IDENTITY_UNAVAILABLE", "SCHEDULER_LOCAL_INTEGRITY_REQUIRED", "SCHEDULER_EXECUTION_BINDING_REQUIRED", "SCHEDULER_DIAGNOSTICS_UNAVAILABLE"]);
    return {status: error instanceof Error && allowed.has(error.message) ? error.message : "SCHEDULER_LOCAL_INACTIVE", ...boundary, business_handled: false};
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await runPreparedSchedulerTick(process.argv.slice(2));
  // Native errors, runner extras and stacks never enter scheduler stdout.
  console.log(JSON.stringify({...finiteSchedulerTickProjection(result), contract_version: 1, scope: unattendedScope, credentials_printed: false}));
  if (!["SCHEDULER_BATCH_COMPLETED", "SCHEDULER_BACKOFF", "SCHEDULER_ORIGINAL_RECONCILED", "SCHEDULER_UNSTARTED_RUN_CLOSED"].includes(String(result.status))) process.exitCode = 2;
}
