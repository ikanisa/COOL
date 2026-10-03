import * as fs from "node:fs/promises";
import type {Stats, Dir} from "node:fs";
import {randomUUID} from "node:crypto";
import {join} from "node:path";
import {schedulerDirectory, schedulerFile, type Deployment} from "./unattended_deployment.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {keys, utc, uuid, hash, type Json} from "./unattended_contract.ts";
import {sha256} from "./unattended_enrollment_contract.ts";

/** Admission ceilings, not an archival policy or a free-space guarantee.
 * Reserve covers a maximum 10-event tick plus bounded history publication.
 * Urgent local disable deliberately does not depend on this scanner. */
export const schedulerStorageLimits = Object.freeze({
  control: {files: 512, bytes: 1_048_576, reserveFiles: 8, reserveBytes: 131_072, recordBytes: 65_536},
  journal: {files: 32_768, bytes: 67_108_864, reserveFiles: 256, reserveBytes: 16_777_216, recordBytes: 65_536},
  diagnostics: {files: 32_768, bytes: 16_777_216, reserveFiles: 4, reserveBytes: 8_192, recordBytes: 2_048},
  minimumFreeBytes: 33_554_432,
});
interface StorageIO extends Pick<typeof fs, "opendir" | "lstat"> {
  statfs(path: string): Promise<{bavail: number; bsize: number}>;
}
export interface StorageDependencies {io?: StorageIO; timeoutMs?: number}
interface Usage {state: "available" | "exhausted" | "unavailable"; entries_counted: number | null; bytes_counted: number | null; complete: boolean}
interface Scanned {usage: Usage; names: string[]}
const unavailable = (): Usage => ({state: "unavailable", entries_counted: null, bytes_counted: null, complete: false});
const unchanged = (a: Stats, b: Stats) => a.dev === b.dev && a.ino === b.ino && a.uid === b.uid && a.mode === b.mode &&
  a.nlink === b.nlink && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;
async function scan(directory: string, limit: typeof schedulerStorageLimits.control, io: StorageIO): Promise<Scanned> {
  let stream: Dir | undefined;
  try {
    await schedulerDirectory(directory); const before = await io.lstat(directory);
    stream = await io.opendir(directory); let count = 0, bytes = 0; const names: string[] = [];
    for await (const entry of stream) {
      count++;
      if (count > limit.files) return {usage: {state: "exhausted", entries_counted: count, bytes_counted: bytes, complete: false}, names: []};
      const path = join(directory, entry.name), info = await io.lstat(path);
      if (!info.isFile() || info.isSymbolicLink() || info.uid !== process.getuid?.() || (info.mode & 0o7777) !== 0o600 || info.nlink !== 1 ||
          !Number.isSafeInteger(info.size) || info.size < 0 || info.size > limit.recordBytes || !unchanged(info, await io.lstat(path))) throw Error();
      bytes += info.size;
      if (bytes > limit.bytes) return {usage: {state: "exhausted", entries_counted: count, bytes_counted: bytes, complete: false}, names: []};
      names.push(entry.name);
    }
    if (!unchanged(before, await io.lstat(directory))) throw Error();
    return {usage: {state: limit.files - count >= limit.reserveFiles && limit.bytes - bytes >= limit.reserveBytes ? "available" : "exhausted",
      entries_counted: count, bytes_counted: bytes, complete: true}, names};
  } catch {return {usage: unavailable(), names: []};}
  finally {await stream?.close().catch(() => {});}
}
const terminalStatuses = new Set(["SCHEDULER_BATCH_COMPLETED", "SCHEDULER_BATCH_DEFERRED", "SCHEDULER_BACKOFF", "SCHEDULER_ORIGINAL_RECONCILED",
  "SCHEDULER_UNSTARTED_RUN_CLOSED", "SCHEDULER_RECONCILIATION_PENDING", "SCHEDULER_ARGUMENTS_INVALID", "SCHEDULER_IDENTITY_UNAVAILABLE",
  "SCHEDULER_JOURNAL_INTEGRITY_REQUIRED", "SCHEDULER_HISTORY_MAINTENANCE_REQUIRED", "SCHEDULER_RUN_UNVERIFIED", "SCHEDULER_UNAVAILABLE",
  "UNATTENDED_PROFILE_UNAVAILABLE", "UNATTENDED_JOURNAL_UNAVAILABLE", "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED", "TICK_OUTCOME_UNCONFIRMED",
  "SCHEDULER_DEPLOYMENT_UNVERIFIED", "SCHEDULER_EXECUTION_BINDING_REQUIRED", "SCHEDULER_LOCAL_INACTIVE", "SCHEDULER_LOCAL_INTEGRITY_REQUIRED",
  "SCHEDULER_STORAGE_ADMISSION_REQUIRED", "SCHEDULER_DIAGNOSTICS_UNAVAILABLE"]);
