import {test} from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {historyHead, historyName, historySegmentSize, type HistoryPlan} from "./unattended_history.ts";
import {UnattendedStore, type UnattendedStoreIO} from "./unattended_store.ts";
import {runUnattended} from "./unattended_runner.ts";
import {runSchedulerTick} from "./unattended_scheduler.ts";
import {id, at, result} from "./testing/unattended_fixture.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedRequest} from "./unattended_contract.ts";

async function fixture(count: number, tailUnresolved = false) {
  const parent = await fs.realpath(await fs.mkdtemp(join(tmpdir(), "collect-history-"))), directory = join(parent, "journal");
  await fs.mkdir(directory, {mode: 0o700});
  const identity = {principalId: id(1), keySha256: "a".repeat(64), expiresAt: new Date(at + 86400000).toISOString()};
  const profile: UnattendedProfile = {contract_version: 2, scope: "rw_receipt_operations", identity,
    helper_path: "/unused-synthetic-helper", helper_sha256: "b".repeat(64), journal_directory: directory};
  const ids = Array.from({length: count}, (_, i) => id(10000 + i * 10));
  const created = (i: number) => new Date(at + i * 2000).toISOString();
  // Synthetic schema-valid historical closed batches, not evidence of executed
  // backend/Edge runs. Real store publications/readbacks are exercised below.
  const write = (name: string, value: unknown) => fs.writeFile(join(directory, name), JSON.stringify(value) + "\n", {mode: 0o600});
  await write(`principal-${identity.principalId}.lock.json`, {contract_version: 2, scope: profile.scope, principal_id: identity.principalId, key_sha256: identity.keySha256, request_id: ids[0]});
  for (let i = 0; i < count; i++) {
    const plan: HistoryPlan = {contract_version: 2, scope: profile.scope, principal_id: identity.principalId, key_sha256: identity.keySha256,
      request_id: ids[i]!, created_at: created(i), request_ids: Array.from({length: 5}, (_, j) => id(10000 + i * 10 + j)), max_events: 1};
    await write(`${ids[i]}.run.json`, plan);
    if (i + 1 < count) await write(`${ids[i]}.step.json`, {contract_version: 2, previous_request_id: ids[i], request_id: ids[i + 1]});
    if (i + 1 < count || !tailUnresolved) await write(`${ids[i]}.closed.json`, {contract_version: 2, request_id: ids[i], status: "UNATTENDED_COMPLETED",
      closed_at: created(i), not_before: new Date(at + i * 2000 + 1000).toISOString()});
  }
  const now = at + count * 2000, store = new UnattendedStore(directory);
  return {parent, directory, profile, identity, ids, now, store, write,
    cleanup: () => fs.rm(parent, {recursive: true, force: true})};
}
const code = (operation: Promise<unknown>, expected = "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED") => assert.rejects(operation, {message: expected});

test("1,101 closed historical batches remain readable and the next runner batch executes once", async () => {
  const f = await fixture(1101); try {
    const before = await fs.readFile(join(f.directory, `${f.ids[0]}.closed.json`));
    assert.equal(await historyHead(f.store, f.identity, f.now), f.ids.at(-1));
    assert.equal((await fs.readdir(f.directory)).filter(name => name.includes(".history-")).length, 8);
    assert.equal(await historyHead(new UnattendedStore(f.directory), f.identity, f.now), f.ids.at(-1));
    let uuidCounter = 500000, calls = 0;
    const deps = {profile: async () => f.profile, now: () => f.now, uuid: () => id(uuidCounter++), transport: () => ({
      initialize: async () => {}, close: async () => {}, call: async (name: string, args: Record<string, unknown>) => {
        calls++; const {request_id, ...payload} = args;
        const request: UnattendedRequest = {action: name.replace("collect_unattended_", "") as UnattendedRequest["action"], requestId: String(request_id), payload};
        return {result: {structuredContent: {result: {contract_version: 2, scope: f.profile.scope, principal_id: f.identity.principalId,
          request_id, action: request.action, outcome: "recorded", reason_code: "UNATTENDED_RESULT_RECORDED", result: result(request, f.identity, f.now), lookup_request_id: null}}}};
      },
    })};
    const args = ["--once", "--request-id", id(600000), "--profile", "/synthetic", "--max-events", "1"];
    assert.equal((await runUnattended(args, deps)).status, "UNATTENDED_COMPLETED"); assert.equal(calls, 5);
    assert.equal((await runUnattended(args, deps)).status, "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"); assert.equal(calls, 5);
    assert.deepEqual(await fs.readFile(join(f.directory, `${f.ids[0]}.closed.json`)), before);
    assert.equal(await historyHead(new UnattendedStore(f.directory), f.identity, f.now), id(600000));
  } finally {await f.cleanup();}
});

