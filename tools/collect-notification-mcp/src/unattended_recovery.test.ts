import {test, type TestContext} from "node:test";
import assert from "node:assert/strict";
import {spawn, spawnSync} from "node:child_process";
import {once} from "node:events";
import * as fs from "node:fs/promises";
import {join} from "node:path";
import {tmpdir} from "node:os";
import {fileURLToPath} from "node:url";
import {createHash} from "node:crypto";
import {exportSchedulerRecovery, restoreSchedulerRecovery, inspectSchedulerRecovery, schedulerRecoveryPolicy} from "./unattended_recovery.ts";
import {scheduleCli, scheduleCliOptions} from "./unattended_schedule_cli.ts";
import {loadSchedulerDeployment, capturedSchedulerConfiguration, schedulerLabel} from "./unattended_deployment.ts";
import {UnattendedStore} from "./unattended_store.ts";
import {RetainedEvidence} from "./unattended_retained.ts";
import {UnattendedJournal} from "./unattended_journal.ts";
import {historyHead} from "./unattended_history.ts";
import {schedulerTickPermitted} from "./unattended_scheduler_control.ts";
import {runUnattended} from "./unattended_runner.ts";
import {runSchedulerTick} from "./unattended_scheduler.ts";
import {envelope, unattendedScope, unattendedAudience, type UnattendedRequest} from "./unattended_contract.ts";
import type {UnattendedProfile} from "./unattended_profile.ts";
import {result} from "./testing/unattended_fixture.ts";