interface Started {contract_version: 1; kind: "scheduler_tick_diagnostic"; preparation_sha256: string; principal_id: string;
  tick_id: string; started_at: string; observed_at: string; phase: "started_unconfirmed"; status: "TICK_STARTED_UNCONFIRMED"}
interface Terminal extends Omit<Started, "phase" | "status"> {phase: "terminal"; status: string; started_sha256: string; request_id: string | null; business_handled: boolean | null}
const startedKeys = ["contract_version", "kind", "preparation_sha256", "principal_id", "tick_id", "started_at", "observed_at", "phase", "status"];
function validStarted(value: unknown, deployment: Deployment, id: string): value is Started {
  return keys(value, startedKeys) && value.contract_version === 1 && value.kind === "scheduler_tick_diagnostic" && value.preparation_sha256 === deployment.manifestSha &&
    value.principal_id === deployment.manifest.identity.principalId && value.tick_id === id && uuid(id) && utc(value.started_at) && value.observed_at === value.started_at &&
    value.phase === "started_unconfirmed" && value.status === "TICK_STARTED_UNCONFIRMED";
}
function validTerminal(value: unknown, started: Started): value is Terminal {
  return keys(value, [...startedKeys, "started_sha256", "request_id", "business_handled"]) && value.contract_version === 1 && value.kind === started.kind &&
    value.preparation_sha256 === started.preparation_sha256 && value.principal_id === started.principal_id && value.tick_id === started.tick_id &&
    value.started_at === started.started_at && utc(value.observed_at) && Date.parse(value.observed_at) >= Date.parse(started.started_at) &&
    value.phase === "terminal" && typeof value.status === "string" && terminalStatuses.has(value.status) && hash(value.started_sha256) &&
    value.started_sha256 === sha256(JSON.stringify(started)) && (value.request_id === null || uuid(value.request_id)) &&
    (value.business_handled === null || typeof value.business_handled === "boolean");
}
const diagnosticsDirectory = (deployment: Deployment) => join(deployment.directory, "diagnostics");
export async function beginSchedulerTickDiagnostic(deployment: Deployment, now = Date.now()): Promise<Started> {
  const time = new Date(now).toISOString(); if (!utc(time)) throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");
  const started: Started = {contract_version: 1, kind: "scheduler_tick_diagnostic", preparation_sha256: deployment.manifestSha,
    principal_id: deployment.manifest.identity.principalId, tick_id: randomUUID(), started_at: time, observed_at: time,
    phase: "started_unconfirmed", status: "TICK_STARTED_UNCONFIRMED"};
  const store = new UnattendedStore(diagnosticsDirectory(deployment));
  await store.publish(`${started.tick_id}.run.json`, started);
  if (JSON.stringify(await store.read(`${started.tick_id}.run.json`)) !== JSON.stringify(started)) throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");
  return started;
}
export function finiteSchedulerTickProjection(result: Json): {status: string; request_id: string | null; business_handled: boolean | null} {
  return {status: typeof result.status === "string" && terminalStatuses.has(result.status) ? result.status : "TICK_OUTCOME_UNCONFIRMED",
    request_id: uuid(result.request_id) ? result.request_id : null, business_handled: typeof result.business_handled === "boolean" ? result.business_handled : null};
}
export async function endSchedulerTickDiagnostic(deployment: Deployment, started: Started, result: Json, now = Date.now()) {
  if (!validStarted(started, deployment, started.tick_id)) throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");
  const terminal: Terminal = {...started, observed_at: new Date(now).toISOString(), phase: "terminal", ...finiteSchedulerTickProjection(result),
    started_sha256: sha256(JSON.stringify(started))};
  if (!validTerminal(terminal, started)) throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");
  const store = new UnattendedStore(diagnosticsDirectory(deployment));
  if (JSON.stringify(await store.read(`${started.tick_id}.run.json`)) !== JSON.stringify(started)) throw Error("SCHEDULER_DIAGNOSTICS_UNAVAILABLE");
  await store.publish(`${started.tick_id}.closed.json`, terminal);
}
async function tickSummary(deployment: Deployment, scanned: Scanned, now: number): Promise<Json> {
  const absent = {state: "absent", freshness: "absent", unconfirmed_count: 0, last: null};
  if (scanned.usage.state === "unavailable" || !scanned.usage.complete) return {state: "unavailable", freshness: "unavailable", unconfirmed_count: null, last: null};
  if (scanned.names.length === 0) return absent;
  try {
    const starts = new Map<string, Started>(), ends = new Map<string, unknown>();
    for (const name of scanned.names) {
      const match = /^([0-9a-f-]{36})\.(run|closed)\.json$/.exec(name); if (!match || !uuid(match[1])) throw Error();
      const raw = await schedulerFile(join(diagnosticsDirectory(deployment), name), 2_048, true);
      const value: unknown = JSON.parse(raw.bytes.toString("utf8")); if (JSON.stringify(value) + "\n" !== raw.bytes.toString("utf8")) throw Error();
      if (match[2] === "run") {if (!validStarted(value, deployment, match[1])) throw Error(); starts.set(match[1], value);} else ends.set(match[1], value);
    }
    let latest: Started | Terminal | null = null, unconfirmed = 0;
    for (const [id, started] of starts) {
      const closed = ends.get(id); if (closed !== undefined && !validTerminal(closed, started)) throw Error();
      const item = closed === undefined ? started : closed as Terminal;
      if (closed === undefined || item.status === "TICK_OUTCOME_UNCONFIRMED") unconfirmed++;
      if (Date.parse(item.observed_at) > now + 10000) throw Error();
      if (!latest || Date.parse(started.started_at) > Date.parse(latest.started_at) || started.started_at === latest.started_at && id > latest.tick_id) latest = item;
      ends.delete(id);
    }
    if (ends.size || !latest) throw Error();
    return {state: unconfirmed ? "unconfirmed" : "terminal", freshness: now < Date.parse(latest.observed_at) + 60000 ? "current" : "stale",
      unconfirmed_count: unconfirmed, last: {tick_id: latest.tick_id, started_at: latest.started_at, observed_at: latest.observed_at,
        phase: latest.phase, status: latest.status, request_id: latest.phase === "terminal" ? latest.request_id : null,
        business_handled: latest.phase === "terminal" ? latest.business_handled : null}};
  } catch {return {state: "unavailable", freshness: "unavailable", unconfirmed_count: null, last: null};}
}
async function inspect(deployment: Deployment, now: number, io: StorageIO): Promise<Json> {
  const [control, journal, diagnostics] = await Promise.all([
    scan(join(deployment.directory, "control"), schedulerStorageLimits.control, io),
    scan(deployment.manifest.journal_directory, schedulerStorageLimits.journal, io),
    scan(diagnosticsDirectory(deployment), schedulerStorageLimits.diagnostics, io),
  ]);
  let free: number | null = null;
  try {
    const rows = await Promise.all([io.statfs(deployment.directory), io.statfs(deployment.manifest.journal_directory)]);
    const available = rows.map(value => value.bavail * value.bsize);
    if (available.some(value => !Number.isSafeInteger(value) || value < 0)) throw Error(); free = Math.min(...available);
  } catch { /* Unknown capacity cannot admit a new action. */ }
  const tick = await tickSummary(deployment, diagnostics, now);
  const usages = [control.usage, journal.usage, diagnostics.usage];
  const state = free === null || tick.state === "unavailable" || usages.some(value => value.state === "unavailable") ? "unavailable" :
    free < schedulerStorageLimits.minimumFreeBytes || usages.some(value => value.state === "exhausted") ? "exhausted" : "available";
  return {contract_version: 1, state, admission_available: state === "available", checked_at: new Date(now).toISOString(),
    sample_valid_until: new Date(now + 60000).toISOString(), control: control.usage, journal: journal.usage, diagnostics: diagnostics.usage,
    minimum_available_bytes: free, last_tick: tick, emergency_disable_bypasses_budget: true, retention_verified: false, restore_verified: false};
}
export async function schedulerStorageDiagnostics(deployment: Deployment, now = Date.now(), dependencies: StorageDependencies = {}): Promise<Json> {
  const unknown = {contract_version: 1, state: "unavailable", admission_available: false, control: unavailable(), journal: unavailable(), diagnostics: unavailable(),
    minimum_available_bytes: null, last_tick: {state: "unavailable", freshness: "unavailable", unconfirmed_count: null, last: null},
    emergency_disable_bypasses_budget: true, retention_verified: false, restore_verified: false};
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeout = dependencies.timeoutMs ?? 10000;
    if (!Number.isSafeInteger(now) || now < 0 || !Number.isSafeInteger(timeout) || timeout < 1 || timeout > 10000) return unknown;
    return await Promise.race([inspect(deployment, now, dependencies.io ?? fs), new Promise<Json>(resolve => {timer = setTimeout(() => resolve(unknown), timeout);})]);
  } catch {return unknown;}
  finally {clearTimeout(timer);}
}
