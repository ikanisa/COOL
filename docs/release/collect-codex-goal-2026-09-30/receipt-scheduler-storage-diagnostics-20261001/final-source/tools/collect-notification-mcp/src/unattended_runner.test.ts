import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp, mkdir, rm, readFile, realpath, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {runUnattended, parseUnattendedOptions} from "./unattended_runner.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {at, id, result, signedFixture} from "./testing/unattended_fixture.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedTransport} from "./unattended_stdio.ts";
import type {Json, UnattendedRequest} from "./unattended_contract.ts";
async function fixture() {
  const parent = await realpath(await mkdtemp(join(tmpdir(), "collect-unattended-runner-"))), directory = join(parent, "journal"); await mkdir(directory, {mode: 0o700});
  const f = signedFixture(), journal = new UnattendedJournal(directory), store = new UnattendedStore(directory);
  const profile: UnattendedProfile = {contract_version: 2, scope: "rw_receipt_operations", identity: f.identity, helper_path: "/missing-reviewed-helper", helper_sha256: "a".repeat(64), journal_directory: directory};
  const calls: string[] = []; let n = 100, closes = 0, mutate: ((name: string, value: Json) => Json) | undefined;
  const transport = (): UnattendedTransport => ({initialize: async () => {}, close: async () => {closes++;}, call: async (name, args) => {
    calls.push(name); const {request_id, ...payload} = args, request: UnattendedRequest = {action: name.replace("collect_unattended_", "") as UnattendedRequest["action"], requestId: String(request_id), payload};
    const value = request.action === "reconcile_request" ? await journal.reconcile(f.identity, String(payload.target_request_id), request.requestId, f.signer, f.fetcher, f.now) :
      await journal.once(f.identity, request, f.signer, f.fetcher, f.now);
    const safe = mutate ? mutate(name, value as unknown as Json) : value;
    return {jsonrpc: "2.0", result: {structuredContent: {result: safe}}};
  }});
  const args = (requestId = id(20)) => ["--once", "--request-id", requestId, "--profile", "/synthetic-profile"];
  const dependencies = {profile: async () => profile, transport, now: f.now, uuid: () => id(n++)};
  return {...f, profile, calls, store, journal, args, dependencies, directory, closes: () => closes,
    mutate: (fn: (name: string, value: Json) => Json) => {mutate = fn;}, cleanup: () => rm(parent, {recursive: true, force: true})};
}
for (const args of [[], ["--once"], ["--once", "--request-id", id(2), "--profile", "relative"], ["--once", "--request-id", id(2), "--profile", "/p", "--url", "https://other"],
  ["--once", "--request-id", id(2), "--profile", "/p", "--max-events", "26"], ["--lookup", "--request-id", id(2), "--lookup-id", id(2), "--profile", "/p"]]) {
  test("bad runner options cause no profile, filesystem, process or network action " + JSON.stringify(args), async () => {
    let loads = 0; const report = await runUnattended(args, {profile: async () => {loads++; throw Error();}});
    assert.equal(report.status, "UNATTENDED_ARGUMENTS_INVALID"); assert.equal(loads, 0);
  });
}
test("bounded actual Edge/journal runner prepares only one batch then completes", async () => {
  const f = await fixture(); try {
    const report = await runUnattended(f.args(), f.dependencies); assert.equal(report.status, "UNATTENDED_COMPLETED");
    assert.deepEqual(f.calls, ["collect_unattended_begin_run", "collect_unattended_list_events", "collect_unattended_ensure_receipt", "collect_unattended_reconcile_backlog", "collect_unattended_complete_run"]);
    assert.equal(report.mode, "Dry-run"); assert.equal(report.handled_count, 0); assert.equal(report.deferred_count, 1); assert.equal(report.sender_actions, 0); assert.equal(report.carrier_delivery_verified, false);
    const plan = JSON.parse(await readFile(join(f.directory, `${id(20)}.run.json`), "utf8")); assert.equal(plan.request_ids.length, 9); assert.equal(new Set(plan.request_ids).size, 9);
    assert.equal(f.closes(), 1);
  } finally {await f.cleanup();}
});
test("same request restart creates no new backend attempt", async () => {
  const f = await fixture(); try {await runUnattended(f.args(), f.dependencies); const before = f.calls.length;
    const report = await runUnattended(f.args(), f.dependencies); assert.equal(report.status, "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"); assert.equal(f.calls.length, before);
  } finally {await f.cleanup();}
});
test("uncertain ensure stops before backlog/completion and blocks later overlap", async () => {
  const f = await fixture(); try {
    f.mutate((name, value) => name.endsWith("ensure_receipt") ? {...value, outcome: "unknown", reason_code: "UNATTENDED_OUTCOME_UNKNOWN", result: null} : value);
    const report = await runUnattended(f.args(), f.dependencies); assert.equal(report.status, "UNATTENDED_OUTCOME_UNKNOWN"); assert.equal(report.unresolved_request_id, id(101));
    assert.equal(f.calls.length, 3); const next = await runUnattended(f.args(id(21)), f.dependencies);
    assert.equal(next.status, "UNATTENDED_LOCAL_OVERLAP_RECONCILIATION_REQUIRED"); assert.equal(f.calls.length, 3);
  } finally {await f.cleanup();}
});
test("BUSY closes no-run evidence and local backoff refuses a later immediate run", async () => {
  const f = await fixture(); try {
    f.patch({ok: false, code: "RUN_BUSY", run_id: null, fence_version: null, expires_at: null});
    const report = await runUnattended(f.args(), f.dependencies); assert.equal(report.status, "RUN_BUSY"); assert.equal(report.local_backoff_seconds, 60); assert.equal(f.calls.length, 1);
    const next = await runUnattended(f.args(id(21)), f.dependencies); assert.equal(next.status, "UNATTENDED_LOCAL_BACKOFF_ACTIVE"); assert.equal(f.calls.length, 1);
    f.setNow(at + 60000); const fresh = await runUnattended(f.args(id(22)), f.dependencies); assert.equal(fresh.status, "RUN_BUSY"); assert.equal(f.calls.length, 2);
  } finally {await f.cleanup();}
});
test("parallel separate root requests have one local overlap winner", async () => {
  const f = await fixture(); try {
    const reports = await Promise.all([runUnattended(f.args(), f.dependencies), runUnattended(f.args(id(21)), f.dependencies)]);
    assert.equal(reports.filter(r => r.status === "UNATTENDED_COMPLETED").length, 1); assert.equal(f.calls.filter(n => n.endsWith("begin_run")).length, 1);
  } finally {await f.cleanup();}
});
test("lease expiry after begin prevents further action", async () => {
  const f = await fixture(); try {
    f.mutate((name, value) => {if (name.endsWith("begin_run")) f.setNow(at + 120001); return value;});
    const report = await runUnattended(f.args(), f.dependencies); assert.equal(report.status, "UNATTENDED_RUN_DEADLINE_OR_LEASE_EXPIRED"); assert.equal(f.calls.length, 1); assert.equal(report.unresolved_request_id, id(20));
    assert.ok(await f.store.read(`${String(report.unresolved_request_id)}.checkpoint.json`));
  } finally {await f.cleanup();}
});
test("local status never starts transport or signs", async () => {
  const f = await fixture(); try {
    await runUnattended(f.args(), f.dependencies); const calls = f.calls.length;
    const report = await runUnattended(["--status", "--request-id", id(20), "--profile", "/synthetic"], {...f.dependencies, transport: () => {throw Error("NO_PROCESS_ALLOWED");}});
    assert.equal(report.status, "UNATTENDED_LOCAL_RUN_CLOSED"); assert.equal(report.evidence, "historical_local_only"); assert.equal(f.calls.length, calls);
  } finally {await f.cleanup();}
});
test("malformed lookup reason cannot expose private backend text", async () => {
  const f = await fixture(); try {
    f.mutate((name, value) => name.endsWith("begin_run") ? {...value, outcome: "unknown", result: null} : value);
    await runUnattended(f.args(), f.dependencies);
    f.mutate((name, value) => name.endsWith("reconcile_request") ? {...value, reason_code: "private credential"} : value);
    const report = await runUnattended(["--lookup", "--request-id", id(20), "--lookup-id", id(30), "--profile", "/synthetic"], f.dependencies);
    assert.equal(report.status, "UNATTENDED_LOOKUP_UNAVAILABLE"); assert.equal(JSON.stringify(report).includes("private credential"), false);
  } finally {await f.cleanup();}
});
test("explicit successful original completion lookup can close local overlap only", async () => {
  const f = await fixture(); try {
    let complete: Json | undefined, completeId: string | undefined;
    f.mutate((name, value) => {if (name.endsWith("complete_run")) {complete = value.result as Json; completeId = String(value.request_id); return {...value, outcome: "unknown", result: null};} return value;});
    const first = await runUnattended(f.args(), f.dependencies); assert.equal(first.status, "UNATTENDED_OUTCOME_UNKNOWN");
    f.patch({status: "recorded", receipt: complete!}); f.mutate((_name, value) => value);
    const report = await runUnattended(["--lookup", "--request-id", completeId!, "--lookup-id", id(30), "--run-request-id", id(20), "--profile", "/synthetic"], f.dependencies);
    assert.equal(report.outcome, "recorded"); assert.equal(report.local_recovery, "UNATTENDED_COMPLETED"); assert.equal(report.automatic_replay, false);
    assert.equal(f.calls.filter(n => n.endsWith("complete_run")).length, 1);
  } finally {await f.cleanup();}
});
test("explicit old uncertain action lookup after lease horizon permits no mutation replay", async () => {
  const f = await fixture(); try {
    let old: Json | undefined, target: string | undefined;
    f.mutate((name, value) => {if (name.endsWith("ensure_receipt")) {old = value.result as Json; target = String(value.request_id); return {...value, outcome: "unknown", result: null};} return value;});
    await runUnattended(f.args(), f.dependencies); f.setNow(at + 240001); f.patch({status: "recorded", receipt: old!}); f.mutate((_name, value) => value);
    const report = await runUnattended(["--lookup", "--request-id", target!, "--lookup-id", id(30), "--run-request-id", id(20), "--profile", "/synthetic"], f.dependencies);
    assert.equal(report.local_recovery, "UNATTENDED_LEASE_EXPIRED_AFTER_LOOKUP"); assert.equal(f.calls.filter(n => n.endsWith("ensure_receipt")).length, 1); assert.equal(report.automatic_replay, false);
  } finally {await f.cleanup();}
});
test("parse supported manual lookup root is explicit and distinct lookup retained", () => {
  const options = parseUnattendedOptions(["--lookup", "--request-id", id(2), "--lookup-id", id(3), "--run-request-id", id(1), "--profile", "/p"]);
  assert.equal(options.lookupId, id(3)); assert.equal(options.runRequestId, id(1));
});

test("canonical malformed closure cannot certify a closed run or permit new overlap", async () => {
  const f = await fixture(); try {
    await runUnattended(f.args(), f.dependencies);
    await writeFile(join(f.directory, `${id(20)}.closed.json`), JSON.stringify({contract_version: 2, request_id: id(21), status: "UNATTENDED_COMPLETED", closed_at: new Date(at).toISOString(), not_before: new Date(at).toISOString()}) + "\n");
    const calls = f.calls.length;
    const status = await runUnattended(["--status", "--request-id", id(20), "--profile", "/synthetic"], f.dependencies);
    assert.equal(status.status, "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"); assert.equal(f.calls.length, calls);
    f.setNow(at + 2000);
    const next = await runUnattended(f.args(id(21)), f.dependencies); assert.equal(next.status, "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"); assert.equal(f.calls.length, calls);
  } finally {await f.cleanup();}
});
