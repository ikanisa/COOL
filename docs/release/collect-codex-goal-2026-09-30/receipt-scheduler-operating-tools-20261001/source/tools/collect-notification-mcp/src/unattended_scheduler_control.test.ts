import {test} from "node:test";
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtemp, realpath, mkdir, writeFile, readFile, chmod, rm, symlink, unlink, link} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {sha256} from "./unattended_enrollment_contract.ts";
import {loadSchedulerDeployment, schedulerLabel, type Deployment} from "./unattended_deployment.ts";
import {controlScheduler, projectHostObservation, schedulerTickPermitted, type Launchctl, type LaunchctlResult, type ControlDependencies} from "./unattended_scheduler_control.ts";
import {runPreparedSchedulerTick} from "./unattended_host_tick.ts";
import {scheduleCli, scheduleCliOptions} from "./unattended_schedule_cli.ts";

const id = (n: number) => `99850000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const at = Date.parse("2026-10-01T16:00:00.000Z"), expiry = "2060-01-01T00:00:00.000Z";
const preparer = fileURLToPath(new URL("../scripts/prepare_unattended_launchd.py", import.meta.url));
const ok = (stdout = ""): LaunchctlResult => ({code: 0, uncertain: false, stdout, stderr: ""});
const absent = (): LaunchctlResult => ({code: 113, uncertain: false, stdout: "", stderr: `Could not find service "${schedulerLabel}" in domain for user gui: ${process.getuid!()}`});

/** Real private filesystem + actual Python preparer; synthetic executable,
 * owner observations and launchctl seam. No Keychain/Auth/host daemon calls. */
async function fixture(identityExpires = expiry) {
  const parent = await realpath(await mkdtemp(join(tmpdir(), "collect-host-controls-")));
  const source = join(parent, "source with ' spaces"), directory = join(parent, "prepared"), profilePath = join(parent, "profile.json"), helper = join(parent, "helper"), node = join(parent, "synthetic-node");
  await mkdir(join(source, "src"), {recursive: true}); await mkdir(join(source, "node_modules/dependency"), {recursive: true});
  await writeFile(join(source, "src/unattended_host_tick.ts"), "// synthetic module binding only\n");
  await writeFile(join(source, "node_modules/dependency/runtime.js"), "// synthetic dependency\n");
  await symlink("dependency", join(source, "node_modules/package-link"));
  await writeFile(join(source, "package.json"), "{}\n"); await writeFile(join(source, "pnpm-lock.yaml"), "{}\n");
  await writeFile(node, "#!/bin/sh\nexit 79\n", {mode: 0o700}); await writeFile(helper, "#!/bin/sh\nexit 71\n", {mode: 0o700});
  const journal = join(parent, "journal"); await mkdir(journal, {mode: 0o700});
  const profile = {contract_version: 2, scope: "rw_receipt_operations", identity: {principalId: id(9), keySha256: "a".repeat(64), expiresAt: identityExpires},
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
const mutations = (calls: readonly string[][]) => calls.filter(args => ["enable", "bootstrap", "disable", "bootout"].includes(args[0]!));

for (const args of [[], ["activate"], ["activate", "--deployment", "relative", "--request-id", id(1)], ["status", "--deployment", "/p", "--request-id", id(1)],
  ["activate", "--deployment", "/p", "--request-id", "PRIVATE_CREDENTIAL_CANARY"], ["activate", "--deployment", "/p", "--request-id", id(1), "--url", "https://other.invalid"],
  ["reconcile", "--deployment", "/p", "--request-id", id(1), "--lookup-id", id(1)], ["prepare", "--deployment", "/p", "--profile", "/p", "--max-events", "11"],
  ["prepare", "--deployment", "/p", "--profile", "/p", "--interval-seconds", "59"], ["status", "--deployment", "/p", "--deployment", "/q"]]) {
  test(`scheduler operating CLI invalid input refuses before side effects ${JSON.stringify(args)}`, async () => {
    let calls = 0; const result = await scheduleCli(args, {launchctl: async () => {calls++; return ok();}, prepare: async () => {calls++; return {};}});
    assert.equal(calls, 0); assert.equal(JSON.stringify(result).includes("PRIVATE_CREDENTIAL_CANARY"), false);
  });
}
test("scheduler prepare parser is bounded and never implies activation", async () => {
  const args = ["prepare", "--deployment", "/private/new-deployment", "--profile", "/private/profile"];
  assert.equal(scheduleCliOptions(args).intervalSeconds, 60); assert.equal(scheduleCliOptions(args).maxEvents, 5);
  let controlCalls = 0; const result = await scheduleCli(args, {prepare: async () => ({status: "SCHEDULER_PREPARED_INACTIVE", installed: false, started: false}),
    launchctl: async () => {controlCalls++; return ok();}});
  assert.equal(result.started, false); assert.equal(controlCalls, 0);
});
test("real preparation is inactive and gated tick performs no operation before explicit activation", async () => {
  const f = await fixture(); try {
    let ticks = 0;
    const result = await runPreparedSchedulerTick(["--deployment", f.directory], {executionBinding: f.executionBinding, now: () => at, tick: async () => {ticks++; return {};}});
    assert.equal(result.status, "SCHEDULER_LOCAL_INACTIVE"); assert.equal(ticks, 0); assert.equal(f.owners(), 0); assert.equal(f.commands.length, 0);
    assert.equal((await controlScheduler("status", f.directory, undefined, undefined, f.dependencies)).status, "SCHEDULER_PREPARED_INACTIVE");
    assert.equal(mutations(f.commands).length, 0); assert.equal(f.owners(), 0);
  } finally {await f.cleanup();}
});
test("explicit activation validates fresh owner and records original before each exact launchctl command", async () => {
  const f = await fixture(); try {
    f.patch(async (args, result) => {
      if (["enable", "bootstrap"].includes(args[0]!)) {
        const original = JSON.parse(await readFile(join(f.directory, "control", `${id(1)}.checkpoint.json`), "utf8"));
        assert.equal(original.request_id, id(1)); assert.equal(original.actor_id, id(20)); assert.equal(original.session_id, id(21));
        const armed = JSON.parse(await readFile(join(f.directory, "control", `${id(1)}.${args[0] === "enable" ? "armed" : "step"}.json`), "utf8"));
        assert.equal(armed.checkpoint_sha256, sha256(JSON.stringify(original)));
      }
      return result;
    });
    const result = await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    assert.equal(result.status, "SCHEDULER_ACTIVATION_OBSERVED"); assert.equal(result.cadence_verified, false); assert.equal(f.owners(), 1);
    assert.deepEqual(mutations(f.commands), [["enable", `gui/${process.getuid!()}/${schedulerLabel}`], ["bootstrap", `gui/${process.getuid!()}`, join(f.directory, `${schedulerLabel}.plist`)]]);
    let ticks = 0;
    const tick = await runPreparedSchedulerTick(["--deployment", f.directory], {executionBinding: f.executionBinding, now: () => at,
      tick: async args => {ticks++; assert.deepEqual(args, ["--tick", "--profile", f.profilePath, "--interval-seconds", "60", "--max-events", "5"]); return {status: "SCHEDULER_BACKOFF"};}});
    assert.equal(tick.status, "SCHEDULER_BACKOFF"); assert.equal(ticks, 1); assert.equal(f.owners(), 1, "unattended tick must not load owner credentials");
  } finally {await f.cleanup();}
});
test("default current source/Node binding refuses another private prepared runtime", async () => {
  const f = await fixture(); try {
    const {executionBinding: _, ...dependencies} = f.dependencies;
    const result = await controlScheduler("activate", f.directory, id(1), undefined, dependencies);
    assert.equal(result.status, "SCHEDULER_EXECUTION_BINDING_REQUIRED"); assert.equal(mutations(f.commands).length, 0); assert.equal(f.owners(), 0);
  } finally {await f.cleanup();}
});
test("unknown bootstrap is manually reconciled from exact job, never replayed", async () => {
  const f = await fixture(); try {
    f.patch((args, result) => {if (args[0] === "bootstrap") throw Error("PRIVATE_DAEMON_CANARY"); return result;});
    const unknown = await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    assert.equal(unknown.status, "SCHEDULER_OPERATION_UNKNOWN"); assert.equal(JSON.stringify(unknown).includes("PRIVATE_DAEMON_CANARY"), false);
    f.patch(undefined);
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
    assert.equal((await controlScheduler("reconcile", f.directory, id(1), id(2), f.dependencies)).status, "SCHEDULER_ACTIVATION_OBSERVED");
    assert.equal(mutations(f.commands).filter(args => args[0] === "bootstrap").length, 1);
    assert.equal(JSON.parse(await readFile(join(f.directory, "control", `${id(2)}.lookup.json`), "utf8")).original_request_id, id(1));
  } finally {await f.cleanup();}
});
test("unknown enable with absent job stays unknown and cannot acquire bootstrap authority", async () => {
  const f = await fixture(); try {
    f.patch((args, result) => {if (args[0] === "enable") throw Error("uncertain"); return result;});
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    f.patch(undefined);
    assert.equal((await controlScheduler("reconcile", f.directory, id(1), id(2), f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal(await schedulerTickPermitted(f.deployment), false); assert.equal(mutations(f.commands).length, 1);
    assert.equal((await controlScheduler("activate", f.directory, id(3), undefined, f.dependencies)).status, "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
  } finally {await f.cleanup();}
});
test("concurrent activation originals have one exclusive claim and one daemon mutation sequence", async () => {
  const f = await fixture(); try {
    const results = await Promise.all([controlScheduler("activate", f.directory, id(1), undefined, f.dependencies), controlScheduler("activate", f.directory, id(2), undefined, f.dependencies)]);
    assert.equal(results.filter(result => result.status === "SCHEDULER_ACTIVATION_OBSERVED").length, 1);
    assert.equal(mutations(f.commands).filter(args => args[0] === "bootstrap").length, 1);
  } finally {await f.cleanup();}
});
test("urgent disable racing activation prevents the later bootstrap", async () => {
  const f = await fixture(); try {
    f.patch(async (args, result) => {
      if (args[0] === "enable") assert.equal((await controlScheduler("disable", f.directory, id(2), undefined, f.dependencies)).status, "SCHEDULER_DISABLE_OBSERVED");
      return result;
    });
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal(mutations(f.commands).filter(args => args[0] === "bootstrap").length, 0);
    assert.equal(await schedulerTickPermitted(f.deployment), false);
  } finally {await f.cleanup();}
});
test("original operation deadline is rechecked after enable and never extended", async () => {
  const f = await fixture(); try {
    f.patch((args, result) => {if (args[0] === "enable") f.time(at + 30000); return result;});
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal(mutations(f.commands).filter(args => args[0] === "bootstrap").length, 0);
    assert.equal(await schedulerTickPermitted(f.deployment), false);
    const original = JSON.parse(await readFile(join(f.directory, "control", `${id(1)}.checkpoint.json`), "utf8"));
    assert.equal(original.request_expires_at, new Date(at + 30000).toISOString());
  } finally {await f.cleanup();}
});
test("failed exclusive bootstrap journal publication permits no daemon bootstrap", async () => {
  const f = await fixture(); try {
    f.patch(async (args, result) => {if (args[0] === "enable") await mkdir(join(f.directory, "control", `${id(1)}.step.json`), {mode: 0o700}); return result;});
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal(mutations(f.commands).filter(args => args[0] === "bootstrap").length, 0);
  } finally {await f.cleanup();}
});
test("disable latches before IPC, survives uncertain bootout and remains manually reconcilable", async () => {
  const f = await fixture(); try {
    await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    f.patch(async (args, result) => {
      if (args[0] === "disable") assert.equal(await schedulerTickPermitted(f.deployment), false);
      if (args[0] === "bootout") throw Error("PRIVATE_BOOTOUT_CANARY"); return result;
    });
    const result = await controlScheduler("disable", f.directory, id(2), undefined, f.dependencies);
    assert.equal(result.status, "SCHEDULER_OPERATION_UNKNOWN"); assert.equal(await schedulerTickPermitted(f.deployment), false);
    f.patch(undefined);
    assert.equal((await controlScheduler("reconcile", f.directory, id(2), id(3), f.dependencies)).status, "SCHEDULER_DISABLE_OBSERVED");
    assert.equal((await controlScheduler("disable", f.directory, id(4), undefined, f.dependencies)).status, "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
    assert.equal((await controlScheduler("activate", f.directory, id(5), undefined, f.dependencies)).status, "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
    assert.equal(mutations(f.commands).filter(args => args[0] === "bootout").length, 1); assert.equal(f.owners(), 1);
  } finally {await f.cleanup();}
});
test("local disabled latch does not falsely prove a loaded process was stopped", async () => {
  const f = await fixture(); try {
    await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    f.patch((args, result) => {if (args[0] === "bootout") {f.state(true, true); return {code: null, uncertain: true, stdout: "PRIVATE", stderr: "PRIVATE"};} return result;});
    assert.equal((await controlScheduler("disable", f.directory, id(2), undefined, f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    f.patch(undefined);
    assert.equal((await controlScheduler("reconcile", f.directory, id(2), id(3), f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal(await schedulerTickPermitted(f.deployment), false);
  } finally {await f.cleanup();}
});
for (const defect of ["timeout", "malformed", "conflicting"] as const) {
  test(`urgent disable retains its local latch before ${defect} daemon observation`, async () => {
    const f = await fixture(); try {
      assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_ACTIVATION_OBSERVED");
      const prior = mutations(f.commands).length;
      f.patch(async (args, result) => {
        if (args[0] === "print" || args[0] === "print-disabled") {
          assert.equal(await schedulerTickPermitted(f.deployment), false, "durable disable must precede every daemon observation");
          const retained = JSON.parse(await readFile(join(f.directory, "control", `${id(2)}.checkpoint.json`), "utf8"));
          assert.equal(retained.activation_request_id, id(1)); assert.equal(retained.action, "disable");
        }
        if (args[0] !== "print") return result;
        if (defect === "timeout") return await new Promise<never>(() => {});
        if (defect === "malformed") return ok(f.print().stdout.replace("state = not running", "state = PRIVATE_UNKNOWN_STATE"));
        return ok(f.print().stdout.replace(join(f.directory, "tick.sh"), "/private/PRIVATE_OTHER_JOB"));
      });
      const result = await controlScheduler("disable", f.directory, id(2), undefined, {...f.dependencies, launchTimeoutMs: 10});
      assert.equal(result.status, "SCHEDULER_OPERATION_UNKNOWN"); assert.equal(result.request_id, id(2));
      assert.equal(JSON.stringify(result).includes("PRIVATE_"), false); assert.equal(mutations(f.commands).length, prior);
      assert.equal(await schedulerTickPermitted(f.deployment), false);
      let ticks = 0;
      assert.equal((await runPreparedSchedulerTick(["--deployment", f.directory], {executionBinding: f.executionBinding, now: () => at,
        tick: async () => {ticks++; return {};}})).status, "SCHEDULER_LOCAL_INACTIVE");
      assert.equal(ticks, 0);
      f.patch(undefined);
      assert.equal((await controlScheduler("reconcile", f.directory, id(2), id(3), f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
      assert.equal((await controlScheduler("disable", f.directory, id(4), undefined, f.dependencies)).status, "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
      assert.equal(mutations(f.commands).length, prior); assert.equal(f.owners(), 1);
    } finally {await f.cleanup();}
  });
}
test("disable and status remain available without owner credentials after helper drift", async () => {
  const f = await fixture(); try {
    await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    await writeFile(f.helper, "compromised bytes\n");
    assert.equal((await controlScheduler("status", f.directory, undefined, undefined, f.dependencies)).status, "SCHEDULER_LOCAL_ACTIVATION_RETAINED");
    assert.equal((await controlScheduler("disable", f.directory, id(2), undefined, f.dependencies)).status, "SCHEDULER_DISABLE_OBSERVED");
    assert.equal(f.owners(), 1);
  } finally {await f.cleanup();}
});
for (const defect of ["profile-permission", "profile-bytes", "helper-bytes", "wrapper-bytes", "runtime-bytes", "symlink", "hardlink", "manifest-permission", "dependency-link"]) {
  test(`${defect} fails deployment activation before owner or mutation`, async () => {
    const f = await fixture(); try {
      if (defect === "profile-permission") await chmod(f.profilePath, 0o644);
      if (defect === "profile-bytes") await writeFile(f.profilePath, (await readFile(f.profilePath, "utf8")) + " ");
      if (defect === "helper-bytes") await writeFile(f.helper, "changed\n");
      if (defect === "wrapper-bytes") await writeFile(join(f.directory, "tick.sh"), "#!/bin/sh\nexit 0\n");
      if (defect === "runtime-bytes") await writeFile(join(f.source, "node_modules/dependency/runtime.js"), "changed\n");
      if (defect === "symlink") {await unlink(f.profilePath); await symlink(join(f.parent, "missing"), f.profilePath);}
      if (defect === "hardlink") await link(f.profilePath, join(f.parent, "alias-profile"));
      if (defect === "manifest-permission") await chmod(join(f.directory, "PREPARATION.json"), 0o644);
      if (defect === "dependency-link") {const path = join(f.source, "node_modules/package-link"); await unlink(path); await symlink("../../", path);}
      const result = await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
      assert.equal(result.status, "SCHEDULER_DEPLOYMENT_UNVERIFIED"); assert.equal(f.owners(), 0); assert.equal(mutations(f.commands).length, 0);
    } finally {await f.cleanup();}
  });
}
test("expired service identity refuses activation without owner/daemon mutations", async () => {
  const f = await fixture("2026-10-01T15:00:00.000Z"); try {
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies)).status, "SCHEDULER_IDENTITY_UNAVAILABLE");
    assert.equal(f.owners(), 0); assert.equal(mutations(f.commands).length, 0);
  } finally {await f.cleanup();}
});
for (const defect of ["wrong-key", "wrong-session", "stale", "timeout"]) {
  test(`${defect} owner validation refuses local activation`, async () => {
    const f = await fixture(); try {
      const dependencies = {...f.dependencies, ownerTimeoutMs: 10, owner: async (deployment: Deployment) => {
        if (defect === "timeout") return await new Promise<never>(() => {});
        const value = await f.dependencies.owner!(deployment);
        if (defect === "wrong-key") value.key_sha256 = "0".repeat(64);
        if (defect === "wrong-session") value.session_id = "PRIVATE_SESSION_CANARY";
        if (defect === "stale") {value.checked_at = new Date(at - 60000).toISOString(); value.sample_valid_until = new Date(at).toISOString();}
        return value;
      }};
      const result = await controlScheduler("activate", f.directory, id(1), undefined, dependencies);
      assert.equal(result.status, "SCHEDULER_OWNER_VALIDATION_REQUIRED"); assert.equal(mutations(f.commands).length, 0);
      assert.equal(JSON.stringify(result).includes("PRIVATE_SESSION_CANARY"), false);
    } finally {await f.cleanup();}
  });
}
test("timed out original command never automatically advances or retries after restart", async () => {
  const f = await fixture(); try {
    const dependencies = {...f.dependencies, launchTimeoutMs: 10, launchctl: async (args: readonly string[]) => args[0] === "enable" ? await new Promise<never>(() => {}) : await f.dependencies.launchctl!(args)};
    assert.equal((await controlScheduler("activate", f.directory, id(1), undefined, dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal((await controlScheduler("reconcile", f.directory, id(1), id(2), f.dependencies)).status, "SCHEDULER_OPERATION_UNKNOWN");
    assert.equal((await controlScheduler("activate", f.directory, id(3), undefined, f.dependencies)).status, "SCHEDULER_ORIGINAL_RECONCILIATION_REQUIRED");
    assert.equal(mutations(f.commands).length, 0); assert.equal(await schedulerTickPermitted(f.deployment), false);
  } finally {await f.cleanup();}
});
test("record replacement or malformed bootstrap claim cannot permit a tick", async () => {
  const f = await fixture(); try {
    await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    const path = join(f.directory, "control", `${id(1)}.step.json`); await writeFile(path, JSON.stringify({contract_version: 1, request_id: id(1), command: "kickstart", checkpoint_sha256: "0".repeat(64)}) + "\n");
    assert.equal(await schedulerTickPermitted(f.deployment), false);
    const original = join(f.directory, "control", `${id(1)}.checkpoint.json`); const value = JSON.parse(await readFile(original, "utf8")); value.key_sha256 = "0".repeat(64); await writeFile(original, JSON.stringify(value) + "\n");
    await assert.rejects(schedulerTickPermitted(f.deployment), /SCHEDULER_LOCAL_INTEGRITY_REQUIRED/);
  } finally {await f.cleanup();}
});
test("foreign job arguments or duplicate override entries remain unverified and redacted", async () => {
  const f = await fixture(); try {
    const foreign = {...f.print(), stdout: f.print().stdout.replace(join(f.directory, "tick.sh"), "/private/OTHER_SECRET_JOB")};
    assert.equal(projectHostObservation(f.deployment, foreign, ok("disabled services = {\n}\n")).state, "conflicting");
    const duplicate = ok(`disabled services = {\n "${schedulerLabel}" => true\n "${schedulerLabel}" => false\n}\n`);
    assert.equal(projectHostObservation(f.deployment, f.print(), duplicate).state, "unknown");
    f.patch((args, result) => args[0] === "print" ? foreign : result);
    const result = await controlScheduler("activate", f.directory, id(1), undefined, f.dependencies);
    assert.equal(result.status, "SCHEDULER_HOST_UNVERIFIED"); assert.equal(mutations(f.commands).length, 0); assert.equal(JSON.stringify(result).includes("OTHER_SECRET_JOB"), false);
  } finally {await f.cleanup();}
});
