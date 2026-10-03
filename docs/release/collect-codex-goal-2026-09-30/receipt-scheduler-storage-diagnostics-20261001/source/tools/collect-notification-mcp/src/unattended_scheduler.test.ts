import {test} from "node:test";
import assert from "node:assert/strict";
import {mkdtemp, realpath, rm, readFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {runSchedulerTick, schedulerRequestId} from "./unattended_scheduler.ts";
import {runUnattended} from "./unattended_runner.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {signedFixture, id, at} from "./testing/unattended_fixture.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import type {Json} from "./unattended_contract.ts";

async function fixture() {
  const f = signedFixture(), parent = await realpath(await mkdtemp(join(tmpdir(), "collect-schedule-")));
  const directory = join(parent, "journal");
  const profile: UnattendedProfile = {contract_version: 2, scope: "rw_receipt_operations", identity: f.identity,
    helper_path: "/unused-synthetic-helper", helper_sha256: "a".repeat(64), journal_directory: directory};
  const store = new UnattendedStore(directory), journal = new UnattendedJournal(directory, store);
  let n = 100, initializeFailed = false, loss: string | null = null;
  const fetcher: typeof fetch = async (url, options) => {
    const envelope = JSON.parse(String(options?.body)) as Json;
    if (envelope.action === "reconcile_request") {
      const target = (envelope.payload as Json).target_request_id;
      const original = f.results.find(value => value.request_id === target);
      f.patch(original ? {status: "recorded", receipt: original} : {status: "not_recorded", receipt: null});
    }
    const response = await f.fetcher(url, options);
    if (envelope.action === "reconcile_request") f.patch({});
    if (envelope.action === loss) {loss = null; throw Error("PRIVATE_NETWORK_CANARY");}
    return response;
  };
  const dependencies = {profile: async () => profile, now: f.now, uuid: () => id(n++), transport: () => ({
    initialize: async () => {if (initializeFailed) throw Error("PRIVATE_PROCESS_CANARY");},
    close: async () => {},
    call: async (name: string, arguments_: Record<string, unknown>) => {
      const {request_id, ...payload} = arguments_;
      const action = name.replace("collect_unattended_", "") as Parameters<UnattendedJournal["once"]>[1]["action"];
      const result = action === "reconcile_request"
        ? await journal.reconcile(f.identity, String(payload.target_request_id), String(request_id), f.signer, fetcher, f.now)
        : await journal.once(f.identity, {requestId: String(request_id), action, payload}, f.signer, fetcher, f.now);
      return {result: {structuredContent: {result}}};
    },
  })};
  const schedulerDependencies = {profile: dependencies.profile, now: f.now, uuid: dependencies.uuid,
    run: (args: readonly string[]) => runUnattended(args, dependencies)};
  const args = ["--tick", "--profile", "/synthetic-profile"];
  return {...f, profile, directory, store, args, dependencies, schedulerDependencies,
    lose: (action: string) => {loss = action;}, failInitialize: () => {initializeFailed = true;},
    recoverInitialize: () => {initializeFailed = false;}, cleanup: () => rm(parent, {recursive: true, force: true})};
}

for (const args of [[], ["--tick"], ["--tick", "--profile", "relative"],
  ["--tick", "--profile", "/p", "--interval-seconds", "59"],
  ["--tick", "--profile", "/p", "--max-events", "11"],
  ["--tick", "--profile", "/p", "--url", "https://other.invalid"],
  ["--tick", "--profile", "/p", "--profile", "/other"]]) {
  test("scheduler invalid arguments cause no IO or process " + JSON.stringify(args), async () => {
    let calls = 0;
    const result = await runSchedulerTick(args, {profile: async () => {calls++; throw Error();}});
    assert.equal(result.status, "SCHEDULER_ARGUMENTS_INVALID"); assert.equal(calls, 0);
  });
}

test("real signed Edge/journal/runner performs one bounded scheduled batch", async () => {
  const f = await fixture(); try {
    const result = await runSchedulerTick(f.args, f.schedulerDependencies);
    assert.equal(result.status, "SCHEDULER_BATCH_COMPLETED"); assert.equal(result.handled_count, 0); assert.equal(result.deferred_count, 1);
    assert.equal(result.complete_backlog_verified, false); assert.equal(result.carrier_delivery_verified, false); assert.equal(result.sender_actions, 0);
    assert.deepEqual(f.requests.map(request => request.action), ["begin_run", "list_events", "ensure_receipt", "reconcile_backlog", "complete_run"]);
    assert.equal(String(result.request_id), schedulerRequestId(f.profile, at, 60));
  } finally {await f.cleanup();}
});

test("same schedule window cannot produce a second mutation", async () => {
  const f = await fixture(); try {
    await runSchedulerTick(f.args, f.schedulerDependencies); const before = f.calls().http;
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_BACKOFF");
    assert.equal(f.calls().http, before);
    f.setNow(at + 61000);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_BATCH_COMPLETED");
    assert.equal(f.requests.filter(request => request.action === "begin_run").length, 2);
  } finally {await f.cleanup();}
});

test("overlapping scheduler processes have one original batch winner", async () => {
  const f = await fixture(); try {
    const results = await Promise.all([runSchedulerTick(f.args, f.schedulerDependencies), runSchedulerTick(f.args, f.schedulerDependencies)]);
    assert.equal(results.filter(result => result.status === "SCHEDULER_BATCH_COMPLETED").length, 1);
    assert.equal(f.requests.filter(request => request.action === "begin_run").length, 1);
  } finally {await f.cleanup();}
});

test("paused authority retains queue and backs off without business side effects", async () => {
  const f = await fixture(); try {
    f.patch({ok: false, code: "OPERATIONS_PAUSED", run_id: null, fence_version: null, expires_at: null});
    const result = await runSchedulerTick(f.args, f.schedulerDependencies);
    assert.equal(result.status, "SCHEDULER_BATCH_DEFERRED"); assert.equal(result.reason_code, "OPERATIONS_PAUSED");
    f.setNow(at + 30000);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_BACKOFF");
    assert.deepEqual(f.requests.map(request => request.action), ["begin_run"]);
  } finally {await f.cleanup();}
});

test("lost response is looked up, never replayed, and new work waits for expired lease proof", async () => {
  const f = await fixture(); try {
    f.lose("ensure_receipt");
    const first = await runSchedulerTick(f.args, f.schedulerDependencies);
    assert.equal(first.status, "SCHEDULER_BATCH_DEFERRED");
    const original = f.requests.find(request => request.action === "ensure_receipt")!;
    f.setNow(at + 30000);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_RECONCILIATION_PENDING");
    assert.equal(f.requests.filter(request => request.action === "ensure_receipt").length, 1);
    assert.ok(f.requests.some(request => request.action === "reconcile_request" && request.payload.target_request_id === original.requestId));
    f.setNow(at + 240001);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_ORIGINAL_RECONCILED");
    assert.equal(f.requests.filter(request => request.action === "begin_run").length, 1);
    f.setNow(at + 301000);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_BATCH_COMPLETED");
    assert.equal(f.requests.filter(request => request.action === "ensure_receipt" && request.requestId === original.requestId).length, 1);
    assert.equal(JSON.stringify(first).includes("PRIVATE_NETWORK_CANARY"), false);
  } finally {await f.cleanup();}
});

test("crash before first checkpoint closes locally only after the fixed plan deadline", async () => {
  const f = await fixture(); try {
    f.failInitialize();
    const first = await runSchedulerTick(f.args, f.schedulerDependencies);
    assert.equal(first.status, "SCHEDULER_BATCH_DEFERRED"); assert.equal(f.calls().http, 0);
    const requestId = String(first.request_id);
    f.setNow(at + 119999);
    const early = await runUnattended(["--recover-unstarted", "--request-id", requestId, "--profile", "/synthetic"], f.dependencies);
    assert.equal(early.status, "UNATTENDED_LOCAL_RECOVERY_REFUSED");
    f.setNow(at + 120001);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_UNSTARTED_RUN_CLOSED");
    assert.equal(f.calls().http, 0);
    const closed = JSON.parse(await readFile(join(f.directory, `${requestId}.closed.json`), "utf8"));
    assert.equal(closed.status, "UNATTENDED_NOT_STARTED");
    f.recoverInitialize(); f.setNow(at + 181000);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_BATCH_COMPLETED");
  } finally {await f.cleanup();}
});

test("a persisted checkpoint prevents local unstarted recovery", async () => {
  const f = await fixture(); try {
    f.lose("begin_run"); const first = await runSchedulerTick(f.args, f.schedulerDependencies); f.setNow(at + 300000);
    const report = await runUnattended(["--recover-unstarted", "--request-id", String(first.request_id), "--profile", "/synthetic"], f.dependencies);
    assert.equal(report.status, "UNATTENDED_LOCAL_RECOVERY_REFUSED");
    assert.equal(await f.store.read(`${String(first.request_id)}.closed.json`, true), null);
  } finally {await f.cleanup();}
});

test("expired identity and malformed local history cause no network", async () => {
  const f = await fixture(); try {
    f.setNow(at + 86400001);
    assert.equal((await runSchedulerTick(f.args, f.schedulerDependencies)).status, "SCHEDULER_IDENTITY_UNAVAILABLE");
    assert.equal(f.calls().http, 0);
    f.setNow(at);
    await f.store.publish(`principal-${f.identity.principalId}.lock.json`, {private: "PRIVATE_LOCAL_CANARY"});
    const report = await runSchedulerTick(f.args, f.schedulerDependencies);
    assert.equal(report.status, "SCHEDULER_JOURNAL_INTEGRITY_REQUIRED"); assert.equal(f.calls().http, 0);
    assert.equal(JSON.stringify(report).includes("PRIVATE_LOCAL_CANARY"), false);
  } finally {await f.cleanup();}
});

test("schedule IDs are stable per key and period and change at the next window", async () => {
  const f = await fixture(); try {
    const same = schedulerRequestId(f.profile, at, 60);
    assert.equal(same, schedulerRequestId(f.profile, at, 60));
    assert.notEqual(same, schedulerRequestId(f.profile, at + 60000, 60));
    assert.notEqual(same, schedulerRequestId({...f.profile, identity: {...f.identity, keySha256: "b".repeat(64)}}, at, 60));
  } finally {await f.cleanup();}
});
