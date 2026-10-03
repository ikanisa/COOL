import {spawn} from "node:child_process";
import {fileURLToPath, pathToFileURL} from "node:url";
import {realpath} from "node:fs/promises";
import {join} from "node:path";
import {uuid, integer, unattendedScope, type Json} from "./unattended_contract.ts";
import {selectedSchedulerPath, loadSchedulerDeployment} from "./unattended_deployment.ts";
import {controlScheduler, type ControlDependencies} from "./unattended_scheduler_control.ts";

export interface ScheduleCliOptions {command: "prepare" | "activate" | "status" | "disable" | "reconcile"; deployment: string;
  profile?: string; requestId?: string; lookupId?: string; intervalSeconds?: number; maxEvents?: number}
export function scheduleCliOptions(args: readonly string[]): ScheduleCliOptions {
  const command = args[0];
  if (!command || !["prepare", "activate", "status", "disable", "reconcile"].includes(command) || args.length % 2 !== 1) throw Error("SCHEDULER_ARGUMENTS_INVALID");
  const allowed: Record<string, string[]> = {prepare: ["--deployment", "--profile", "--interval-seconds", "--max-events"], activate: ["--deployment", "--request-id"],
    status: ["--deployment"], disable: ["--deployment", "--request-id"], reconcile: ["--deployment", "--request-id", "--lookup-id"]};
  const fields = new Map<string, string>();
  for (let index = 1; index < args.length; index += 2) {const key = args[index], value = args[index + 1];
    if (!key || !value || !allowed[command]!.includes(key) || fields.has(key)) throw Error("SCHEDULER_ARGUMENTS_INVALID"); fields.set(key, value);}
  const deployment = fields.get("--deployment"), profile = fields.get("--profile"), requestId = fields.get("--request-id"), lookupId = fields.get("--lookup-id");
  if (!selectedSchedulerPath(deployment) || command === "prepare" && !selectedSchedulerPath(profile) ||
      ["activate", "disable", "reconcile"].includes(command) && !uuid(requestId) || command === "reconcile" && (!uuid(lookupId) || lookupId === requestId)) throw Error("SCHEDULER_ARGUMENTS_INVALID");
  if (command === "prepare") {
    const interval = fields.get("--interval-seconds") ?? "60", max = fields.get("--max-events") ?? "5";
    if (!/^[1-9][0-9]*$/.test(interval) || !integer(Number(interval), 60, 3600) || !/^[1-9][0-9]*$/.test(max) || !integer(Number(max), 1, 10)) throw Error("SCHEDULER_ARGUMENTS_INVALID");
    return {command, deployment, profile: profile!, intervalSeconds: Number(interval), maxEvents: Number(max)};
  }
  return {command: command as ScheduleCliOptions["command"], deployment, ...(requestId ? {requestId} : {}), ...(lookupId ? {lookupId} : {})};
}
async function prepare(options: ScheduleCliOptions): Promise<Json> {
  const source = fileURLToPath(new URL("../", import.meta.url)).replace(/\/$/, ""), node = await realpath(process.execPath);
  const args = [join(source, "scripts/prepare_unattended_launchd.py"), "--profile", options.profile!, "--node", node, "--source-directory", source,
    "--output-directory", options.deployment, "--interval-seconds", String(options.intervalSeconds), "--max-events", String(options.maxEvents)];
  await new Promise<void>((resolve, reject) => {
    const child = spawn("/usr/bin/python3", args, {stdio: ["ignore", "ignore", "ignore"], env: {PATH: "/usr/bin:/bin", LANG: "C", PYTHONUTF8: "1"}});
    let settled = false; const finish = (ok: boolean) => {if (settled) return; settled = true; clearTimeout(timer); ok ? resolve() : reject(Error("SCHEDULER_PREPARATION_REFUSED"));};
    const timer = setTimeout(() => {child.kill("SIGKILL"); finish(false);}, 30000);
    child.on("error", () => finish(false)); child.on("close", code => finish(code === 0));
  });
  const deployment = await loadSchedulerDeployment(options.deployment, true);
  return {status: "SCHEDULER_PREPARED_INACTIVE", contract_version: 1, scope: unattendedScope, installed: false, started: false,
    preparation_sha256: deployment.manifestSha, principal_id: deployment.manifest.identity.principalId,
    sender_actions: 0, credentials_printed: false, cadence_verified: false};
}
export async function scheduleCli(args: readonly string[], dependencies: ControlDependencies & {prepare?: (options: ScheduleCliOptions) => Promise<Json>} = {}): Promise<Json> {
  let options: ScheduleCliOptions | undefined;
  try {
    options = scheduleCliOptions(args);
    return options.command === "prepare" ? await (dependencies.prepare ?? prepare)(options) :
      await controlScheduler(options.command, options.deployment, options.requestId, options.lookupId, dependencies);
  } catch {return {status: "SCHEDULER_PREPARATION_OR_ARGUMENTS_REFUSED", contract_version: 1, scope: unattendedScope, request_id: options?.requestId ?? null,
    sender_actions: 0, credentials_printed: false, automatic_replay: false, cadence_verified: false};}
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await scheduleCli(process.argv.slice(2)); console.log(JSON.stringify(result));
  if (!["SCHEDULER_PREPARED_INACTIVE", "SCHEDULER_ACTIVATION_OBSERVED", "SCHEDULER_DISABLE_OBSERVED", "SCHEDULER_LOCAL_DISABLED", "SCHEDULER_LOCAL_ACTIVATION_RETAINED"].includes(String(result.status))) process.exitCode = 2;
}
