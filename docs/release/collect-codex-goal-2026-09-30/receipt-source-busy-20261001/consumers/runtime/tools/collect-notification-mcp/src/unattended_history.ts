import {createHash} from "node:crypto";
import {hash, integer, keys, unattendedScope, utc, uuid, type Json} from "./unattended_contract.ts";
import {UnattendedStore} from "./unattended_store.ts";

export interface HistoryIdentity {principalId: string; keySha256: string}
export interface HistoryPlan {contract_version: 2; scope: string; principal_id: string; key_sha256: string;
  request_id: string; created_at: string; request_ids: string[]; max_events: number}
export const historySegmentSize = 128;
// Bounded lookup and bounded migration work per invocation. An old unindexed
// archive is advanced durably in chunks; reaching this limit never enables HTTP.
const MAX_SEQUENCE = 1_000_000_000, MAX_TRANSITIONS = historySegmentSize * 32;
const INTEGRITY = "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED";
const MAINTENANCE = "UNATTENDED_HISTORY_MAINTENANCE_REQUIRED";
const digest = (value: unknown) => createHash("sha256").update(JSON.stringify(value) + "\n").digest("hex");
interface Entry {request_id: string; next_request_id: string; run_sha256: string; step_sha256: string; closed_sha256: string}
interface Segment {contract_version: 2; kind: "closed_claim_segment"; scope: string; principal_id: string; key_sha256: string;
  root_request_id: string; root_sha256: string; root_run_sha256: string; sequence: number; previous_sha256: string | null;
  start_request_id: string; head_request_id: string; head_run_sha256: string; entries: Entry[]}

