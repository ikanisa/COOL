import * as fs from "node:fs/promises";
import {join} from "node:path";
import {createHash} from "node:crypto";
import {keys, object, utc, uuid, type Json} from "./unattended_contract.ts";
import type {Deployment} from "./unattended_deployment.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {validHistoryPlan, validHistoryClosure, historyHead, type HistoryPlan} from "./unattended_history.ts";
import {retainedPolicy, retentionPolicySha256} from "./unattended_retained.ts";
import {validStarted, validTerminal, schedulerStorageLimits} from "./unattended_scheduler_storage.ts";
import {validOperation} from "./unattended_scheduler_control.ts";
import {validUnattendedBasename} from "./unattended_store_names.ts";

export {retentionPolicySha256} from "./unattended_retained.ts";
const INTEGRITY = "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED";
const encoded = (value: unknown) => JSON.stringify(value) + "\n";
const sha = (value: unknown) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
export interface RetentionResult {status: "retained" | "disabled" | "deferred"; files_archived: number; bytes_archived: number; business_actions: 0}
export interface RetentionDependencies {store?: (directory: string) => UnattendedStore}
async function names(directory: string, maximum: number) {
  const result: string[] = [], stream = await fs.opendir(directory);
  try {for await (const entry of stream) {if (result.length >= maximum || !entry.isFile() || !validUnattendedBasename(entry.name)) throw Error(INTEGRITY); result.push(entry.name);}}
  finally {await stream.close().catch(() => {});}
  return result.sort();
}
/** Preparation explicitly pins the module and this finite policy. Maintenance
 * is local evidence work, never signer, transport, daemon, or run authority. */