const sha = (bytes: Uint8Array | string) => createHash("sha256").update(bytes).digest("hex");
const encoded = (value: unknown) => JSON.stringify(value) + "\n";
const id = (n: number) => `99860000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const at = Date.parse("2026-10-01T16:00:00.000Z");
const preparer = fileURLToPath(new URL("../scripts/prepare_unattended_launchd.py", import.meta.url));
async function write(directory: string, name: string, value: unknown) {await fs.writeFile(join(directory, name), encoded(value), {mode: 0o600});}
async function fixture(t: TestContext, history = false) {
  const parent = await fs.realpath(await fs.mkdtemp(join(tmpdir(), "collect-full-recovery-"))); await fs.chmod(parent, 0o700);
  t.after(() => fs.rm(parent, {recursive: true, force: true}));
  const source = join(parent, "source ' runtime"), directory = join(parent, "prepared"), journal = join(parent, "journal"), helper = join(parent, "helper"), node = join(parent, "node");
  await fs.mkdir(join(source, "src"), {recursive: true}); await fs.mkdir(join(source, "node_modules/dependency"), {recursive: true});
  await fs.writeFile(join(source, "src/unattended_host_tick.ts"), "// inert synthetic runtime\n");
  await fs.writeFile(join(source, "node_modules/dependency/runtime.js"), "// inert dependency\n");
  await fs.symlink("dependency", join(source, "node_modules/package-link"));
  await fs.writeFile(join(source, "package.json"), "{}\n"); await fs.writeFile(join(source, "pnpm-lock.yaml"), "{}\n");
  const canary = join(parent, "OPERATION_MUST_NOT_RUN");
  await fs.writeFile(helper, `#!/bin/sh\n/usr/bin/touch '${canary}'\nexit 71\n`, {mode: 0o700});
  await fs.writeFile(node, `#!/bin/sh\n/usr/bin/touch '${canary}'\nexit 79\n`, {mode: 0o700}); await fs.mkdir(journal, {mode: 0o700});
  const profile: UnattendedProfile = {contract_version: 2, scope: unattendedScope,
    identity: {principalId: id(1), keySha256: "a".repeat(64), expiresAt: "2060-01-01T00:00:00.000Z"}, helper_path: helper,
    helper_sha256: sha(await fs.readFile(helper)), journal_directory: journal};
  const profilePath = join(parent, "profile.json"); await fs.writeFile(profilePath, encoded(profile), {mode: 0o600});
  const preparation = spawnSync("/usr/bin/python3", [preparer, "--profile", profilePath, "--node", node, "--source-directory", source, "--output-directory", directory],
    {env: {PATH: "/usr/bin:/bin", LANG: "C", PYTHONUTF8: "1"}, encoding: "utf8", timeout: 10000, maxBuffer: 4096});
  assert.equal(preparation.status, 0, preparation.stderr); const deployment = await loadSchedulerDeployment(directory, false), store = new UnattendedStore(journal);
  const checkpoint = (request: UnattendedRequest) => ({contract_version: 2, scope: unattendedScope, audience: unattendedAudience, identity: profile.identity, request, created_at: new Date(at).toISOString()});
  const armed = (request: UnattendedRequest) => ({contract_version: 2, request_id: request.requestId, envelope_sha256: sha(JSON.stringify(envelope(profile.identity, request, at))),
    issued_at: new Date(at).toISOString(), not_recorded_before: new Date(at + 120000).toISOString()});
  const unknown: UnattendedRequest = {action: "begin_run", requestId: id(10), payload: {}};
  await store.publish(`${unknown.requestId}.checkpoint.json`, checkpoint(unknown)); await store.publish(`${unknown.requestId}.armed.json`, armed(unknown));
  const recorded: UnattendedRequest = {action: "begin_run", requestId: id(20), payload: {}};
  await store.publish(`${recorded.requestId}.checkpoint.json`, checkpoint(recorded)); await store.publish(`${recorded.requestId}.armed.json`, armed(recorded));
  const outcome = {contract_version: 2, scope: unattendedScope, principal_id: profile.identity.principalId, request_id: recorded.requestId, action: recorded.action,
    outcome: "recorded", reason_code: "UNATTENDED_RESULT_RECORDED", result: result(recorded, profile.identity, at), lookup_request_id: null};
  await store.publish(`${recorded.requestId}.outcome.json`, outcome);
  for (const suffix of ["checkpoint", "armed", "outcome"]) await store.archive(`${recorded.requestId}.${suffix}.json`, await store.read(`${recorded.requestId}.${suffix}.json`));
  const alias: UnattendedRequest = {action: "begin_run", requestId: id(30), payload: {}};
  const lookup: UnattendedRequest = {action: "reconcile_request", requestId: id(31), payload: {target_request_id: alias.requestId}};
  for (const request of [alias, lookup]) {await store.publish(`${request.requestId}.checkpoint.json`, checkpoint(request)); await store.publish(`${request.requestId}.armed.json`, armed(request));}
  await store.publish(`${alias.requestId}.lookup.json`, {...outcome, request_id: alias.requestId, result: result(alias, profile.identity, at), lookup_request_id: lookup.requestId});
  const plan = {contract_version: 2, scope: unattendedScope, principal_id: profile.identity.principalId, key_sha256: profile.identity.keySha256,
    request_id: unknown.requestId, created_at: new Date(at).toISOString(), request_ids: Array.from({length: 5}, (_, index) => id(10 + index)), max_events: 1};
  await store.publish(`${unknown.requestId}.run.json`, plan);
  await store.publish(`principal-${profile.identity.principalId}.lock.json`, {contract_version: 2, scope: unattendedScope, principal_id: profile.identity.principalId, key_sha256: profile.identity.keySha256, request_id: unknown.requestId});
  const activation = {contract_version: 1, kind: "local_scheduler_operation", scope: unattendedScope, origin: "https://lhbowpbcpwoiparwnwgt.supabase.co", action: "activate", request_id: id(40),
    preparation_sha256: deployment.manifestSha, profile_sha256: deployment.manifest.profile_sha256, principal_id: profile.identity.principalId, key_sha256: profile.identity.keySha256,
    uid: process.getuid!(), label: schedulerLabel, created_at: new Date(at).toISOString(), request_expires_at: new Date(at + 30000).toISOString(), actor_id: id(41), session_id: id(42), activation_request_id: null};
  const control = new UnattendedStore(join(directory, "control"));
  await control.publish(`${id(40)}.checkpoint.json`, activation);
  await control.publish(`principal-${profile.identity.principalId}.lock.json`, {contract_version: 1, request_id: id(40), checkpoint_sha256: sha(JSON.stringify(activation)), preparation_sha256: deployment.manifestSha});
  await control.publish(`${id(40)}.step.json`, {contract_version: 1, request_id: id(40), command: "bootstrap", checkpoint_sha256: sha(JSON.stringify(activation))});
  await new UnattendedStore(join(directory, "diagnostics")).publish(`${id(50)}.run.json`, {contract_version: 1, kind: "scheduler_tick_diagnostic", preparation_sha256: deployment.manifestSha,
    principal_id: profile.identity.principalId, tick_id: id(50), started_at: new Date(at).toISOString(), observed_at: new Date(at).toISOString(), phase: "started_unconfirmed", status: "TICK_STARTED_UNCONFIRMED"});
  if (history) {
    let previous = unknown.requestId;
    for (let n = 0; n < 130; n++) {
      const current = id(1000 + n * 10);
      await store.publish(`${current}.run.json`, {...plan, request_id: current, request_ids: Array.from({length: 5}, (_, index) => id(1000 + n * 10 + index))});
      await store.publish(`${previous}.closed.json`, {contract_version: 2, request_id: previous, status: "UNATTENDED_NOT_STARTED", closed_at: new Date(at + 120000).toISOString(), not_before: new Date(at + 180000).toISOString()});
      await store.publish(`${previous}.step.json`, {contract_version: 2, previous_request_id: previous, request_id: current}); previous = current;
    }
    assert.equal(await historyHead(store, profile.identity, at + 200000), previous);
  }
  return {parent, source, directory, journal, profile, profilePath, helper, canary, deployment, store, unknown, recorded, alias, lookup,
    bundle: join(parent, "bundle"), target: join(parent, "restored")};
}
async function absent(path: string) {await assert.rejects(fs.lstat(path), {code: "ENOENT"});}
async function allInactive(target: string) {for (const name of ["control", "diagnostics", "journal"]) assert.equal(await new RetainedEvidence(join(target, name)).inactive(), true);}
function cli(args: string[]) {
  const run = spawnSync(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("./unattended_schedule_cli.ts", import.meta.url)), ...args],
    {env: {PATH: "/usr/bin:/bin", LANG: "C"}, encoding: "utf8", timeout: 60000, maxBuffer: 65536});
  assert.equal(run.status, 0, run.stderr + run.stdout); return JSON.parse(run.stdout) as Record<string, unknown>;
}