test("indexed lookup reads a bounded recent segment rather than the entire growing archive", async () => {
  const f = await fixture(1101); try {
    await historyHead(f.store, f.identity, f.now);
    let reads = 0;
    const io: UnattendedStoreIO = {...fs, open: async (...args: Parameters<typeof fs.open>) => {reads++; return fs.open(...args);}};
    assert.equal(await historyHead(new UnattendedStore(f.directory, io), f.identity, f.now), f.ids.at(-1));
    assert.ok(reads < 900, `Bounded selected-segment verification unexpectedly read ${reads} records`);
  } finally {await f.cleanup();}
});

test("an unresolved tail beyond 1,000 batches remains the head and blocks all new mutation", async () => {
  const f = await fixture(1101, true); try {
    assert.equal(await historyHead(f.store, f.identity, f.now), f.ids.at(-1));
    let initializes = 0, n = 500000;
    const response = await runUnattended(["--once", "--request-id", id(600000), "--profile", "/synthetic"], {
      profile: async () => f.profile, now: () => f.now, uuid: () => id(n++), transport: () => {initializes++; throw Error("PRIVATE_NETWORK_CANARY");},
    });
    assert.equal(response.status, "UNATTENDED_LOCAL_OVERLAP_RECONCILIATION_REQUIRED"); assert.equal(initializes, 0);
    assert.equal(await f.store.read(`${f.ids.at(-1)}.closed.json`, true), null);
  } finally {await f.cleanup();}
});

for (const stage of ["before_link", "after_link", "directory_sync"] as const) {
  test(`interrupted index publication at ${stage} retains original records and is recoverable after restart`, async () => {
    const f = await fixture(historySegmentSize + 2); try {
      let interrupted = false;
      const io: UnattendedStoreIO = {...fs,
        link: async (from, to) => {
          if (!interrupted && String(to).includes(".history-") && stage !== "directory_sync") {
            interrupted = true;
            if (stage === "after_link") await fs.link(from, to);
            throw Error("PRIVATE_INDEX_INTERRUPTED");
          }
          await fs.link(from, to);
        },
        open: async (...args: Parameters<typeof fs.open>) => {
          const file = await fs.open(...args), sync = file.sync.bind(file);
          if (stage === "directory_sync" && String(args[0]) === f.directory) file.sync = async () => {
            if (!interrupted) {interrupted = true; throw Error("PRIVATE_INDEX_SYNC_FAILED");} await sync();
          };
          return file;
        },
      };
      const failed = new UnattendedStore(f.directory, io);
      await code(historyHead(failed, f.identity, f.now), "UNATTENDED_JOURNAL_UNAVAILABLE");
      assert.equal(interrupted, true);
      assert.equal(await historyHead(new UnattendedStore(f.directory), f.identity, f.now), f.ids.at(-1));
      for (const original of f.ids) assert.ok(await f.store.read(`${original}.run.json`));
    } finally {await f.cleanup();}
  });
}

test("concurrent history maintenance publishes one identical immutable index per segment", async () => {
  const f = await fixture(260); try {
    const heads = await Promise.all(Array.from({length: 4}, () => historyHead(new UnattendedStore(f.directory), f.identity, f.now)));
    assert.ok(heads.every(head => head === f.ids.at(-1)));
    assert.equal((await fs.readdir(f.directory)).filter(name => name.includes(".history-")).length, 2);
    assert.equal(await historyHead(new UnattendedStore(f.directory), f.identity, f.now), f.ids.at(-1));
  } finally {await f.cleanup();}
});

