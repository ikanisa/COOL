import {randomUUID} from "node:crypto";
import {pathToFileURL} from "node:url";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {historyHead, validHistoryPlan, validHistoryClosure, type HistoryPlan} from "./unattended_history.ts";
import {unattendedStdio} from "./unattended_stdio.ts";
import type {UnattendedTransport} from "./unattended_stdio.ts";
import {validResult, keys, uuid, utc, unattendedScope, validIdentity, object} from "./unattended_contract.ts";
import type {Json, UnattendedRequest} from "./unattended_contract.ts";
export interface UnattendedOptions {mode: "once" | "lookup" | "status" | "recover-unstarted"; requestId: string; profilePath: string; lookupId?: string; runRequestId?: string; maxEvents: number}
export function parseUnattendedOptions(args: readonly string[]): UnattendedOptions {
  if (!Array.isArray(args) || !["--once", "--lookup", "--status", "--recover-unstarted"].includes(args[0] ?? "") || args.length > 9) throw Error("UNATTENDED_ARGUMENTS_INVALID");
  const fields = new Map<string, string>();
  for (let i = 1; i < args.length; i += 2) {
    const name = args[i], value = args[i + 1];
    if (!name || !value || !["--request-id", "--profile", "--lookup-id", "--run-request-id", "--max-events"].includes(name) || fields.has(name)) throw Error("UNATTENDED_ARGUMENTS_INVALID");
    fields.set(name, value);
  }
  const requestId = fields.get("--request-id"), profilePath = fields.get("--profile"), lookupId = fields.get("--lookup-id"), runRequestId = fields.get("--run-request-id");
  const mode = args[0]!.slice(2) as UnattendedOptions["mode"], max = fields.get("--max-events") ?? "5";
  if (!uuid(requestId) || !profilePath?.startsWith("/") || !/^(?:[1-9]|10)$/.test(max) ||
      (mode === "lookup" ? !uuid(lookupId) || lookupId === requestId : lookupId !== undefined) ||
      (mode !== "once" && fields.has("--max-events")) || (runRequestId !== undefined && (mode !== "lookup" || !uuid(runRequestId)))) throw Error("UNATTENDED_ARGUMENTS_INVALID");
  return {mode, requestId, profilePath, ...(lookupId ? {lookupId} : {}), ...(runRequestId ? {runRequestId} : {}), maxEvents: Number(max)};
}
type Plan = HistoryPlan;
const base = (id: string) => ({contract_version: 2, scope: unattendedScope, request_id: id, sender_actions: 0, credentials_printed: false});
function structured(reply: Record<string, unknown>): Json {
  if (!object(reply.result) || reply.result.isError || !keys(reply.result.structuredContent, ["result"]) || !object(reply.result.structuredContent.result)) throw Error("UNATTENDED_OUTCOME_UNKNOWN");
  return reply.result.structuredContent.result;
}
function validPlan(value: unknown, profile: UnattendedProfile): value is Plan {
  return validHistoryPlan(value, profile.identity);
}
const validClosure = validHistoryClosure;
async function claim(store: UnattendedStore, plan: Plan, now: number): Promise<void> {
  const name = `principal-${plan.principal_id}.lock.json`;
  const first = {contract_version: 2, scope: unattendedScope, principal_id: plan.principal_id, key_sha256: plan.key_sha256, request_id: plan.request_id};
  let current = await store.read(name, true);
  if (current === null) {
    try {await store.publish(name, first); return;}
    catch (error) {if (!(error instanceof Error) || error.message !== "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED") throw error; current = await store.read(name);}
  }
  const id = await historyHead(store, {principalId: plan.principal_id, keySha256: plan.key_sha256}, now);
  if (id === null) throw Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
  const closed = await store.read(`${id}.closed.json`, true);
  if (closed === null) throw Error("UNATTENDED_LOCAL_OVERLAP_RECONCILIATION_REQUIRED");
  if (!validClosure(closed, id, now)) throw Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
  if (Date.parse(String(closed.not_before)) > now) throw Error("UNATTENDED_LOCAL_BACKOFF_ACTIVE");
  await store.publish(`${id}.step.json`, {contract_version: 2, previous_request_id: id, request_id: plan.request_id});
}
export async function runUnattended(args: readonly string[], dependencies: {
  profile?: (path: string) => Promise<UnattendedProfile>; transport?: (path: string) => UnattendedTransport; now?: () => number;
  store?: (directory: string) => UnattendedStore; uuid?: () => string;
} = {}): Promise<Json> {
  let options: UnattendedOptions;
  try {options = parseUnattendedOptions(args);} catch {return {status: "UNATTENDED_ARGUMENTS_INVALID", sender_actions: 0, credentials_printed: false};}
  const boundary = base(options.requestId), now = dependencies.now ?? Date.now;
  let transport: UnattendedTransport | undefined, pending = options.requestId;
  try {
    const profile = await (dependencies.profile ?? loadUnattendedProfile)(options.profilePath);
    const store = (dependencies.store ?? (directory => new UnattendedStore(directory)))(profile.journal_directory);
    if (options.mode === "status" || options.mode === "recover-unstarted") {
      const plan = await store.read(`${options.requestId}.run.json`, true);
      if (plan === null) return {status: "UNATTENDED_LOCAL_RUN_NOT_FOUND", ...boundary};
      if (!validPlan(plan, profile)) throw Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
      const closed = await store.read(`${options.requestId}.closed.json`, true);
      if (closed !== null && !validClosure(closed, options.requestId, now())) throw Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
      let unresolved: string | null = null, started = false;
      for (const id of plan.request_ids) {
        const checkpoint = await store.read(`${id}.checkpoint.json`, true);
        if (checkpoint !== null) {
          started = true;
          const result = await new UnattendedJournal(profile.journal_directory, store).readOriginal(id);
          if (result.outcome === "unknown") {unresolved = id; break;}
        }
      }
      if (options.mode === "recover-unstarted") {
        // Every network call requires a durable checkpoint. The run deadline
        // is fixed relative to the original plan, even across process suspension.
        // This operation closes local overlap only and never contacts a service.
        if (closed === null && !started && now() >= Date.parse(plan.created_at) + 120000) {
          const at = now();
          await store.publish(`${options.requestId}.closed.json`, {contract_version: 2,
            request_id: options.requestId, status: "UNATTENDED_NOT_STARTED", closed_at: new Date(at).toISOString(),
            not_before: new Date(at + 60000).toISOString()});
          return {status: "UNATTENDED_NOT_STARTED", ...boundary, evidence: "local_checkpoint_absence_after_fixed_deadline", automatic_replay: false};
        }
        return {status: "UNATTENDED_LOCAL_RECOVERY_REFUSED", ...boundary, reconciliation_required: closed === null,
          evidence: "local_checkpoint_absence_not_proven", automatic_replay: false};
      }
      return {status: closed === null ? "UNATTENDED_LOCAL_RUN_UNRESOLVED" : "UNATTENDED_LOCAL_RUN_CLOSED", ...boundary, unresolved_request_id: unresolved, evidence: "historical_local_only"};
    }
    const permit = async () => {
      if (await store.retained.inactive()) throw Error("UNATTENDED_JOURNAL_UNAVAILABLE");
      if (!validIdentity(profile.identity, now())) throw Error("UNATTENDED_PROFILE_UNAVAILABLE");
    };
    await permit();
    if (options.mode === "lookup") {
      transport = (dependencies.transport ?? unattendedStdio)(options.profilePath); await transport.initialize();
      await permit();
      const looked = structured(await transport.call("collect_unattended_reconcile_request", {request_id: options.lookupId!, target_request_id: options.requestId}));
      const reasons = ["UNATTENDED_RESULT_RECORDED", "UNATTENDED_ORIGINAL_REQUEST_NOT_RECORDED", "UNATTENDED_ORIGINAL_REQUEST_IN_PROGRESS", "UNATTENDED_ORIGINAL_REQUEST_WINDOW_OPEN", "UNATTENDED_OUTCOME_UNKNOWN", "UNATTENDED_LOOKUP_UNAVAILABLE", "UNATTENDED_SIGNING_UNAVAILABLE", "UNATTENDED_JOURNAL_UNAVAILABLE", "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED", "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"];
      if (!keys(looked, ["contract_version", "scope", "principal_id", "request_id", "action", "outcome", "reason_code", "result", "lookup_request_id"]) ||
          looked.contract_version !== 2 || looked.scope !== unattendedScope || looked.request_id !== options.requestId || looked.principal_id !== profile.identity.principalId || looked.lookup_request_id !== options.lookupId ||
          typeof looked.outcome !== "string" || !["recorded", "unknown", "not_recorded"].includes(looked.outcome) ||
          typeof looked.reason_code !== "string" || !reasons.includes(looked.reason_code)) throw Error("UNATTENDED_LOOKUP_UNAVAILABLE");
      const original = await store.read(`${options.requestId}.checkpoint.json`);
      if (!object(original) || !object(original.request) || !validResult(looked.result, profile.identity, original.request as unknown as UnattendedRequest) && looked.outcome === "recorded") throw Error("UNATTENDED_LOOKUP_UNAVAILABLE");
      let recovery: string | null = null;
      if (options.runRequestId && looked.outcome !== "unknown") {
        const plan = await store.read(`${options.runRequestId}.run.json`);
        if (!validPlan(plan, profile) || !plan.request_ids.includes(options.requestId)) throw Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
        const closed = await store.read(`${options.runRequestId}.closed.json`, true);
        if (closed !== null && !validClosure(closed, options.runRequestId, now())) throw Error("UNATTENDED_JOURNAL_INTEGRITY_REQUIRED");
        const first = await new UnattendedJournal(profile.journal_directory, store).readOriginal(options.runRequestId);
        const receipt = looked.result;
        if (closed === null) {
          let status: string | null = null;
          if (looked.outcome === "recorded" && object(receipt) && receipt.action === "complete_run" && receipt.status === "completed") status = "UNATTENDED_COMPLETED";
          else if (options.requestId === options.runRequestId && looked.outcome === "recorded" && object(receipt) && receipt.action === "begin_run" && receipt.ok === false) status = String(receipt.code);
          else if (options.requestId === options.runRequestId && looked.outcome === "not_recorded") status = "UNATTENDED_NOT_RECORDED";
          else if (object(first) && first.outcome === "recorded" && object(first.result) && first.result.action === "begin_run" && first.result.ok === true && utc(first.result.expires_at) && now() >= Date.parse(first.result.expires_at) + 120000) {
            // Fresh authorized lookup plus a conservative expired-lease horizon.
            // Preserve every old request; this closes only local overlap tracking.
            const armed = await store.read(`${options.lookupId}.armed.json`);
            if (object(armed) && utc(armed.issued_at) && Date.parse(armed.issued_at) >= Date.parse(first.result.expires_at) + 120000) status = "UNATTENDED_LEASE_EXPIRED_AFTER_LOOKUP";
          }
          if (status) {
            const at = now(); await store.publish(`${options.runRequestId}.closed.json`, {contract_version: 2, request_id: options.runRequestId, status,
              closed_at: new Date(at).toISOString(), not_before: new Date(at + 60000).toISOString()}); recovery = status;
          }
        } else recovery = "UNATTENDED_LOCAL_RUN_ALREADY_CLOSED";
      }
      return {status: looked.outcome === "recorded" ? "UNATTENDED_LOOKUP_RECORDED" : looked.outcome === "not_recorded" ? "UNATTENDED_ORIGINAL_REQUEST_NOT_RECORDED" : "UNATTENDED_LOOKUP_UNKNOWN", ...boundary, lookup_request_id: options.lookupId, outcome: looked.outcome,
        reason_code: looked.reason_code, local_recovery: recovery, evidence: "original_request_lookup_only", automatic_replay: false};
    }
    const requestIds = [options.requestId, ...Array.from({length: options.maxEvents + 3}, () => (dependencies.uuid ?? randomUUID)())];
    const plan: Plan = {contract_version: 2, scope: unattendedScope, principal_id: profile.identity.principalId, key_sha256: profile.identity.keySha256,
      request_id: options.requestId, created_at: new Date(now()).toISOString(), request_ids: requestIds, max_events: options.maxEvents};
    if (!validPlan(plan, profile)) throw Error("UNATTENDED_ARGUMENTS_INVALID");
    await store.publish(`${options.requestId}.run.json`, plan); await claim(store, plan, now());
    await permit();
    const deadline = Date.parse(plan.created_at) + 60_000;
    transport = (dependencies.transport ?? unattendedStdio)(options.profilePath); await transport.initialize();
    let ordinal = 0, run: {run_id: string; fence_version: number} | null = null, lease = Infinity;
    const call = async (action: UnattendedRequest["action"], payload: Json) => {
      await permit();
      const next = requestIds[ordinal];
      if (!next || now() >= deadline || now() + 5000 >= lease) throw Error("UNATTENDED_RUN_DEADLINE_OR_LEASE_EXPIRED");
      pending = next; ordinal++;
      const request: UnattendedRequest = {action, requestId: pending, payload};
      const result = structured(await transport!.call(`collect_unattended_${action}`, {request_id: pending, ...payload}));
      if (!keys(result, ["contract_version", "scope", "principal_id", "request_id", "action", "outcome", "reason_code", "result", "lookup_request_id"]) || result.contract_version !== 2 || result.scope !== unattendedScope || result.request_id !== pending || result.principal_id !== profile.identity.principalId || result.action !== action ||
          result.outcome !== "recorded" || result.reason_code !== "UNATTENDED_RESULT_RECORDED" || result.lookup_request_id !== null ||
          !validResult(result.result, profile.identity, request)) throw Error("UNATTENDED_OUTCOME_UNKNOWN");
      return result.result;
    };
    const begin = await call("begin_run", {});
    if (begin.ok === false) {
      const status = String(begin.code), at = now();
      await store.publish(`${options.requestId}.closed.json`, {contract_version: 2, request_id: options.requestId, status,
        closed_at: new Date(at).toISOString(), not_before: new Date(at + 60000).toISOString()});
      return {status, ...boundary, local_backoff_seconds: 60};
    }
    run = {run_id: String(begin.run_id), fence_version: Number(begin.fence_version)}; lease = Date.parse(String(begin.expires_at));
    const events = await call("list_events", {...run, limit: options.maxEvents});
    for (const event of events.events as Json[]) await call("ensure_receipt", {...run, event_id: event.event_id, expected_source_version: event.source_version});
    await call("reconcile_backlog", {...run, limit: options.maxEvents});
    const complete = await call("complete_run", run);
    if (now() >= lease || Date.parse(String(complete.observed_at)) >= lease) throw Error("UNATTENDED_OUTCOME_UNKNOWN");
    const at = now();
    await store.publish(`${options.requestId}.closed.json`, {contract_version: 2, request_id: options.requestId, status: "UNATTENDED_COMPLETED",
      closed_at: new Date(at).toISOString(), not_before: new Date(at + 1000).toISOString()});
    return {status: "UNATTENDED_COMPLETED", ...boundary, run_id: run.run_id, mode: begin.mode, handled_count: complete.handled_count,
      deferred_count: complete.deferred_count, action_count: complete.action_count, recorded_sms_segments: complete.sms_segments,
      more_events: events.more, carrier_delivery_verified: false};
  } catch (error) {
    const allowed = new Set(["UNATTENDED_ARGUMENTS_INVALID", "UNATTENDED_PROFILE_UNAVAILABLE", "UNATTENDED_JOURNAL_UNAVAILABLE", "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED",
      "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED", "UNATTENDED_LOCAL_OVERLAP_RECONCILIATION_REQUIRED", "UNATTENDED_LOCAL_BACKOFF_ACTIVE", "UNATTENDED_HISTORY_MAINTENANCE_REQUIRED",
      "UNATTENDED_RUN_DEADLINE_OR_LEASE_EXPIRED", "UNATTENDED_LOOKUP_UNAVAILABLE"]);
    return {status: error instanceof Error && allowed.has(error.message) ? error.message : "UNATTENDED_OUTCOME_UNKNOWN", ...boundary,
      unresolved_request_id: pending, reconciliation_required: true, automatic_replay: false};
  } finally {await transport?.close().catch(() => {});}
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await runUnattended(process.argv.slice(2)); console.log(JSON.stringify(result));
  if (!["UNATTENDED_COMPLETED", "UNATTENDED_LOOKUP_RECORDED", "UNATTENDED_LOCAL_RUN_CLOSED", "UNATTENDED_NOT_STARTED"].includes(String(result.status))) process.exitCode = 2;
}
