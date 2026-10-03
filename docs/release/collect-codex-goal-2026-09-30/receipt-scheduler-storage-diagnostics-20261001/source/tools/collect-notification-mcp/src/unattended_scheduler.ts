import {createHash, randomUUID} from "node:crypto";
import {pathToFileURL} from "node:url";
import {loadUnattendedProfile, type UnattendedProfile} from "./unattended_profile.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {historyHead} from "./unattended_history.ts";
import {runUnattended} from "./unattended_runner.ts";
import {keys, uuid, utc, unattendedScope, validIdentity, type Json} from "./unattended_contract.ts";

export interface SchedulerOptions {profilePath: string; maxEvents: number; intervalSeconds: number}
export function parseSchedulerOptions(args: readonly string[]): SchedulerOptions {
  if (args[0] !== "--tick" || args.length < 3 || args.length > 7) throw Error("SCHEDULER_ARGUMENTS_INVALID");
  const fields = new Map<string, string>();
  for (let i = 1; i < args.length; i += 2) {
    const key = args[i], value = args[i + 1];
    if (!key || !value || !["--profile", "--max-events", "--interval-seconds"].includes(key) || fields.has(key)) throw Error("SCHEDULER_ARGUMENTS_INVALID");
    fields.set(key, value);
  }
  const profilePath = fields.get("--profile"), max = fields.get("--max-events") ?? "5", interval = fields.get("--interval-seconds") ?? "60";
  if (!profilePath?.startsWith("/") || profilePath.includes("\0") || !/^(?:[1-9]|10)$/.test(max) ||
      !/^[1-9][0-9]{1,3}$/.test(interval) || Number(interval) < 60 || Number(interval) > 3600) throw Error("SCHEDULER_ARGUMENTS_INVALID");
  return {profilePath, maxEvents: Number(max), intervalSeconds: Number(interval)};
}

/** Same principal/key/time window produces one original batch identity. This
 * is a local scheduler deduplication key, never a backend authority token. */