export function validHistoryPlan(value: unknown, identity: HistoryIdentity): value is HistoryPlan {
  return keys(value, ["contract_version", "scope", "principal_id", "key_sha256", "request_id", "created_at", "request_ids", "max_events"]) &&
    value.contract_version === 2 && value.scope === unattendedScope && value.principal_id === identity.principalId && value.key_sha256 === identity.keySha256 &&
    uuid(value.request_id) && utc(value.created_at) && integer(value.max_events, 1, 10) && Array.isArray(value.request_ids) &&
    value.request_ids.length === value.max_events + 4 && value.request_ids[0] === value.request_id &&
    value.request_ids.every(uuid) && new Set(value.request_ids).size === value.request_ids.length;
}
export function validHistoryClosure(value: unknown, requestId: string, now: number): value is Json {
  return keys(value, ["contract_version", "request_id", "status", "closed_at", "not_before"]) && value.contract_version === 2 && value.request_id === requestId &&
    typeof value.status === "string" && ["UNATTENDED_COMPLETED", "OPERATIONS_PAUSED", "RUN_BUSY", "PRINCIPAL_SCOPE_UNCONFIGURED", "UNATTENDED_NOT_RECORDED", "UNATTENDED_LEASE_EXPIRED_AFTER_LOOKUP", "UNATTENDED_NOT_STARTED"].includes(value.status) &&
    utc(value.closed_at) && utc(value.not_before) && Date.parse(value.not_before) >= Date.parse(value.closed_at) && Date.parse(value.closed_at) <= now;
}
export function historyName(identity: HistoryIdentity, sequence: number) {
  if (!uuid(identity.principalId) || !hash(identity.keySha256) || !integer(sequence, 1, MAX_SEQUENCE)) throw Error(INTEGRITY);
  return `principal-${identity.principalId}.history-${String(sequence).padStart(10, "0")}.json`;
}
function validStep(value: unknown, from: string): value is {contract_version: 2; previous_request_id: string; request_id: string} {
  return keys(value, ["contract_version", "previous_request_id", "request_id"]) && value.contract_version === 2 &&
    value.previous_request_id === from && uuid(value.request_id) && value.request_id !== from;
}
function validSegment(value: unknown, identity: HistoryIdentity, root: Json, rootRun: HistoryPlan, sequence: number): value is Segment {
  if (!keys(value, ["contract_version", "kind", "scope", "principal_id", "key_sha256", "root_request_id", "root_sha256", "root_run_sha256", "sequence", "previous_sha256", "start_request_id", "head_request_id", "head_run_sha256", "entries"]) ||
      value.contract_version !== 2 || value.kind !== "closed_claim_segment" || value.scope !== unattendedScope || value.principal_id !== identity.principalId || value.key_sha256 !== identity.keySha256 ||
      value.root_request_id !== root.request_id || value.root_sha256 !== digest(root) || value.root_run_sha256 !== digest(rootRun) || value.sequence !== sequence ||
      (sequence === 1 ? value.previous_sha256 !== null || value.start_request_id !== root.request_id : !hash(value.previous_sha256)) ||
      !uuid(value.start_request_id) || !uuid(value.head_request_id) || !hash(value.head_run_sha256) || !Array.isArray(value.entries) || value.entries.length !== historySegmentSize) return false;
  let current = value.start_request_id;
  const seen = new Set<string>([current]);
  for (const entry of value.entries) {
    if (!keys(entry, ["request_id", "next_request_id", "run_sha256", "step_sha256", "closed_sha256"]) || entry.request_id !== current || !uuid(entry.next_request_id) ||
        seen.has(entry.next_request_id) || !hash(entry.run_sha256) || !hash(entry.step_sha256) || !hash(entry.closed_sha256)) return false;
    seen.add(entry.next_request_id); current = entry.next_request_id;
  }
  return value.head_request_id === current;
}
async function readPlan(store: UnattendedStore, identity: HistoryIdentity, id: string): Promise<HistoryPlan> {
  const value = await store.read(`${id}.run.json`);
  if (!validHistoryPlan(value, identity) || value.request_id !== id) throw Error(INTEGRITY);
  return value;
}
async function transition(store: UnattendedStore, identity: HistoryIdentity, plan: HistoryPlan, now: number): Promise<{entry: Entry; next: HistoryPlan} | null> {
  const step = await store.read(`${plan.request_id}.step.json`, true);
  if (step === null) return null;
  if (!validStep(step, plan.request_id)) throw Error(INTEGRITY);
  const closed = await store.read(`${plan.request_id}.closed.json`), next = await readPlan(store, identity, step.request_id);
  // Plans are published before claim acquisition and may be prepared while an
  // earlier run is finishing. Their creation time is not a claim/backoff time.
  if (!validHistoryClosure(closed, plan.request_id, now) || Date.parse(String(closed.closed_at)) < Date.parse(plan.created_at) ||
      Date.parse(next.created_at) > now) throw Error(INTEGRITY);
  return {entry: {request_id: plan.request_id, next_request_id: step.request_id, run_sha256: digest(plan), step_sha256: digest(step), closed_sha256: digest(closed)}, next};
}

/** Resolve the actual append-only claim tail, using checked immutable segment
 * proofs to skip older history. No run/request/outcome is removed or rewritten.
 * Indexes certify closed transitions, never completion or delivery of the tail.
 * The selected segment's source records and predecessor digest are reread; older
 * segments remain historical captured hashes, not a full archive scan per tick. */