for (const kind of ["index", "plan", "step", "closure", "predecessor", "root"] as const) {
  test(`canonical replacement of selected ${kind} proof fails closed`, async () => {
    const f = await fixture(260); try {
      await historyHead(f.store, f.identity, f.now);
      const name = kind === "index" ? historyName(f.identity, 2) : kind === "predecessor" ? historyName(f.identity, 1) :
        kind === "root" ? `principal-${f.identity.principalId}.lock.json` : `${f.ids[140]}.${kind === "plan" ? "run" : kind === "closure" ? "closed" : "step"}.json`;
      const value = await f.store.read(name) as Record<string, unknown>;
      if (kind === "index" || kind === "predecessor") value.head_run_sha256 = "c".repeat(64);
      else if (kind === "root") value.request_id = f.ids[1];
      else if (kind === "plan") value.max_events = 2;
      else if (kind === "step") value.request_id = f.ids[142];
      else value.status = "UNATTENDED_NOT_STARTED";
      const path = join(f.directory, name);
      await fs.rename(path, join(f.parent, `replaced-${kind}`));
      await f.write(name, value);
      await code(historyHead(new UnattendedStore(f.directory), f.identity, f.now));
    } finally {await f.cleanup();}
  });
}

test("missing predecessor, foreign key binding and source cycles cannot authorize a new run", async () => {
  const f = await fixture(260); try {
    await historyHead(f.store, f.identity, f.now);
    await fs.unlink(join(f.directory, historyName(f.identity, 1)));
    await code(historyHead(new UnattendedStore(f.directory), f.identity, f.now));
    await code(historyHead(new UnattendedStore(f.directory), {...f.identity, keySha256: "c".repeat(64)}, f.now));
  } finally {await f.cleanup();}
  const cycle = await fixture(3); try {
    await cycle.write(`${cycle.ids[2]}.step.json`, {contract_version: 2, previous_request_id: cycle.ids[2], request_id: cycle.ids[0]});
    await code(historyHead(cycle.store, cycle.identity, cycle.now));
  } finally {await cycle.cleanup();}
});

test("scheduler after 1,001 closed batches backs off within a known window without calls or replay", async () => {
  const f = await fixture(1001); try {
    await f.write(`${f.ids.at(-1)}.closed.json`, {contract_version: 2, request_id: f.ids.at(-1), status: "UNATTENDED_COMPLETED",
      closed_at: new Date(f.now - 1000).toISOString(), not_before: new Date(f.now + 60000).toISOString()});
    let called = 0;
    // The actual scheduler uses history indexing before selecting its tail.
    const reply = await runSchedulerTick(["--tick", "--profile", "/synthetic"], {profile: async () => f.profile, now: () => f.now,
      run: async args => {
        called++; assert.equal(args[0], "--status"); assert.equal(args[2], f.ids.at(-1));
        return {status: "UNATTENDED_LOCAL_RUN_CLOSED", contract_version: 2, scope: f.profile.scope, request_id: f.ids.at(-1),
          sender_actions: 0, credentials_printed: false, unresolved_request_id: null, evidence: "historical_local_only"};
      },
    });
    assert.equal(reply.status, "SCHEDULER_BACKOFF"); assert.equal(called, 1);
    assert.equal(reply.sender_actions, 0);
  } finally {await f.cleanup();}
});

test("concurrent scheduler ticks after 1,001 batches retain one CAS winner and one backend begin", async () => {
  const f = await fixture(1001); try {
    let n = 500000, begins = 0;
    const deps = {profile: async () => f.profile, now: () => f.now, uuid: () => id(n++), transport: () => ({
      initialize: async () => {}, close: async () => {}, call: async (name: string, args: Record<string, unknown>) => {
        const {request_id, ...payload} = args;
        const request: UnattendedRequest = {action: name.replace("collect_unattended_", "") as UnattendedRequest["action"], requestId: String(request_id), payload};
        if (request.action === "begin_run") begins++;
        return {result: {structuredContent: {result: {contract_version: 2, scope: f.profile.scope, principal_id: f.identity.principalId,
          request_id, action: request.action, outcome: "recorded", reason_code: "UNATTENDED_RESULT_RECORDED", result: result(request, f.identity, f.now), lookup_request_id: null}}}};
      },
    })};
    const scheduler = {profile: deps.profile, now: deps.now, run: (args: readonly string[]) => runUnattended(args, deps)};
    const reports = await Promise.all([runSchedulerTick(["--tick", "--profile", "/synthetic"], scheduler), runSchedulerTick(["--tick", "--profile", "/synthetic"], scheduler)]);
    assert.equal(reports.filter(report => report.status === "SCHEDULER_BATCH_COMPLETED").length, 1);
    assert.equal(begins, 1);
    assert.equal((await fs.readdir(f.directory)).filter(name => name.includes(".history-")).length, 7);
  } finally {await f.cleanup();}
});