test("real operating CLI round-trip preserves mixed hot/cold requests, original configuration and history while every restored store stays inactive", async t => {
  const f = await fixture(t, true), expected = new Map<string, unknown>();
  for (const name of await fs.readdir(f.journal)) expected.set(name, await f.store.read(name));
  for (const suffix of ["checkpoint", "armed", "outcome"]) expected.set(`${f.recorded.requestId}.${suffix}.json`, await f.store.read(`${f.recorded.requestId}.${suffix}.json`));
  const exported = cli(["export", "--deployment", f.directory, "--bundle", f.bundle]); assert.equal(exported.status, "SCHEDULER_RECOVERY_EXPORTED"); assert.ok(Number(exported.pages) > 1);
  assert.equal(cli(["restore", "--bundle", f.bundle, "--target", f.target]).status, "SCHEDULER_RECOVERY_RESTORED_INACTIVE"); await allInactive(f.target);
  const restored = new UnattendedStore(join(f.target, "journal")); for (const [name, value] of expected) assert.deepEqual(await restored.read(name), value);
  const context = JSON.parse(await fs.readFile(join(f.target, "context.json"), "utf8"));
  for (const config of context.configuration) assert.deepEqual(Buffer.from(config.bytes_base64, "base64"), await fs.readFile(config.source_path));
  const journal = new UnattendedJournal(restored.directory); assert.equal((await journal.readOriginal(f.unknown.requestId)).outcome, "unknown");
  assert.equal((await journal.readOriginal(f.recorded.requestId)).outcome, "recorded"); assert.equal((await journal.readOriginal(f.alias.requestId)).lookup_request_id, f.lookup.requestId);
  assert.equal(cli(["inspect", "--target", f.target, "--request-id", f.alias.requestId]).lookup_request_id, f.lookup.requestId);
  const inspected = cli(["inspect", "--target", f.target]); assert.equal(inspected.complete, true); assert.equal(inspected.restored_inactive, true); assert.ok(Number(inspected.unknown_requests) >= 2);
  assert.equal(await schedulerTickPermitted({...f.deployment, directory: f.target, manifest: {...f.deployment.manifest, journal_directory: restored.directory}}), false);
  await absent(f.canary);
});

