import {test} from "node:test";
import assert from "node:assert/strict";
import {mkdtemp, rmdir, lstat} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {withSessionLock} from "./keychain_store.ts";
import {execFile} from "node:child_process";
import {promisify} from "node:util";

test("overlapping calls serialize session access and release only their own empty lock", async () => {
  const directory = await mkdtemp(join(tmpdir(), "collect-session-lock-"));
  const helper = join(directory, "helper");
  let release!: () => void;
  const hold = new Promise<void>(resolve => { release = resolve; });
  let entered!: () => void;
  const ready = new Promise<void>(resolve => { entered = resolve; });
  const events: string[] = [];
  try {
    const first = withSessionLock(helper, async () => { events.push("first"); entered(); await hold; events.push("first-finished"); });
    await ready;
    const second = withSessionLock(helper, async () => { events.push("second"); });
    release();
    await Promise.all([first, second]);
    assert.deepEqual(events, ["first", "first-finished", "second"]);
    await assert.rejects(lstat(`${helper}.session-lock`), {code: "ENOENT"});
    await assert.rejects(withSessionLock(helper, async () => { throw new Error("task failed"); }), /task failed/);
    await assert.rejects(lstat(`${helper}.session-lock`), {code: "ENOENT"});
  } finally { await rmdir(directory); }
});

test("a separate Node process cannot enter a held session lock", async () => {
  const directory = await mkdtemp(join(tmpdir(), "collect-process-lock-"));
  const helper = join(directory, "helper");
  try {
    await withSessionLock(helper, async () => {
      const script = `import {withSessionLock} from ${JSON.stringify(new URL("./keychain_store.ts", import.meta.url).href)};
        try { await withSessionLock(process.argv[1], async () => { throw new Error("LOCK_BYPASSED"); }); }
        catch (error) { if (error.message !== "OPERATOR_SESSION_BUSY_OR_LOCK_RECOVERY_REQUIRED") process.exitCode=2; }`;
      await promisify(execFile)(process.execPath, ["--experimental-strip-types", "--input-type=module", "--eval", script, helper], {timeout: 10000});
      assert.ok((await lstat(`${helper}.session-lock`)).isDirectory());
    });
    await assert.rejects(lstat(`${helper}.session-lock`), {code: "ENOENT"});
  } finally { await rmdir(directory); }
});
