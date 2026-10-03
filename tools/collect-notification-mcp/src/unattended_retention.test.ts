import {test, type TestContext} from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {createHash} from "node:crypto";
import {spawn} from "node:child_process";
import {once} from "node:events";
import {pathToFileURL} from "node:url";
import {UnattendedStore, type UnattendedStoreIO} from "./unattended_store.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {runUnattended} from "./unattended_runner.ts";
import {runSchedulerTick} from "./unattended_scheduler.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import {RetainedEvidence, retainedPolicy, retentionPolicySha256} from "./unattended_retained.ts";
import {maintainSchedulerEvidence} from "./unattended_retention.ts";
import {schedulerStorageDiagnostics, schedulerStorageLimits, beginSchedulerTickDiagnostic, endSchedulerTickDiagnostic} from "./unattended_scheduler_storage.ts";
import {schedulerTickPermitted} from "./unattended_scheduler_control.ts";
import {historyHead, type HistoryPlan} from "./unattended_history.ts";
import type {Deployment} from "./unattended_deployment.ts";
import {unattendedScope, unattendedAudience, envelope, type UnattendedRequest, type Json} from "./unattended_contract.ts";
import {id, at, signedFixture, result} from "./testing/unattended_fixture.ts";
const sha = (value: unknown) => createHash("sha256").update(JSON.stringify(value)).digest("hex");

async function fixture(t: TestContext) {
  const parent = await fs.realpath(await fs.mkdtemp(join(tmpdir(), "collect-cold-retention-"))); await fs.chmod(parent, 0o700);
  t.after(() => fs.rm(parent, {recursive: true, force: true}));
  const directory = join(parent, "prepared"), journal = join(parent, "journal");
  await fs.mkdir(directory, {mode: 0o700}); for (const name of ["control", "diagnostics"]) await fs.mkdir(join(directory, name), {mode: 0o700});
  await fs.mkdir(journal, {mode: 0o700});
  const identity = {principalId: id(1), keySha256: "a".repeat(64), expiresAt: new Date(at + 86400000).toISOString()};
  // The maintenance API needs only these binding fields; activation tests below
  // use retained schema-valid control claims, never a real host job.
  const deployment = {directory, manifestSha: "b".repeat(64), manifest: {identity, journal_directory: journal, uid: process.getuid!(), label: "com.ikanisa.collect.receipt-operations",
    retention_policy_sha256: retentionPolicySha256, profile_sha256: "c".repeat(64)}} as Deployment;
  return {parent, directory, journal, identity, deployment, store: new UnattendedStore(journal)};
}
function operation(f: Awaited<ReturnType<typeof fixture>>, requestId: string) {
  return {contract_version: 1, kind: "local_scheduler_operation", scope: unattendedScope, origin: "https://lhbowpbcpwoiparwnwgt.supabase.co",
    action: "activate", request_id: requestId, preparation_sha256: f.deployment.manifestSha, profile_sha256: f.deployment.manifest.profile_sha256,
    principal_id: f.identity.principalId, key_sha256: f.identity.keySha256, uid: process.getuid!(), label: "com.ikanisa.collect.receipt-operations",
    created_at: new Date(at).toISOString(), request_expires_at: new Date(at + 30000).toISOString(), actor_id: id(802), session_id: id(803), activation_request_id: null};
}
async function write(directory: string, name: string, value: unknown) {await fs.writeFile(join(directory, name), JSON.stringify(value) + "\n", {mode: 0o600});}
async function recorded(store: UnattendedStore, identity: Deployment["manifest"]["identity"], request: UnattendedRequest, time: number, value?: Json) {
  const checkpoint = {contract_version: 2, scope: unattendedScope, audience: unattendedAudience, identity, request, created_at: new Date(time).toISOString()};
  const armed = {contract_version: 2, request_id: request.requestId, envelope_sha256: sha(envelope(identity, request, time)),
    issued_at: new Date(time).toISOString(), not_recorded_before: new Date(time + 120000).toISOString()};
  const outcome = {contract_version: 2, scope: unattendedScope, principal_id: identity.principalId, request_id: request.requestId, action: request.action,
    outcome: "recorded", reason_code: "UNATTENDED_RESULT_RECORDED", result: value ?? result(request, identity, time), lookup_request_id: null};
  await write(store.directory, `${request.requestId}.checkpoint.json`, checkpoint); await write(store.directory, `${request.requestId}.armed.json`, armed);
  await write(store.directory, `${request.requestId}.outcome.json`, outcome);
  return outcome;
}
async function plans(f: Awaited<ReturnType<typeof fixture>>, count = 132, bad: "none" | "unknown" | "expired" = "none") {
  const ids = Array.from({length: count}, (_, index) => id(10000 + index * 10));
  await write(f.journal, `principal-${f.identity.principalId}.lock.json`, {contract_version: 2, scope: unattendedScope,
    principal_id: f.identity.principalId, key_sha256: f.identity.keySha256, request_id: ids[0]});
  for (let index = 0; index < count; index++) {
    const time = at + index * 1000, requestId = ids[index]!;
    const plan: HistoryPlan = {contract_version: 2, scope: unattendedScope, principal_id: f.identity.principalId, key_sha256: f.identity.keySha256,
      request_id: requestId, created_at: new Date(time).toISOString(), request_ids: Array.from({length: 5}, (_, n) => id(10000 + index * 10 + n)), max_events: 1};
    await write(f.journal, `${requestId}.run.json`, plan);
    if (index + 1 < count) await write(f.journal, `${requestId}.step.json`, {contract_version: 2, previous_request_id: requestId, request_id: ids[index + 1]});
    await write(f.journal, `${requestId}.closed.json`, {contract_version: 2, request_id: requestId,
      status: index === 0 && bad === "expired" ? "UNATTENDED_LEASE_EXPIRED_AFTER_LOOKUP" : "OPERATIONS_PAUSED",
      closed_at: new Date(time + (index === 0 && bad === "expired" ? 240000 : 0)).toISOString(), not_before: new Date(time + 241000).toISOString()});
    const request: UnattendedRequest = {action: "begin_run", requestId, payload: {}};
    const paused = result(request, f.identity, time, {ok: false, code: "OPERATIONS_PAUSED", run_id: null, fence_version: null, mode: "Paused", expires_at: null});
    await recorded(f.store, f.identity, request, time, index === 0 && bad === "expired" ? result(request, f.identity, time) : paused);
    if (index === 0 && bad !== "none") {
      const child: UnattendedRequest = {action: "prove_key", requestId: plan.request_ids[1]!, payload: {}};
      await recorded(f.store, f.identity, child, time);
      const original = await f.store.read(`${child.requestId}.outcome.json`) as Json;
      await write(f.journal, `${child.requestId}.outcome.json`, {...original, outcome: "unknown", reason_code: "UNATTENDED_OUTCOME_UNKNOWN", result: null});
    }
  }
  return ids;
}