export function schedulerRequestId(profile: UnattendedProfile, at: number, seconds: number): string {
  if (!Number.isSafeInteger(at) || at < 0 || !Number.isSafeInteger(seconds) || seconds < 60 || seconds > 3600) throw Error("SCHEDULER_ARGUMENTS_INVALID");
  const bytes = createHash("sha256").update(`collect-receipt-schedule-v2:${profile.identity.principalId}:${profile.identity.keySha256}:${seconds}:${Math.floor(at / (seconds * 1000))}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x40; bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const h = bytes.toString("hex"); return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}

async function head(profile: UnattendedProfile, store: UnattendedStore, now: number): Promise<string | null> {
  try {return await historyHead(store, profile.identity, now);}
  catch (error) {
    if (error instanceof Error && error.message === "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED") throw Error("SCHEDULER_JOURNAL_INTEGRITY_REQUIRED");
    if (error instanceof Error && error.message === "UNATTENDED_HISTORY_MAINTENANCE_REQUIRED") throw Error("SCHEDULER_HISTORY_MAINTENANCE_REQUIRED");
    throw error;
  }
}

export async function runSchedulerTick(args: readonly string[], dependencies: {
  profile?: (path: string) => Promise<UnattendedProfile>; run?: (args: readonly string[]) => Promise<Json>;
  now?: () => number; store?: (directory: string) => UnattendedStore; uuid?: () => string;
} = {}): Promise<Json> {
  const boundary = {contract_version: 2, scope: unattendedScope, sender_actions: 0, credentials_printed: false, automatic_replay: false};
  try {
    const options = parseSchedulerOptions(args), now = dependencies.now ?? Date.now;
    const profile = await (dependencies.profile ?? loadUnattendedProfile)(options.profilePath);
    if (!validIdentity(profile.identity, now())) throw Error("SCHEDULER_IDENTITY_UNAVAILABLE");
    const store = (dependencies.store ?? (directory => new UnattendedStore(directory)))(profile.journal_directory);
    const run = dependencies.run ?? runUnattended;
    const current = await head(profile, store, now()), planned = schedulerRequestId(profile, now(), options.intervalSeconds);
    if (current !== null) {
      const state = await run(["--status", "--request-id", current, "--profile", options.profilePath]);
      if (!keys(state, ["status", "contract_version", "scope", "request_id", "sender_actions", "credentials_printed", "unresolved_request_id", "evidence"]) ||
          state.contract_version !== 2 || state.scope !== unattendedScope || state.request_id !== current || state.sender_actions !== 0 || state.credentials_printed !== false ||
          state.evidence !== "historical_local_only" || state.unresolved_request_id !== null && !uuid(state.unresolved_request_id)) throw Error("SCHEDULER_JOURNAL_INTEGRITY_REQUIRED");
      if (state.status === "UNATTENDED_LOCAL_RUN_UNRESOLVED") {
        const unstarted = await run(["--recover-unstarted", "--request-id", current, "--profile", options.profilePath]);
        if (unstarted.status === "UNATTENDED_NOT_STARTED") return {status: "SCHEDULER_UNSTARTED_RUN_CLOSED", ...boundary, request_id: current, business_handled: false};
        const original = state.unresolved_request_id ?? current;
        const lookupId = (dependencies.uuid ?? randomUUID)();
        if (!uuid(lookupId) || lookupId === original) throw Error("SCHEDULER_ARGUMENTS_INVALID");
        const result = await run(["--lookup", "--request-id", String(original), "--lookup-id", lookupId,
          "--run-request-id", current, "--profile", options.profilePath]);
        const closed = result.local_recovery === "UNATTENDED_COMPLETED" || result.local_recovery === "UNATTENDED_LEASE_EXPIRED_AFTER_LOOKUP" ||
          result.local_recovery === "UNATTENDED_NOT_RECORDED" || result.local_recovery === "OPERATIONS_PAUSED" || result.local_recovery === "RUN_BUSY" || result.local_recovery === "PRINCIPAL_SCOPE_UNCONFIGURED";
        // Recovery never sends another business mutation in this same tick.
        return {status: closed ? "SCHEDULER_ORIGINAL_RECONCILED" : "SCHEDULER_RECONCILIATION_PENDING", ...boundary,
          request_id: current, original_request_id: original, business_handled: false};
      }
      if (state.status !== "UNATTENDED_LOCAL_RUN_CLOSED") throw Error("SCHEDULER_JOURNAL_INTEGRITY_REQUIRED");
      const closed = await store.read(`${current}.closed.json`);
      if (!keys(closed, ["contract_version", "request_id", "status", "closed_at", "not_before"]) || closed.contract_version !== 2 ||
          closed.request_id !== current || !utc(closed.not_before) || !utc(closed.closed_at) || Date.parse(closed.closed_at) > now() ||
          Date.parse(closed.not_before) < Date.parse(closed.closed_at)) throw Error("SCHEDULER_JOURNAL_INTEGRITY_REQUIRED");
      if (current === planned || Date.parse(closed.not_before) > now()) return {status: "SCHEDULER_BACKOFF", ...boundary, request_id: current, business_handled: false};
    }
    const result = await run(["--once", "--request-id", planned, "--profile", options.profilePath, "--max-events", String(options.maxEvents)]);
    const statuses = new Set(["UNATTENDED_COMPLETED", "OPERATIONS_PAUSED", "RUN_BUSY", "PRINCIPAL_SCOPE_UNCONFIGURED",
      "UNATTENDED_OUTCOME_UNKNOWN", "UNATTENDED_LOCAL_OVERLAP_RECONCILIATION_REQUIRED", "UNATTENDED_LOCAL_BACKOFF_ACTIVE",
      "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED", "UNATTENDED_RUN_DEADLINE_OR_LEASE_EXPIRED"]);
    if (!statuses.has(String(result.status)) || result.request_id !== planned || result.sender_actions !== 0 || result.credentials_printed !== false) throw Error("SCHEDULER_RUN_UNVERIFIED");
    const counts: Json = {};
    if (result.status === "UNATTENDED_COMPLETED") {
      for (const name of ["handled_count", "deferred_count", "action_count", "recorded_sms_segments"]) {
        const value = result[name];
        if (!Number.isSafeInteger(value) || Number(value) < 0 || Number(value) > 1_000_000_000) throw Error("SCHEDULER_RUN_UNVERIFIED");
        counts[name] = value;
      }
    }
    return {status: result.status === "UNATTENDED_COMPLETED" ? "SCHEDULER_BATCH_COMPLETED" : "SCHEDULER_BATCH_DEFERRED",
      ...boundary, request_id: planned, reason_code: result.status, ...counts, complete_backlog_verified: false, carrier_delivery_verified: false};
  } catch (error) {
    const allowed = new Set(["SCHEDULER_ARGUMENTS_INVALID", "SCHEDULER_IDENTITY_UNAVAILABLE", "SCHEDULER_JOURNAL_INTEGRITY_REQUIRED",
      "SCHEDULER_HISTORY_MAINTENANCE_REQUIRED", "SCHEDULER_RUN_UNVERIFIED", "UNATTENDED_PROFILE_UNAVAILABLE", "UNATTENDED_JOURNAL_UNAVAILABLE", "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"]);
    return {status: error instanceof Error && allowed.has(error.message) ? error.message : "SCHEDULER_UNAVAILABLE", ...boundary, business_handled: false};
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await runSchedulerTick(process.argv.slice(2)); console.log(JSON.stringify(result));
  if (!["SCHEDULER_BATCH_COMPLETED", "SCHEDULER_BACKOFF", "SCHEDULER_ORIGINAL_RECONCILED", "SCHEDULER_UNSTARTED_RUN_CLOSED"].includes(String(result.status))) process.exitCode = 2;
}