test("actual CLI recovery dispatch invokes zero owner, signer, HTTP, transport or daemon authority", async t => {
  const f = await fixture(t); let owners = 0, daemon = 0, signatures = 0, http = 0, transports = 0;
  const deps = {owner: async () => {owners++; throw Error("forbidden");}, launchctl: async () => {daemon++; throw Error("forbidden");}};
  assert.equal((await scheduleCli(["export", "--deployment", f.directory, "--bundle", f.bundle], deps)).status, "SCHEDULER_RECOVERY_EXPORTED");
  assert.equal((await scheduleCli(["restore", "--bundle", f.bundle, "--target", f.target], deps)).status, "SCHEDULER_RECOVERY_RESTORED_INACTIVE");
  assert.equal((await scheduleCli(["inspect", "--target", f.target], deps)).status, "SCHEDULER_RECOVERY_INSPECTED_INACTIVE");
  const targetJournal = join(f.target, "journal"), profile = {...f.profile, journal_directory: targetJournal};
  const result = await new UnattendedJournal(targetJournal).once(profile.identity, f.unknown,
    async () => {signatures++; throw Error("forbidden");}, async () => {http++; throw Error("forbidden");}); assert.equal(result.outcome, "unknown");
  const transport = () => {transports++; throw Error("forbidden");};
  await runUnattended(["--once", "--profile", f.profilePath, "--request-id", id(70)], {profile: async () => profile, transport});
  await runSchedulerTick(["--profile", f.profilePath], {profile: async () => profile, run: async () => {transports++; throw Error("forbidden");}});
  assert.deepEqual([owners, daemon, signatures, http, transports], [0, 0, 0, 0, 0]); await absent(f.canary);
});

test("inactive recovery inspection and original UUID lookup survive removal of all original configuration and runtime paths", async t => {
  const f = await fixture(t); assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORED_INACTIVE");
  for (const path of [f.directory, f.source, f.journal, f.journal + ".retained", f.helper, f.profilePath, join(f.parent, "node")]) await fs.rm(path, {recursive: true, force: true});
  assert.equal(cli(["inspect", "--target", f.target]).complete, true);
  assert.equal(cli(["inspect", "--target", f.target, "--request-id", f.recorded.requestId]).outcome, "recorded");
  assert.equal(cli(["inspect", "--target", f.target, "--request-id", f.unknown.requestId]).outcome, "unknown"); await allInactive(f.target); await absent(f.canary);
});

test("killed importer leaves durable inactive mappings and original evidence without a completion seal", async t => {
  const f = await fixture(t); assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  const module = new URL("./unattended_recovery.ts", import.meta.url).href;
  const source = `import {restoreSchedulerRecovery} from ${JSON.stringify(module)};
await restoreSchedulerRecovery(${JSON.stringify(f.bundle)},${JSON.stringify(f.target)}, {hook: async stage => {
if(stage === "record_imported") {process.stdout.write("DURABLE\\n");await new Promise(()=>{});}
}});`;
  const child = spawn(process.execPath, ["--experimental-strip-types", "--input-type=module", "-e", source],
    {stdio: ["ignore", "pipe", "pipe"], env: {PATH: "/usr/bin:/bin", LANG: "C"}});
  let stderr = ""; child.stderr.on("data", data => {stderr += data;});
  await Promise.race([once(child.stdout, "data"), once(child, "exit").then(() => {throw Error(stderr);}),
    new Promise((_, reject) => {const timeout = setTimeout(() => reject(Error("import checkpoint deadline")), 30000); timeout.unref();})]);
  const ended = once(child, "close"); child.kill("SIGKILL"); await ended;
  await allInactive(f.target); await absent(join(f.target, "COMPLETE.json")); const inspected = await inspectSchedulerRecovery(f.target);
  assert.equal(inspected.complete, false); assert.equal(inspected.restored_inactive, true); await absent(f.canary);
});

for (const stage of ["stores_inactive", "record_imported"] as const) test(`interrupted ${stage} import keeps all stores inactive and refuses a completion claim`, async t => {
  const f = await fixture(t); assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  const restored = await restoreSchedulerRecovery(f.bundle, f.target, {hook: async current => {if (current === stage) throw Error("injected interruption");}});
  assert.equal(restored.status, "SCHEDULER_RECOVERY_RESTORE_REFUSED"); await allInactive(f.target); await absent(join(f.target, "COMPLETE.json"));
  const inspected = await inspectSchedulerRecovery(f.target); assert.equal(inspected.complete, false); assert.equal(inspected.restored_inactive, true);
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORE_REFUSED");
});