test("archive removes only hot bytes after durable exact retained identity and read-through survives reload", async t => {
  const f = await fixture(t), name = `${id(7)}.checkpoint.json`, value = {contract_version: 2, request_id: id(7), evidence: "recorded"};
  await f.store.publish(name, value); const stages: string[] = [];
  await f.store.archive(name, value, async stage => {stages.push(stage);
    if (stage === "generation_durable") await assert.rejects(f.store.read(name), {message: "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
    else assert.deepEqual(await f.store.read(name), value);});
  assert.deepEqual(stages, ["object_durable", "transaction_durable", "generation_durable", "index_durable"]);
  assert.equal((await fs.readdir(f.journal)).includes(name), false); assert.deepEqual(await new UnattendedStore(f.journal).read(name), value);
  await assert.rejects(new UnattendedStore(f.journal).publish(name, {...value, evidence: "new"}), {message: "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"});
});

test("an archived original UUID signs and sends zero times through the actual journal once caller", async t => {
  const f = await fixture(t), signed = signedFixture(), request: UnattendedRequest = {action: "begin_run", requestId: id(9), payload: {}};
  const journal = new UnattendedJournal(f.journal), outcome = await journal.once(signed.identity, request, signed.signer, signed.fetcher, signed.now);
  assert.equal(outcome.outcome, "recorded");
  for (const suffix of ["checkpoint", "armed", "outcome"]) {const name = `${request.requestId}.${suffix}.json`; await f.store.archive(name, await f.store.read(name));}
  let signatures = 0, http = 0;
  const again = await new UnattendedJournal(f.journal).once(signed.identity, request,
    async (...args) => {signatures++; return signed.signer(...args);}, async (...args) => {http++; return signed.fetcher(...args);}, signed.now);
  assert.equal(again.outcome, "unknown"); assert.equal(signatures, 0); assert.equal(http, 0);
  assert.deepEqual(await new UnattendedJournal(f.journal).readOriginal(request.requestId), outcome);
});

for (const stage of ["object_durable", "transaction_durable", "generation_durable", "index_durable", "hot_removed"]) {
  test(`killed archive at ${stage} resumes its original local evidence without a fresh publication`, async t => {
    const f = await fixture(t), name = `${id(20)}.checkpoint.json`, value = {contract_version: 2, request_id: id(20), result: "original"};
    await f.store.publish(name, value);
    const module = pathToFileURL(join(import.meta.dirname, "unattended_store.ts")).href;
    const source = `import * as fs from 'node:fs/promises'; import {UnattendedStore} from ${JSON.stringify(module)};
const path=${JSON.stringify(f.journal)},name=${JSON.stringify(name)},value=${JSON.stringify(value)},selected=${JSON.stringify(stage)};
const stop=async()=>{process.stdout.write('DURABLE\\n');await new Promise(()=>{});};
const io={...fs,unlink:async p=>{await fs.unlink(p);if(selected==='hot_removed'&&String(p).endsWith(name))await stop();}};
await new UnattendedStore(path,io).archive(name,value,async step=>{if(step===selected)await stop();});`;
    const child = spawn(process.execPath, ["--experimental-strip-types", "--input-type=module", "-e", source], {stdio: ["ignore", "pipe", "pipe"]});
    let stderr = ""; child.stderr.on("data", data => {stderr += data;});
    await Promise.race([once(child.stdout, "data"), once(child, "exit").then(() => {throw Error(stderr);}),
      new Promise((_, reject) => {const timeout = setTimeout(() => reject(Error("child proof deadline")), 10000); timeout.unref();})]);
    const ended = once(child, "close"); child.kill("SIGKILL"); await ended;
    const restarted = new UnattendedStore(f.journal); await restarted.archive(name, value);
    assert.deepEqual(await restarted.read(name), value); assert.equal((await fs.readdir(f.journal)).includes(name), false);
    await assert.rejects(restarted.publish(name, value), {message: "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"});
  });
}

test("a stale concurrent archive intent appends to the current root and preserves both winners", async t => {
  const f = await fixture(t), first = `${id(30)}.outcome.json`, second = `${id(31)}.outcome.json`;
  await f.store.publish(first, {id: 30}); await f.store.publish(second, {id: 31});
  let ready!: () => void, release!: () => void; const waiting = new Promise<void>(resolve => {ready = resolve;}), barrier = new Promise<void>(resolve => {release = resolve;});
  const a = f.store.archive(first, {id: 30}, async stage => {if (stage === "object_durable") {ready(); await barrier;}});
  await waiting; await new UnattendedStore(f.journal).archive(second, {id: 31}); release(); await a;
  assert.deepEqual(await f.store.read(first), {id: 30}); assert.deepEqual(await f.store.read(second), {id: 31});
  assert.equal((await fs.readdir(f.journal)).length, 0);
});

test("archive and hot publish race retains one original basename and rejects a competing claim", async t => {
  const f = await fixture(t), name = `${id(32)}.checkpoint.json`, value = {id: 32}; await f.store.publish(name, value);
  let publication!: () => void, release!: () => void; const published = new Promise<void>(resolve => {publication = resolve;}), barrier = new Promise<void>(resolve => {release = resolve;});
  const io: UnattendedStoreIO = {...fs, unlink: async path => {await fs.unlink(path); if (String(path) === join(f.journal, name)) {publication(); await barrier;}}};
  const archive = new UnattendedStore(f.journal, io).archive(name, value); await published;
  await assert.rejects(new UnattendedStore(f.journal).publish(name, {id: 33}), {message: "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"}); release(); await archive;
  assert.deepEqual(await f.store.read(name), value);
});

for (const target of ["root", "head", "node", "object", "receipt", "head-generation"] as const) {
  test(`missing established ${target} fails closed even on an optional UUID lookup`, async t => {
    const f = await fixture(t), name = `${id(40)}.checkpoint.json`, value = {id: 40}; await f.store.publish(name, value); await f.store.archive(name, value);
    const cold = f.store.retained.directory, head = JSON.parse(await fs.readFile(join(cold, "head.json"), "utf8"));
    const node = JSON.parse(await fs.readFile(join(cold, "nodes", head.root_sha256), "utf8")), entry = node.entries[0];
    const path = target === "root" ? cold : target === "head" ? join(cold, "head.json") : target === "node" ? join(cold, "nodes", head.root_sha256) :
      target === "object" ? join(cold, "objects", entry.bytes_sha256) : target === "receipt" ? join(cold, "objects", entry.receipt_sha256) : join(cold, "heads", String(head.sequence).padStart(16, "0"));
    await fs.rm(path, {recursive: target === "root"});
    await assert.rejects(new UnattendedStore(f.journal).read(name, true), {message: "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
    await assert.rejects(new UnattendedStore(f.journal).publish(name, {id: 41}));
  });
}

test("conflicting hot/cold bytes and tampered canonical cold bytes are never accepted", async t => {
  const f = await fixture(t), name = `${id(50)}.outcome.json`; await f.store.publish(name, {id: 50}); await f.store.archive(name, {id: 50});
  await write(f.journal, name, {id: 51}); await assert.rejects(f.store.read(name), {message: "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
  await fs.unlink(join(f.journal, name)); const head = JSON.parse(await fs.readFile(join(f.store.retained.directory, "head.json"), "utf8"));
  const node = JSON.parse(await fs.readFile(join(f.store.retained.directory, "nodes", head.root_sha256), "utf8"));
  await write(join(f.store.retained.directory, "objects"), node.entries[0].bytes_sha256, {id: 52});
  await assert.rejects(f.store.read(name), {message: "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
});

test("bounded export and multi-page restore preserve exact evidence while all control authority stays inactive", async t => {
  const f = await fixture(t);
  for (let n = 0; n < 70; n++) {const name = `${id(100 + n)}.outcome.json`, value = {n}; await f.store.publish(name, value); await f.store.archive(name, value);}
  const restoreHot = join(f.parent, "restored"); await fs.mkdir(restoreHot, {mode: 0o700}); const restore = new RetainedEvidence(restoreHot);
  let cursor: string | null = null, total = 0, root: string | null | undefined;
  do {const page = await f.store.retained.exportPage(cursor, 17, root); root = page.root_sha256; assert.ok(page.entries.length <= 17);
    await restore.restorePage(page); total += page.entries.length; cursor = page.next_cursor;} while (cursor !== null);
  assert.equal(total, 70); assert.equal(await restore.inactive(), true);
  for (let n = 0; n < 70; n++) assert.deepEqual(await new UnattendedStore(restoreHot).read(`${id(100 + n)}.outcome.json`), {n});
  await assert.rejects(f.store.retained.exportPage("bad")); await assert.rejects(f.store.retained.exportPage(null, 65));
  await assert.rejects(f.store.retained.restorePage(await restore.exportPage()), {message: "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
});

test("fresh empty restore remains readable and inactive", async t => {
  const f = await fixture(t), hot = join(f.parent, "empty-restore"); await fs.mkdir(hot, {mode: 0o700}); const retained = new RetainedEvidence(hot);
  await retained.restorePage({contract_version: 1, kind: "retained_evidence_export", root_sha256: null, restored_inactive: true, entries: [], next_cursor: null});
  assert.equal(await retained.inactive(), true); assert.equal(await retained.read(`${id(1)}.checkpoint.json`), null);
  let signatures = 0, calls = 0; const signed = signedFixture();
  const outcome = await new UnattendedJournal(hot).once(signed.identity, {action: "begin_run", requestId: id(200), payload: {}},
    async (...args) => {signatures++; return signed.signer(...args);}, async (...args) => {calls++; return signed.fetcher(...args);}, signed.now);
  assert.equal(outcome.outcome, "unknown"); assert.equal(signatures, 0); assert.equal(calls, 0);
  assert.equal((await fs.readdir(hot)).length, 0);
});

for (const name of ["principal-" + "a".repeat(36) + ".lock.json", "principal-" + "-".repeat(36) + ".history-0000000001.json", "A9800000-0000-4000-8000-000000000001.outcome.json"]) {
  test(`retained names reject malformed principal or uppercase UUID ${name}`, async t => {
    const f = await fixture(t); await assert.rejects(f.store.retained.retain(name, {}));
    assert.equal(await f.store.retained.inactive(), false);
  });
}

test("existing private hot evidence under a read-only public parent remains compatible before retention", async t => {
  const f = await fixture(t); await f.store.publish(`${id(201)}.outcome.json`, {original: true}); await fs.chmod(f.parent, 0o755);
  assert.deepEqual(await f.store.read(`${id(201)}.outcome.json`), {original: true});
  await f.store.publish(`${id(202)}.outcome.json`, {next: true}); await fs.chmod(f.parent, 0o700);
});

test("automatic maintenance repeatedly recovers real control admission beyond its lifetime file ceiling", async t => {
  const f = await fixture(t), directory = join(f.directory, "control"), original = id(2000);
  const plan = operation(f, original);
  await write(directory, `${original}.checkpoint.json`, plan);
  const total = schedulerStorageLimits.control.files + 30;
  for (let start = 0; start < total; start += 100) {
    for (let n = start; n < Math.min(total, start + 100); n++) await write(directory, `${id(3000 + n)}.lookup.json`, {
      contract_version: 1, request_id: id(3000 + n), original_request_id: original, checkpoint_sha256: sha(plan), observed_at: new Date(at + n).toISOString(),
      status: "SCHEDULER_ACTIVATION_OBSERVED", host: {state: "loaded", loaded: true, disabled: false, process_running: false}});
    const maintained = await maintainSchedulerEvidence(f.deployment, at + 1_000_000); assert.equal(maintained.business_actions, 0);
    assert.ok(maintained.files_archived <= retainedPolicy.maintenance_files); assert.ok(maintained.bytes_archived <= retainedPolicy.maintenance_bytes);
    assert.equal((await schedulerStorageDiagnostics(f.deployment, at + 1_000_000)).admission_available, true);
  }
  assert.equal((await fs.readdir(directory)).length, 2);
  assert.equal((await new UnattendedStore(directory).read(`${id(3000)}.lookup.json`) as Json).status, "SCHEDULER_ACTIVATION_OBSERVED");
  await assert.rejects(new UnattendedStore(directory).publish(`${id(3000)}.lookup.json`, {}), {message: "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED"});
});

test("maintenance stays opt-in and unknown control observations remain hot", async t => {
  const f = await fixture(t); delete f.deployment.manifest.retention_policy_sha256;
  assert.equal((await maintainSchedulerEvidence(f.deployment, at)).status, "disabled");
  f.deployment.manifest.retention_policy_sha256 = retentionPolicySha256;
  const directory = join(f.directory, "control"), original = operation(f, id(9000)); await write(directory, `${id(9000)}.checkpoint.json`, original);
  for (let n = 0; n < 3; n++) await write(directory, `${id(9010 + n)}.lookup.json`, {contract_version: 1, request_id: id(9010 + n), original_request_id: id(9000),
    checkpoint_sha256: sha(original), observed_at: new Date(at + n).toISOString(), status: "SCHEDULER_OPERATION_UNKNOWN", host: {state: "unknown", loaded: null, disabled: null, process_running: null}});
  assert.equal((await maintainSchedulerEvidence(f.deployment, at + 1_000_000)).files_archived, 0);
  assert.equal((await fs.readdir(directory)).length, 4);
});

test("diagnostic partial prune joins its cold terminal and maintenance resumes without hiding unconfirmed starts", async t => {
  const f = await fixture(t); const ticks: Awaited<ReturnType<typeof beginSchedulerTickDiagnostic>>[] = [];
  for (let n = 0; n < 4; n++) {const started = await beginSchedulerTickDiagnostic(f.deployment, at + n);
    if (n !== 1) await endSchedulerTickDiagnostic(f.deployment, started, {status: "SCHEDULER_BACKOFF", business_handled: false}, at + n + 1); ticks.push(started);}
  let crash = true;
  const io: UnattendedStoreIO = {...fs, unlink: async path => {await fs.unlink(path); if (crash && String(path).endsWith(`${ticks[0]!.tick_id}.closed.json`)) {crash = false; throw Error("simulated prune crash");}}};
  await assert.rejects(maintainSchedulerEvidence(f.deployment, at + 1_000_000, {store: directory => new UnattendedStore(directory, io)}));
  const before = await schedulerStorageDiagnostics(f.deployment, at + 1_000_000); assert.equal((before.last_tick as Json).unconfirmed_count, 1);
  await maintainSchedulerEvidence(f.deployment, at + 1_000_000); assert.equal((await schedulerStorageDiagnostics(f.deployment, at + 1_000_000)).admission_available, true);
  assert.equal((await schedulerStorageDiagnostics(f.deployment, at + 1_000_000)).last_tick && ((await schedulerStorageDiagnostics(f.deployment, at + 1_000_000)).last_tick as Json).unconfirmed_count, 1);
  assert.equal((await fs.readdir(join(f.directory, "diagnostics"))).includes(`${ticks[0]!.tick_id}.run.json`), false);
});

for (const suffix of ["checkpoint", "armed", "outcome", "closed", "step", "run"]) {
  test(`journal partial prune at ${suffix} resumes the original closed group and history fence`, async t => {
    const f = await fixture(t), ids = await plans(f), first = ids[0]!, before = await new UnattendedJournal(f.journal).readOriginal(first);
    let crash = true;
    const io: UnattendedStoreIO = {...fs, unlink: async path => {await fs.unlink(path); if (crash && String(path) === join(f.journal, `${first}.${suffix}.json`)) {crash = false; throw Error("simulated prune crash");}}};
    await assert.rejects(maintainSchedulerEvidence(f.deployment, at + 1_000_000, {store: directory => new UnattendedStore(directory, io)}));
    await maintainSchedulerEvidence(f.deployment, at + 1_000_000);
    assert.equal(await historyHead(new UnattendedStore(f.journal), f.identity, at + 1_000_000), ids.at(-1));
    assert.deepEqual(await new UnattendedJournal(f.journal).readOriginal(first), before);
    for (const kind of ["checkpoint", "armed", "outcome", "closed", "step", "run"]) assert.equal((await fs.readdir(f.journal)).includes(`${first}.${kind}.json`), false);
  });
}

for (const bad of ["unknown", "expired"] as const) {
  test(`${bad} local closure with an unresolved child remains entirely hot`, async t => {
    const f = await fixture(t), ids = await plans(f, 132, bad), before = new Map<string, string>();
    for (const name of (await fs.readdir(f.journal)).filter(name => name.startsWith(ids[0]!.slice(0, -1)))) before.set(name, await fs.readFile(join(f.journal, name), "utf8"));
    await maintainSchedulerEvidence(f.deployment, at + 1_000_000);
    for (const [name, bytes] of before) assert.equal(await fs.readFile(join(f.journal, name), "utf8"), bytes);
  });
}

test("restored activation/bootstrap evidence cannot recreate tick authority", async t => {
  const f = await fixture(t), source = join(f.parent, "restore-source"); await fs.mkdir(source, {mode: 0o700}); const retained = new RetainedEvidence(source);
  const operation = {contract_version: 1, kind: "local_scheduler_operation", scope: unattendedScope, origin: "https://lhbowpbcpwoiparwnwgt.supabase.co",
    action: "activate", request_id: id(800), preparation_sha256: f.deployment.manifestSha, profile_sha256: f.deployment.manifest.profile_sha256,
    principal_id: f.identity.principalId, key_sha256: f.identity.keySha256, uid: process.getuid!(), label: "com.ikanisa.collect.receipt-operations",
    created_at: new Date(at).toISOString(), request_expires_at: new Date(at + 30000).toISOString(), actor_id: id(802), session_id: id(803), activation_request_id: null};
  f.deployment.manifest.uid = process.getuid!(); f.deployment.manifest.label = "com.ikanisa.collect.receipt-operations";
  await retained.retain(`principal-${f.identity.principalId}.lock.json`, {contract_version: 1, request_id: operation.request_id, checkpoint_sha256: sha(operation), preparation_sha256: f.deployment.manifestSha});
  await retained.retain(`${operation.request_id}.checkpoint.json`, operation);
  await retained.retain(`${operation.request_id}.step.json`, {contract_version: 1, request_id: operation.request_id, command: "bootstrap", checkpoint_sha256: sha(operation)});
  await new RetainedEvidence(join(f.directory, "control")).restorePage(await retained.exportPage());
  assert.equal(await schedulerTickPermitted(f.deployment), false);
});

const emptyRestore = {contract_version: 1, kind: "retained_evidence_export", root_sha256: null, restored_inactive: true, entries: [], next_cursor: null} as const;

test("inactive evidence rejects direct run and direct scheduler before transport or signer authority", async t => {
  const f = await fixture(t), signed = signedFixture();
  await f.store.retained.restorePage({...emptyRestore, entries: []});
  const profile: UnattendedProfile = {contract_version: 2, scope: unattendedScope, identity: signed.identity,
    helper_path: "/unavailable-reviewed-helper", helper_sha256: "a".repeat(64), journal_directory: f.journal};
  let transports = 0, runs = 0;
  const direct = await runUnattended(["--once", "--request-id", id(910), "--profile", "/synthetic-profile"], {
    profile: async () => profile, now: signed.now, transport: () => {transports++; throw Error("unexpected transport");}});
  const tick = await runSchedulerTick(["--tick", "--profile", "/synthetic-profile"], {
    profile: async () => profile, now: signed.now, run: async () => {runs++; return {};}});
  assert.equal(direct.status, "UNATTENDED_JOURNAL_UNAVAILABLE"); assert.equal(tick.status, "UNATTENDED_JOURNAL_UNAVAILABLE");
  assert.equal(transports, 0); assert.equal(runs, 0); assert.deepEqual(signed.calls(), {http: 0, rpc: 0});
});

test("restore during direct runner transport initialization permits no first operational call", async t => {
  const f = await fixture(t), signed = signedFixture();
  const profile: UnattendedProfile = {contract_version: 2, scope: unattendedScope, identity: signed.identity,
    helper_path: "/unavailable-reviewed-helper", helper_sha256: "a".repeat(64), journal_directory: f.journal};
  let calls = 0, closes = 0, next = 930;
  const direct = await runUnattended(["--once", "--request-id", id(920), "--profile", "/synthetic-profile"], {
    profile: async () => profile, now: signed.now, uuid: () => id(next++), transport: () => ({
      initialize: async () => {await f.store.retained.restorePage({...emptyRestore, entries: []});},
      call: async () => {calls++; throw Error("unexpected operational call");}, close: async () => {closes++;}})});
  assert.equal(direct.status, "UNATTENDED_JOURNAL_UNAVAILABLE"); assert.equal(calls, 0); assert.equal(closes, 1);
  assert.deepEqual(signed.calls(), {http: 0, rpc: 0});
});

test("restore during the signer await preserves its checkpoint and permits zero HTTP calls", async t => {
  const f = await fixture(t), signed = signedFixture(); let signatures = 0, calls = 0;
  const request: UnattendedRequest = {action: "begin_run", requestId: id(940), payload: {}};
  const outcome = await new UnattendedJournal(f.journal).once(signed.identity, request, async (...args) => {
    signatures++; const signature = await signed.signer(...args); await f.store.retained.restorePage({...emptyRestore, entries: []}); return signature;
  }, async (...args) => {calls++; return signed.fetcher(...args);}, signed.now);
  assert.equal(outcome.outcome, "unknown"); assert.equal(signatures, 1); assert.equal(calls, 0);
  assert.notEqual(await f.store.read(`${request.requestId}.checkpoint.json`), null);
  assert.equal((await new UnattendedJournal(f.journal).readOriginal(request.requestId)).outcome, "unknown");
});
