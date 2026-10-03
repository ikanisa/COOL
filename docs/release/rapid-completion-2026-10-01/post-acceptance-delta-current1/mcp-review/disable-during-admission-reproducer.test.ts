import {test} from "node:test";
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import * as filesystem from "node:fs/promises";
import {mkdtemp, realpath, mkdir, writeFile, readFile, chmod, rm, symlink, unlink, link, open, readdir} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {sha256} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_enrollment_contract.ts";
import type {Json} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_contract.ts";
import {signedFixture} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/testing/unattended_fixture.ts";
import {runSchedulerTick} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_scheduler.ts";
import {UnattendedStore} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_store.ts";
import {UnattendedJournal} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_journal.ts";
import type {UnattendedRequest, UnattendedIdentity} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_contract.ts";
import type {UnattendedProfile} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_profile.ts";
import {loadSchedulerDeployment, schedulerLabel, type Deployment} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_deployment.ts";
import {controlScheduler, projectHostObservation, schedulerTickPermitted, type Launchctl, type LaunchctlResult, type ControlDependencies} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_scheduler_control.ts";
import {runPreparedSchedulerTick} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_host_tick.ts";
import {scheduleCli, scheduleCliOptions} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_schedule_cli.ts";
import {schedulerStorageDiagnostics, schedulerStorageLimits, beginSchedulerTickDiagnostic, endSchedulerTickDiagnostic, finiteSchedulerTickProjection} from "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/src/unattended_scheduler_storage.ts";