for (const drift of ["publication", "transient-record", "helper", "dependency-link", "new-runtime-file", "same-root", "compaction"] as const) test(`source ${drift} drift refuses an export seal and keeps the failed proof`, async t => {
  const f = await fixture(t); let changed = false;
  const exported = await exportSchedulerRecovery(f.directory, f.bundle, {hook: async stage => {
    if (stage !== "source_captured" || changed) return; changed = true;
    if (drift === "publication") await f.store.publish(`${id(80)}.outcome.json`, {contract_version: 2, request_id: id(80), outcome: "unknown"});
    if (drift === "transient-record") {const path = join(f.journal, `${f.unknown.requestId}.checkpoint.json`), original = await fs.readFile(path);
      await write(f.journal, `${f.unknown.requestId}.checkpoint.json`, {different: "transient"}); await fs.writeFile(path, original, {mode: 0o600});}
    if (drift === "helper") await fs.writeFile(f.helper, "// changed helper\n", {mode: 0o700});
    if (drift === "dependency-link") {await fs.unlink(join(f.source, "node_modules/package-link")); await fs.symlink("./dependency", join(f.source, "node_modules/package-link"));}
    if (drift === "new-runtime-file") await fs.writeFile(join(f.source, "src/new-module.ts"), "// unpinned new input\n");
    if (drift === "same-root") {const path = join(f.store.retained.directory, "head.json"), original = await fs.readFile(path); await fs.writeFile(path, original, {mode: 0o600});}
    if (drift === "compaction") await f.store.retained.retain(`${id(81)}.outcome.json`, {new: "cold member"});
  }});
  assert.notEqual(exported.status, "SCHEDULER_RECOVERY_EXPORTED"); assert.equal(exported.complete, false); await absent(join(f.bundle, "seal.json"));
  assert.equal(JSON.parse(await fs.readFile(join(f.bundle, "FAILED.json"), "utf8")).status, "SCHEDULER_RECOVERY_EXPORT_INCOMPLETE");
});

for (const defect of ["missing-page", "reordered-page", "duplicate-entry", "conflicting-hot-cold", "extra-page", "missing-seal"] as const) test(`${defect} cannot receive a complete restore`, async t => {
  const f = await fixture(t); assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  const path = join(f.bundle, "page-00000001.json"), page = JSON.parse(await fs.readFile(path, "utf8"));
  if (defect === "missing-page") await fs.unlink(path);
  if (defect === "reordered-page") {page.sequence = 2; await write(f.bundle, "page-00000001.json", page);}
  if (defect === "duplicate-entry") {page.entries.splice(1, 0, page.entries[0]); await write(f.bundle, "page-00000001.json", page);}
  if (defect === "conflicting-hot-cold") {const entry = page.entries.find((entry: {tier: string}) => entry.tier === "hot"); entry.value = {conflicting: true}; entry.bytes_sha256 = sha(encoded(entry.value)); await write(f.bundle, "page-00000001.json", page);}
  if (defect === "extra-page") await write(f.bundle, "page-00000002.json", page);
  if (defect === "missing-seal") await fs.unlink(join(f.bundle, "seal.json"));
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORE_REFUSED"); await absent(join(f.target, "COMPLETE.json"));
  if (["reordered-page", "duplicate-entry", "conflicting-hot-cold"].includes(defect)) await allInactive(f.target);
});

test("exact duplicate hot/cold bytes retain both source tiers while divergent bytes refuse export", async t => {
  const f = await fixture(t), name = `${f.recorded.requestId}.outcome.json`, value = await f.store.read(name);
  await write(f.journal, name, value); assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORED_INACTIVE"); assert.deepEqual(await new UnattendedStore(join(f.target, "journal")).read(name), value);
  const pages = JSON.parse(await fs.readFile(join(f.bundle, "page-00000001.json"), "utf8")); assert.deepEqual(pages.entries.filter((entry: {name: string}) => entry.name === name).map((entry: {tier: string}) => entry.tier).sort(), ["cold", "hot"]);
  await write(f.journal, name, {different: true}); assert.notEqual((await exportSchedulerRecovery(f.directory, join(f.parent, "conflict-bundle"))).status, "SCHEDULER_RECOVERY_EXPORTED");
});