export async function historyHead(store: UnattendedStore, identity: HistoryIdentity, now: number): Promise<string | null> {
  if (!uuid(identity.principalId) || !hash(identity.keySha256) || !integer(now, 0, 253402300799999)) throw Error(INTEGRITY);
  const root = await store.read(`principal-${identity.principalId}.lock.json`, true);
  if (root === null) return null;
  if (!keys(root, ["contract_version", "scope", "principal_id", "key_sha256", "request_id"]) || root.contract_version !== 2 ||
      root.scope !== unattendedScope || root.principal_id !== identity.principalId || root.key_sha256 !== identity.keySha256 || !uuid(root.request_id)) throw Error(INTEGRITY);
  const rootRun = await readPlan(store, identity, root.request_id), cache = new Map<number, Segment | null>();
  if (Date.parse(rootRun.created_at) > now) throw Error(INTEGRITY);
  const indexed = async (sequence: number): Promise<Segment | null> => {
    if (cache.has(sequence)) return cache.get(sequence)!;
    const value = await store.read(historyName(identity, sequence), true);
    if (value !== null && !validSegment(value, identity, root, rootRun, sequence)) throw Error(INTEGRITY);
    cache.set(sequence, value as Segment | null); return value as Segment | null;
  };
  // Publication is contiguous: n+1 requires a read-back accepted n. Concurrent
  // publication may leave an older starting point; the bounded tail walk below
  // catches up without treating any absent index as an absent business request.
  let lower = 0, upper = 1;
  while (await indexed(upper) !== null) {
    lower = upper;
    if (upper === MAX_SEQUENCE) throw Error(MAINTENANCE);
    upper = Math.min(upper * 2, MAX_SEQUENCE);
  }
  while (upper - lower > 1) {
    const mid = Math.floor((lower + upper) / 2);
    if (await indexed(mid) === null) upper = mid; else lower = mid;
  }
  // A hole followed immediately by a published segment cannot arise from the
  // ordered publisher. Refuse observed deletion/replacement rather than treating
  // that index gap as permission to reconstruct a different current head.
  if (upper < MAX_SEQUENCE && await indexed(upper + 1) !== null) {
    // Another publisher may have filled our earlier optional-read miss. Reread
    // the gap once before classifying it as observed corruption.
    cache.delete(upper);
    if (await indexed(upper) === null) throw Error(INTEGRITY);
  }
  let previous = lower === 0 ? null : await indexed(lower), plan = rootRun;
  if (previous !== null) {
    if (lower > 1) {
      const predecessor = await indexed(lower - 1);
      if (predecessor === null || previous.previous_sha256 !== digest(predecessor) || previous.start_request_id !== predecessor.head_request_id ||
          previous.entries[0]!.run_sha256 !== predecessor.head_run_sha256) throw Error(INTEGRITY);
    } else if (previous.entries[0]!.run_sha256 !== digest(rootRun)) throw Error(INTEGRITY);
    plan = await readPlan(store, identity, previous.start_request_id);
    for (const entry of previous.entries) {
      const checked = await transition(store, identity, plan, now);
      if (checked === null || digest(checked.entry) !== digest(entry)) throw Error(INTEGRITY);
      plan = checked.next;
    }
    if (plan.request_id !== previous.head_request_id || digest(plan) !== previous.head_run_sha256) throw Error(INTEGRITY);
  }
  const seen = new Set<string>([plan.request_id]); let entries: Entry[] = [], start = plan.request_id;
  for (let work = 0; work < MAX_TRANSITIONS; work++) {
    const checked = await transition(store, identity, plan, now);
    if (checked === null) return plan.request_id;
    if (seen.has(checked.next.request_id)) throw Error(INTEGRITY);
    seen.add(checked.next.request_id); entries.push(checked.entry); plan = checked.next;
    if (entries.length === historySegmentSize) {
      const sequence = lower + 1;
      if (sequence > MAX_SEQUENCE) throw Error(MAINTENANCE);
      const segment: Segment = {contract_version: 2, kind: "closed_claim_segment", scope: unattendedScope, principal_id: identity.principalId, key_sha256: identity.keySha256,
        root_request_id: root.request_id, root_sha256: digest(root), root_run_sha256: digest(rootRun), sequence, previous_sha256: previous === null ? null : digest(previous),
        start_request_id: start, head_request_id: plan.request_id, head_run_sha256: digest(plan), entries};
      const name = historyName(identity, sequence);
      try {await store.publish(name, segment);}
      catch (error) {if (!(error instanceof Error) || error.message !== "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED") throw error;}
      const accepted = await store.read(name);
      if (!validSegment(accepted, identity, root, rootRun, sequence) || digest(accepted) !== digest(segment)) throw Error(INTEGRITY);
      // Do not accept a head whose source changed during index publication.
      if (digest(await readPlan(store, identity, plan.request_id)) !== segment.head_run_sha256) throw Error(INTEGRITY);
      previous = segment; lower = sequence; start = plan.request_id; entries = [];
    }
  }
  throw Error(MAINTENANCE);
}