const id = (n: number) => `99850000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const at = Date.parse("2026-10-01T16:00:00.000Z"), expiry = "2060-01-01T00:00:00.000Z";
const preparer = "/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-post-acceptance-review-20261001-current1/tools/collect-notification-mcp/scripts/prepare_unattended_launchd.py";
const ok = (stdout = ""): LaunchctlResult => ({code: 0, uncertain: false, stdout, stderr: ""});
const absent = (): LaunchctlResult => ({code: 113, uncertain: false, stdout: "", stderr: `Could not find service "${schedulerLabel}" in domain for user gui: ${process.getuid!()}`});

/** Real private filesystem + actual Python preparer; synthetic executable,
 * owner observations and launchctl seam. No Keychain/Auth/host daemon calls. */
async function fixture(identityExpires = expiry, identity?: UnattendedIdentity) {
  const parent = await realpath(await mkdtemp(join(tmpdir(), "collect-host-controls-")));
  const source = join(parent, "source with ' spaces"), directory = join(parent, "prepared"), profilePath = join(parent, "profile.json"), helper = join(parent, "helper"), node = join(parent, "synthetic-node");
  await mkdir(join(source, "src"), {recursive: true}); await mkdir(join(source, "node_modules/dependency"), {recursive: true});
  await writeFile(join(source, "src/unattended_host_tick.ts"), "// synthetic module binding only\n");
  await writeFile(join(source, "node_modules/dependency/runtime.js"), "// synthetic dependency\n");
  await symlink("dependency", join(source, "node_modules/package-link"));
  await writeFile(join(source, "package.json"), "{}\n"); await writeFile(join(source, "pnpm-lock.yaml"), "{}\n");
  await writeFile(node, "#!/bin/sh\nexit 79\n", {mode: 0o700}); await writeFile(helper, "#!/bin/sh\nexit 71\n", {mode: 0o700});
  const journal = join(parent, "journal"); await mkdir(journal, {mode: 0o700});
  const profile: UnattendedProfile = {contract_version: 2, scope: "rw_receipt_operations", identity: identity ?? {principalId: id(9), keySha256: "a".repeat(64), expiresAt: identityExpires},
    helper_path: helper, helper_sha256: sha256(await readFile(helper)), journal_directory: journal};
  await writeFile(profilePath, JSON.stringify(profile) + "\n", {mode: 0o600});
  const preparation = spawnSync("/usr/bin/python3", [preparer, "--profile", profilePath, "--node", node, "--source-directory", source, "--output-directory", directory],
    {env: {PATH: "/usr/bin:/bin", LANG: "C", PYTHONUTF8: "1"}, encoding: "utf8", timeout: 10000, maxBuffer: 4096});
  assert.equal(preparation.status, 0, "synthetic preparation must complete");
  const deployment = await loadSchedulerDeployment(directory, true);
  let loaded = false, disabled = false, clock = at, ownerCalls = 0;
  const commands: string[][] = [];
  const print = () => ok(`gui/${process.getuid!()}/${schedulerLabel} = {\n path = ${join(directory, `${schedulerLabel}.plist`)}\n type = LaunchAgent\n state = not running\n program = /bin/sh\n arguments = {\n /bin/sh\n ${join(directory, "tick.sh")}\n }\n}\n`);
  let transform: ((args: readonly string[], result: LaunchctlResult) => Promise<LaunchctlResult> | LaunchctlResult) | undefined;
  const launchctl: Launchctl = async args => {
    commands.push([...args]); let result = ok();
    if (args[0] === "print") result = loaded ? print() : absent();
    if (args[0] === "print-disabled") result = ok(`disabled services = {\n "${schedulerLabel}" => ${disabled}\n}\n`);
    if (args[0] === "enable") disabled = false;
    if (args[0] === "bootstrap") loaded = true;
    if (args[0] === "disable") disabled = true;
    if (args[0] === "bootout") loaded = false;
    return transform ? await transform(args, result) : result;
  };
  const owner = async (current: Deployment) => {ownerCalls++; return {actor_id: id(20), session_id: id(21), profile_sha256: current.manifest.profile_sha256,
    helper_sha256: current.manifest.helper_sha256, principal_id: profile.identity.principalId, key_sha256: profile.identity.keySha256,
    identity_expires_at: profile.identity.expiresAt, checked_at: new Date(clock).toISOString(), sample_valid_until: new Date(clock + 60000).toISOString()};};
  const executionBinding = async (current: Deployment) => {assert.equal(current.manifest.source_directory, source); assert.equal(current.manifest.node_path, node);};
  const dependencies: ControlDependencies = {launchctl, owner, executionBinding, now: () => clock};
  return {parent, directory, source, node, helper, profilePath, deployment, profile, dependencies, executionBinding, commands, print,
    owners: () => ownerCalls, time: (value: number) => {clock = value;}, state: (active: boolean, stop: boolean) => {loaded = active; disabled = stop;},
    patch: (fn: typeof transform) => {transform = fn;}, cleanup: () => rm(parent, {recursive: true, force: true})};
}

// Existing private filesystem/launchctl seams only. No production mutation.
test("durable local disable during admission prevents a subsequent runner invocation", async () => {
  const f = await fixture();
  let release!: () => void, entered!: () => void;
  const held = new Promise<void>(resolve => {release = resolve;});
  const reached = new Promise<void>(resolve => {entered = resolve;});
  let calls = 0;
  try {
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_ACTIVATION_OBSERVED");
    const pending = runPreparedSchedulerTick(["--deployment", f.directory], {
      executionBinding: f.executionBinding, now: () => at,
      storage: {io: {...filesystem, statfs: async path => {entered(); await held; return await filesystem.statfs(path);}}},
      tick: async () => {calls++; return {status: "SCHEDULER_BACKOFF", business_handled: false};},
    });
    await reached;
    assert.equal((await controlScheduler("disable", f.directory, id(2), undefined, f.dependencies)).status, "SCHEDULER_DISABLE_OBSERVED");
    assert.equal(await schedulerTickPermitted(f.deployment), false);
    release(); const result = await pending;
    console.log(JSON.stringify({runner_calls_after_durable_disable: calls, status: result.status, local_tick_permitted: await schedulerTickPermitted(f.deployment)}));
    assert.equal(calls, 0, "a tick must recheck the durable disabled latch after admission awaits");
  } finally {release(); await f.cleanup();}
});