test("canonical malformed and orphan evidence is preserved and reported without repairing original claims", async t => {
  const f = await fixture(t); await f.store.publish(`${id(90)}.checkpoint.json`, {contract_version: 2, incomplete: true});
  await f.store.publish(`${id(91)}.armed.json`, {original_unknown: true});
  assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORED_INACTIVE");
  const store = new UnattendedStore(join(f.target, "journal")); assert.deepEqual(await store.read(`${id(91)}.armed.json`), {original_unknown: true});
  assert.ok(Number((await inspectSchedulerRecovery(f.target)).integrity_required_requests) >= 1); await absent(`${store.directory}/${id(91)}.checkpoint.json`);
});

test("configuration bytes stay inert and historical UID metadata cannot become a live Deployment", async t => {
  const f = await fixture(t), manifest = JSON.parse(await fs.readFile(join(f.directory, "PREPARATION.json"), "utf8"));
  manifest.uid += 1; const artifacts = Object.fromEntries(await Promise.all(Object.keys(manifest.artifacts).map(async name => [name, await fs.readFile(join(f.directory, name))])));
  const captured = capturedSchedulerConfiguration(f.directory, Buffer.from(JSON.stringify(manifest)), await fs.readFile(f.profilePath), artifacts);
  assert.equal(captured.kind, "inert_scheduler_configuration"); assert.equal("directory" in captured, false);
  await fs.writeFile(join(f.directory, "PREPARATION.json"), JSON.stringify(manifest), {mode: 0o600}); await assert.rejects(loadSchedulerDeployment(f.directory, false));
});

test("captured and active configuration share retained-policy and runtime/dependency layout rejection despite matching forged artifacts", async t => {
  const f = await fixture(t), originalManifest = await fs.readFile(join(f.directory, "PREPARATION.json")), profile = await fs.readFile(f.profilePath);
  const base = JSON.parse(originalManifest.toString("utf8"));
  const originalArtifacts: Record<string, Buffer> = Object.fromEntries(await Promise.all(Object.keys(base.artifacts).map(async name => [name, await fs.readFile(join(f.directory, name))])));
  const quote = (text: string) => /^[A-Za-z0-9_@%+=:,./-]+$/.test(text) ? text : `'${text.replaceAll("'", "'\"'\"'")}'`;
  for (const defect of ["retention-policy", "required-input", "outside-runtime", "newline-runtime", "outside-link", "newline-link", "profile-input", "link-input-overlap", "command-link"]) {
    const value = JSON.parse(originalManifest.toString("utf8")), artifacts = {...originalArtifacts};
    if (defect === "retention-policy") value.retention_policy_sha256 = "f".repeat(64);
    if (defect === "required-input") delete value.runtime_inputs[join(f.source, "src/unattended_host_tick.ts")];
    if (defect === "outside-runtime") value.runtime_inputs[join(f.parent, "outside-runtime.ts")] = "c".repeat(64);
    if (defect === "newline-runtime") value.runtime_inputs[join(f.source, "src/module\npath.ts")] = "c".repeat(64);
    if (defect === "profile-input") value.runtime_inputs[f.profilePath] = "c".repeat(64);
    if (defect === "link-input-overlap") value.runtime_inputs[Object.keys(value.dependency_links)[0]!] = "c".repeat(64);
    const link = defect === "outside-link" ? join(f.parent, "outside-package") : defect === "newline-link" ? join(f.source, "node_modules/new\npackage-link") :
      defect === "command-link" ? join(f.source, "node_modules/.bin/unused") : null;
    if (link) {
      value.dependency_links[link] = "dependency";
      const wrapper = artifacts["tick.sh"]!.toString("utf8"), effect = wrapper.lastIndexOf("exec /usr/bin/env");
      artifacts["tick.sh"] = Buffer.from(wrapper.slice(0, effect) + `[ "$(/usr/bin/env -i PATH=/usr/bin:/bin LANG=C /usr/bin/readlink ${quote(link)})" = dependency ] || exit 78\n` + wrapper.slice(effect));
    }
    artifacts["runtime.sha256"] = Buffer.from(Object.entries(value.runtime_inputs).map(([path, digest]) => `${digest}  ${path}\n`).join(""));
    for (const [name, bytes] of Object.entries(artifacts)) value.artifacts[name] = sha(bytes);
    // Artifact bytes intentionally agree with the changed manifest. Rejection
    // therefore establishes the metadata/layout contract, not stale sums.
    assert.throws(() => capturedSchedulerConfiguration(f.directory, Buffer.from(JSON.stringify(value)), profile, artifacts), {message: "SCHEDULER_RECOVERY_CONFIGURATION_UNVERIFIED"}, defect);
    await fs.writeFile(join(f.directory, "PREPARATION.json"), JSON.stringify(value), {mode: 0o600});
    for (const [name, bytes] of Object.entries(artifacts)) await fs.writeFile(join(f.directory, name), bytes, {mode: 0o600});
    await assert.rejects(loadSchedulerDeployment(f.directory, false), {message: "SCHEDULER_DEPLOYMENT_UNVERIFIED"}, defect);
  }
});

