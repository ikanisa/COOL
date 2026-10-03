import {pathToFileURL} from "node:url";
import {loadSchedulerDeployment, selectedSchedulerPath, assertSchedulerExecutionBinding, type Deployment} from "./unattended_deployment.ts";
import {schedulerTickPermitted} from "./unattended_scheduler_control.ts";
import {runSchedulerTick} from "./unattended_scheduler.ts";
import {unattendedScope, validIdentity, type Json} from "./unattended_contract.ts";

/** No operator credentials are loaded on this unattended path. Immutable local
 * bindings guard drift; current service identity, policy/lease/quota authority
 * is independently enforced by every existing signed backend operation. */
export async function runPreparedSchedulerTick(args: readonly string[], dependencies: {
  tick?: typeof runSchedulerTick; now?: () => number; executionBinding?: (deployment: Deployment) => Promise<void>;
} = {}): Promise<Json> {
  const boundary = {contract_version: 1, scope: unattendedScope, sender_actions: 0, credentials_printed: false, automatic_replay: false};
  try {
    if (args.length !== 2 || args[0] !== "--deployment" || !selectedSchedulerPath(args[1])) throw Error("SCHEDULER_ARGUMENTS_INVALID");
    const deployment = await loadSchedulerDeployment(args[1], true), now = dependencies.now ?? Date.now;
    await (dependencies.executionBinding ?? assertSchedulerExecutionBinding)(deployment);
    if (!validIdentity(deployment.manifest.identity, now())) throw Error("SCHEDULER_IDENTITY_UNAVAILABLE");
    if (!await schedulerTickPermitted(deployment)) return {status: "SCHEDULER_LOCAL_INACTIVE", ...boundary, business_handled: false};
    return await (dependencies.tick ?? runSchedulerTick)(["--tick", "--profile", deployment.manifest.profile_path,
      "--interval-seconds", String(deployment.manifest.interval_seconds), "--max-events", String(deployment.manifest.max_events)]);
  } catch (error) {
    const allowed = new Set(["SCHEDULER_ARGUMENTS_INVALID", "SCHEDULER_DEPLOYMENT_UNVERIFIED", "SCHEDULER_IDENTITY_UNAVAILABLE", "SCHEDULER_LOCAL_INTEGRITY_REQUIRED", "SCHEDULER_EXECUTION_BINDING_REQUIRED"]);
    return {status: error instanceof Error && allowed.has(error.message) ? error.message : "SCHEDULER_LOCAL_INACTIVE", ...boundary, business_handled: false};
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await runPreparedSchedulerTick(process.argv.slice(2)); console.log(JSON.stringify(result));
  if (!["SCHEDULER_BATCH_COMPLETED", "SCHEDULER_BACKOFF", "SCHEDULER_ORIGINAL_RECONCILED", "SCHEDULER_UNSTARTED_RUN_CLOSED"].includes(String(result.status))) process.exitCode = 2;
}