export async function maintainSchedulerEvidence(deployment: Deployment, now = Date.now(), dependencies: RetentionDependencies = {}): Promise<RetentionResult> {
  if (deployment.manifest.retention_policy_sha256 !== retentionPolicySha256) return {status: "disabled", files_archived: 0, bytes_archived: 0, business_actions: 0};
  if (!Number.isSafeInteger(now) || now < retainedPolicy.preserve_recent_ms) throw Error(INTEGRITY);
  const cutoff = now - retainedPolicy.preserve_recent_ms;
  let files = 0, bytes = 0, deferred = false;
  const retain = async (store: UnattendedStore, values: Map<string, unknown>) => {
    const groupBytes = [...values.values()].reduce<number>((sum, value) => sum + Buffer.byteLength(encoded(value)), 0);
    if (files + values.size > retainedPolicy.maintenance_files || bytes + groupBytes > retainedPolicy.maintenance_bytes) {deferred = true; return false;}
    // Exact records are revalidated by Store.archive immediately before prune.
    for (const [name, value] of values) {await store.archive(name, value); files++; bytes += Buffer.byteLength(encoded(value));}
    return true;
  };
  const makeStore = dependencies.store ?? (directory => new UnattendedStore(directory));
  const diagnostics = makeStore(join(deployment.directory, "diagnostics"));
  const diagnosticNames = await names(diagnostics.directory, schedulerStorageLimits.diagnostics.files);
  const starts: {id: string; value: unknown; at: number}[] = [];
  const diagnosticIds = [...new Set(diagnosticNames.map(name => name.slice(0, 36)))];
  for (const id of diagnosticIds) {
    const value = await diagnostics.read(`${id}.run.json`);
    if (!validStarted(value, deployment, id)) throw Error(INTEGRITY);
    starts.push({id, value, at: Date.parse(value.started_at)});
  }
  starts.sort((a, b) => b.at - a.at || b.id.localeCompare(a.id));
  const definite = new Set(["SCHEDULER_BATCH_COMPLETED", "SCHEDULER_BATCH_DEFERRED", "SCHEDULER_BACKOFF", "SCHEDULER_ORIGINAL_RECONCILED",
    "SCHEDULER_UNSTARTED_RUN_CLOSED", "SCHEDULER_LOCAL_INACTIVE", "SCHEDULER_IDENTITY_UNAVAILABLE", "SCHEDULER_STORAGE_ADMISSION_REQUIRED"]);
  for (const start of starts.slice(retainedPolicy.preserve_latest_diagnostics).reverse()) {
    const end = await diagnostics.read(`${start.id}.closed.json`, true);
    if (end === null || !validStarted(start.value, deployment, start.id) || !validTerminal(end, start.value)) {if (end !== null) throw Error(INTEGRITY); continue;}
    if (start.at > cutoff || Date.parse(end.observed_at) > cutoff || !definite.has(end.status) || end.business_handled === null) continue;
    if (!await retain(diagnostics, new Map<string, unknown>([[`${start.id}.closed.json`, end], [`${start.id}.run.json`, start.value]]))) break;
  }
  const control = makeStore(join(deployment.directory, "control"));
  const controlNames = await names(control.directory, schedulerStorageLimits.control.files);
  const lookups: {name: string; value: Json; at: number}[] = [];
  for (const name of controlNames.filter(name => name.endsWith(".lookup.json"))) {
    const value = await control.read(name);
    if (!keys(value, ["contract_version", "request_id", "original_request_id", "checkpoint_sha256", "observed_at", "status", "host"]) ||
      value.contract_version !== 1 || !uuid(value.request_id) || name !== `${value.request_id}.lookup.json` || !uuid(value.original_request_id) || !utc(value.observed_at) ||
      typeof value.status !== "string" || !["SCHEDULER_ACTIVATION_OBSERVED", "SCHEDULER_DISABLE_OBSERVED", "SCHEDULER_OPERATION_UNKNOWN"].includes(value.status)) throw Error(INTEGRITY);
    const original = await control.read(`${value.original_request_id}.checkpoint.json`);
    if (!validOperation(original, deployment, value.original_request_id) || value.checkpoint_sha256 !== sha(original) ||
      !keys(value.host, ["state", "loaded", "disabled", "process_running"]) || typeof value.host.state !== "string" ||
      !["absent", "loaded", "running", "disabled", "unknown", "conflicting"].includes(value.host.state) ||
      [value.host.loaded, value.host.disabled, value.host.process_running].some(flag => flag !== null && typeof flag !== "boolean") ||
      value.status === "SCHEDULER_ACTIVATION_OBSERVED" && (value.host.loaded !== true || value.host.disabled !== false) ||
      value.status === "SCHEDULER_DISABLE_OBSERVED" && (value.host.loaded !== false || value.host.disabled !== true)) throw Error(INTEGRITY);
    lookups.push({name, value, at: Date.parse(value.observed_at)});
  }
  lookups.sort((a, b) => b.at - a.at || b.name.localeCompare(a.name));
  const latestByOriginal = new Set<string>();
  for (const lookup of lookups) {
    const original = String(lookup.value.original_request_id);
    if (!latestByOriginal.has(original)) {latestByOriginal.add(original); continue;}
    if (lookup.at > cutoff || lookup.value.status === "SCHEDULER_OPERATION_UNKNOWN") continue;
    if (!await retain(control, new Map([[lookup.name, lookup.value]]))) break;
  }
  const store = makeStore(deployment.manifest.journal_directory), journal = new UnattendedJournal(store.directory, store);
  const journalNames = await names(store.directory, schedulerStorageLimits.journal.files);
  const identity = deployment.manifest.identity, head = await historyHead(store, identity, now);
  const plans: HistoryPlan[] = [], pinned = new Set<string>();
  const planIds = [...new Set(journalNames.filter(name => /\.(run|closed|step)\.json$/.test(name)).map(name => name.slice(0, 36)))];
  for (const id of planIds) {
    const plan = await store.read(`${id}.run.json`);
    if (!validHistoryPlan(plan, identity) || id !== plan.request_id) throw Error(INTEGRITY);
    plans.push(plan);
  }
  // The actual current tail and the unindexed recent history stay hot. Older
  // source records remain available through verified cold reads to historyHead.
  plans.sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at) || b.request_id.localeCompare(a.request_id));
  for (const plan of plans.slice(0, 129)) for (const id of plan.request_ids) pinned.add(id);
  if (head) pinned.add(head);
  const closedGroups = new Set<string>();
  const requestGroup = async (id: string, group: Map<string, unknown>): Promise<boolean> => {
    const checkpoint = await store.read(`${id}.checkpoint.json`, true);
    if (checkpoint === null) return true;
    if (!object(checkpoint) || !object(checkpoint.request) || checkpoint.request.action === "reconcile_request") return false;
    const result = await journal.readOriginal(id);
    if (result.outcome !== "recorded") return false;
    for (const suffix of ["checkpoint", "armed", "outcome", "lookup"]) {
      const name = `${id}.${suffix}.json`, value = await store.read(name, true); if (value !== null) group.set(name, value);
    }
    if (result.lookup_request_id) {
      for (const suffix of ["checkpoint", "armed", "lookup", "outcome"]) {
        const name = `${result.lookup_request_id}.${suffix}.json`, value = await store.read(name, true); if (value !== null) group.set(name, value);
      }
    }
    return true;
  };
  for (const plan of plans.slice(129).reverse()) {
    const closed = await store.read(`${plan.request_id}.closed.json`, true), step = await store.read(`${plan.request_id}.step.json`, true);
    if (closed === null) {for (const id of plan.request_ids) pinned.add(id); continue;}
    if (!validHistoryClosure(closed, plan.request_id, now) || !keys(step, ["contract_version", "previous_request_id", "request_id"]) ||
      step.contract_version !== 2 || step.previous_request_id !== plan.request_id || !uuid(step.request_id)) throw Error(INTEGRITY);
    if (Date.parse(String(closed.closed_at)) > cutoff || Date.parse(plan.created_at) > cutoff) continue;
    const group = new Map<string, unknown>();
    let complete = true, started = false, begin: Json | null = null, completed = false;
    for (const id of plan.request_ids) {
      if (!await requestGroup(id, group)) complete = false;
      const checkpoint = group.get(`${id}.checkpoint.json`);
      if (object(checkpoint) && object(checkpoint.request)) {
        started = true;
        const observed = await journal.readOriginal(id);
        if (observed.outcome === "recorded" && object(observed.result)) {
          if (checkpoint.request.action === "begin_run") begin = observed.result;
          if (checkpoint.request.action === "complete_run" && observed.result.status === "completed") completed = true;
        }
      }
    }
    if (closed.status === "UNATTENDED_COMPLETED" && (!completed || begin?.ok !== true) ||
      closed.status === "UNATTENDED_NOT_STARTED" && (started || Date.parse(String(closed.closed_at)) < Date.parse(plan.created_at) + 120_000) ||
      ["OPERATIONS_PAUSED", "RUN_BUSY", "PRINCIPAL_SCOPE_UNCONFIGURED"].includes(String(closed.status)) && (begin?.ok !== false || begin.code !== closed.status) ||
      closed.status === "UNATTENDED_LEASE_EXPIRED_AFTER_LOOKUP" && (begin?.ok !== true || !utc(begin.expires_at) || Date.parse(String(closed.closed_at)) < Date.parse(begin.expires_at) + 120_000)) complete = false;
    if (!complete) {for (const id of plan.request_ids) pinned.add(id); continue;}
    group.set(`${plan.request_id}.closed.json`, closed); group.set(`${plan.request_id}.step.json`, step); group.set(`${plan.request_id}.run.json`, plan);
    for (const id of plan.request_ids) closedGroups.add(id);
    if (!await retain(store, group)) break;
  }
  // Recorded standalone actions are also eligible. Never strip a child from
  // a pinned or incompletely reconciled run merely because that child succeeded.
  for (const plan of plans) for (const id of plan.request_ids) if (!closedGroups.has(id)) pinned.add(id);
  for (const name of journalNames.filter(name => name.endsWith(".checkpoint.json"))) {
    const id = name.slice(0, -16); if (pinned.has(id) || closedGroups.has(id)) continue;
    const checkpoint = await store.read(name);
    if (!object(checkpoint) || !utc(checkpoint.created_at) || Date.parse(checkpoint.created_at) > cutoff ||
      !object(checkpoint.request) || checkpoint.request.action === "reconcile_request") continue;
    const group = new Map<string, unknown>(); if (await requestGroup(id, group) && !await retain(store, group)) break;
  }
  const segments = journalNames.filter(name => /\.history-[0-9]{10}\.json$/.test(name)).sort();
  for (const name of segments.slice(0, -2)) {const value = await store.read(name); if (!await retain(store, new Map([[name, value]]))) break;}
  return {status: deferred ? "deferred" : "retained", files_archived: files, bytes_archived: bytes, business_actions: 0};
}