test("credential field screening normalizes common key names while public key metadata and noncredential anomalies remain recoverable", async t => {
  const f = await fixture(t), name = `${id(93)}.outcome.json`;
  for (const marker of ["api_key", "API-Key", "apiKey", "client_secret", "CLIENT.SECRET", "service_role_key", "ServiceRoleKey", "signing_key", "Signing Key", "PRIVATE_KEY", "accessToken", "refresh-token", "Authorization", "signature"]) {
    await f.store.publish(name, {malformed_noncredential_record: true, nested: {[marker]: "PRIVATE_MARKER_CANARY"}});
    const refused = await exportSchedulerRecovery(f.directory, join(f.parent, "refused-marker-bundle"));
    assert.equal(refused.status, "SCHEDULER_RECOVERY_EXPORT_REFUSED", marker); assert.equal(JSON.stringify(refused).includes("PRIVATE_MARKER_CANARY"), false);
    await fs.unlink(join(f.journal, name));
  }
  const metadata = {key_sha256: "d".repeat(64), keySha256: "e".repeat(64), key_tag_id: id(94), signature_sha256: "f".repeat(64), orphan_noncredential_record: true};
  await f.store.publish(name, metadata);
  assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORED_INACTIVE");
  assert.deepEqual(await new UnattendedStore(join(f.target, "journal")).read(name), metadata);
  assert.ok(Number((await inspectSchedulerRecovery(f.target)).integrity_required_requests) >= 1);
});

test("invalid names, credential fields, target overlap, occupied targets and symlinks refuse local recovery", async t => {
  const f = await fixture(t); await fs.writeFile(join(f.journal, "unexpected.txt"), "private", {mode: 0o600});
  assert.notEqual((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED"); await fs.unlink(join(f.journal, "unexpected.txt"));
  await f.store.publish(`${id(92)}.outcome.json`, {access_token: "PRIVATE_CANARY"});
  const refused = await scheduleCli(["export", "--deployment", f.directory, "--bundle", f.bundle]); assert.equal(JSON.stringify(refused).includes("PRIVATE_CANARY"), false); await fs.unlink(join(f.journal, `${id(92)}.outcome.json`));
  assert.equal((await exportSchedulerRecovery(f.directory, f.bundle)).status, "SCHEDULER_RECOVERY_EXPORTED");
  assert.equal((await restoreSchedulerRecovery(f.bundle, f.journal)).status, "SCHEDULER_RECOVERY_RESTORE_REFUSED");
  await fs.symlink(f.journal, f.target); assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORE_REFUSED");
  await fs.unlink(f.target); await fs.mkdir(f.target, {mode: 0o700}); assert.equal((await restoreSchedulerRecovery(f.bundle, f.target)).status, "SCHEDULER_RECOVERY_RESTORE_REFUSED");
});

test("recovery parser and page bounds remain explicit and reject authority flags", async () => {
  assert.equal(scheduleCliOptions(["restore", "--bundle", "/private/bundle", "--target", "/private/target"]).command, "restore");
  for (const args of [["export", "--deployment", "/private/source"], ["restore", "--bundle", "/private/bundle", "--target", "relative"],
    ["inspect", "--target", "/private/target", "--activate", "yes"], ["restore", "--bundle", "/private/bundle", "--target", "/private/target", "--request-id", id(3)]]) assert.throws(() => scheduleCliOptions(args));
  assert.equal(schedulerRecoveryPolicy.page_entries, 64); assert.equal(schedulerRecoveryPolicy.page_bytes, 4194304);
});