test("an indexed unresolved run can close only through existing unstarted recovery without HTTP", async () => {
  const f = await fixture(1001, true); try {
    await historyHead(f.store, f.identity, f.now);
    let transports = 0;
    const deps = {profile: async () => f.profile, now: () => f.now + 120000, transport: () => {transports++; throw Error("PRIVATE_UNEXPECTED_TRANSPORT");}};
    const args = ["--tick", "--profile", "/synthetic"];
    const response = await runSchedulerTick(args, {profile: deps.profile, now: deps.now, run: (values: readonly string[]) => runUnattended(values, deps)});
    assert.equal(response.status, "SCHEDULER_UNSTARTED_RUN_CLOSED"); assert.equal(transports, 0);
    assert.equal((await f.store.read(`${f.ids.at(-1)}.closed.json`) as Record<string, unknown>).status, "UNATTENDED_NOT_STARTED");
    assert.equal(await historyHead(new UnattendedStore(f.directory), f.identity, f.now + 120000), f.ids.at(-1));
  } finally {await f.cleanup();}
});

test("large legacy history migration is bounded, durable and resumes without reusing a mutation UUID", async () => {
  const f = await fixture(4130); try {
    await code(historyHead(f.store, f.identity, f.now), "UNATTENDED_HISTORY_MAINTENANCE_REQUIRED");
    assert.equal((await fs.readdir(f.directory)).filter(name => name.includes(".history-")).length, 32);
    assert.equal(await historyHead(new UnattendedStore(f.directory), f.identity, f.now), f.ids.at(-1));
    assert.ok(await f.store.read(`${f.ids.at(-1)}.run.json`));
  } finally {await f.cleanup();}
});

test("history names reject invalid sequence/key/principal before any evidence access", () => {
  const identity = {principalId: id(1), keySha256: "a".repeat(64)};
  for (const sequence of [0, -1, 1.5, 1000000001, NaN, Infinity]) assert.throws(() => historyName(identity, sequence), {message: "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
  assert.throws(() => historyName({...identity, principalId: "private-canary"}, 1));
  assert.throws(() => historyName({...identity, keySha256: "not-a-hash"}, 1));
  assert.equal(historyName(identity, 1), `principal-${id(1)}.history-0000000001.json`);
});

test("a plan prepared during previous backoff is not confused with its later claim time", async () => {
  const f = await fixture(2); try {
    const next = await f.store.read(`${f.ids[1]}.run.json`) as HistoryPlan;
    next.created_at = new Date(at + 500).toISOString();
    await f.write(`${f.ids[1]}.run.json`, next);
    assert.equal(await historyHead(f.store, f.identity, f.now), f.ids[1]);
  } finally {await f.cleanup();}
});

test("head source changed during index publication cannot be accepted as a current-head proof", async () => {
  const f = await fixture(130); try {
    const io: UnattendedStoreIO = {...fs, link: async (from, to) => {
      await fs.link(from, to);
      if (String(to).includes(".history-")) {
        const head = await f.store.read(`${f.ids[128]}.run.json`) as HistoryPlan;
        head.created_at = new Date(at).toISOString();
        await f.write(`${f.ids[128]}.run.json`, head);
      }
    }};
    await code(historyHead(new UnattendedStore(f.directory, io), f.identity, f.now));
    await code(historyHead(new UnattendedStore(f.directory), f.identity, f.now));
  } finally {await f.cleanup();}
});
