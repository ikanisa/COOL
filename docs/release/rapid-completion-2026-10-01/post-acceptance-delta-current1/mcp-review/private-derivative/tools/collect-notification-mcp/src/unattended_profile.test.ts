import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp, realpath, chmod, writeFile, rm, symlink} from "node:fs/promises";
import * as fs from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {loadUnattendedProfile} from "./unattended_profile.ts";
import type {UnattendedProfileIO} from "./unattended_profile.ts";
async function fixture() {
  const directory = await realpath(await mkdtemp(join(tmpdir(), "collect-public-operations-profile-"))), path = join(directory, "profile.json");
  const profile = {contract_version: 2, scope: "rw_receipt_operations", identity: {principalId: "99800000-0000-4000-8000-000000000001", keySha256: "a".repeat(64), expiresAt: "2026-11-01T00:00:00Z"},
    helper_path: "/private/reviewed-helper", helper_sha256: "b".repeat(64), journal_directory: join(directory, "journal")};
  await writeFile(path, JSON.stringify(profile) + "\n", {mode: 0o600}); return {directory, path, profile, cleanup: () => rm(directory, {recursive: true, force: true})};
}
test("owner-private canonical public profile loads without auth/helper execution", async () => {
  const f = await fixture(); try {assert.deepEqual(await loadUnattendedProfile(f.path), f.profile);} finally {await f.cleanup();}
});
for (const [name, patch] of Object.entries({operatorToken: {access_token: "private"}, wrongScope: {scope: "rw_receipt_shadow"}, wrongVersion: {contract_version: 1},
  arbitraryUrl: {endpoint: "https://elsewhere"}, relativeHelper: {helper_path: "helper"}, invalidHash: {helper_sha256: "invalid"}})) {
  test("profile refuses " + name + " without reflecting values", async () => {
    const f = await fixture(); try {await writeFile(f.path, JSON.stringify({...f.profile, ...patch}) + "\n"); await assert.rejects(loadUnattendedProfile(f.path), /^Error: UNATTENDED_PROFILE_UNAVAILABLE$/);} finally {await f.cleanup();}
  });
}
test("public-readable and symlink profile are refused", async () => {
  const f = await fixture(); try {await chmod(f.path, 0o644); await assert.rejects(loadUnattendedProfile(f.path), /UNATTENDED_PROFILE_UNAVAILABLE/); await chmod(f.path, 0o600);
    const link = join(f.directory, "link"); await symlink(f.path, link); await assert.rejects(loadUnattendedProfile(link), /UNATTENDED_PROFILE_UNAVAILABLE/);
  } finally {await f.cleanup();}
});
test("duplicate JSON keys cannot be silently accepted", async () => {
  const f = await fixture(); try {const raw = JSON.stringify(f.profile).replace('"contract_version":2', '"contract_version":1,"contract_version":2'); await writeFile(f.path, raw + "\n"); await assert.rejects(loadUnattendedProfile(f.path), /UNATTENDED_PROFILE_UNAVAILABLE/);} finally {await f.cleanup();}
});
test("a profile growing after its initial fstat is refused after at most 8193 bytes without an unbounded read", async () => {
  const f = await fixture(); let readBytes = 0, grew = false;
  const io: UnattendedProfileIO = {lstat:fs.lstat,open:async (...args: Parameters<typeof fs.open>) => {
    const handle = await fs.open(...args);
    return new Proxy(handle,{get(target,key) {
      if (key === "stat") return async () => {
        const snapshot = await target.stat();
        if (!grew) {grew = true; await fs.appendFile(f.path,Buffer.alloc(256 * 1024,0x20));}
        return snapshot;
      };
      if (key === "readFile") return () => {throw Error("MUST_NOT_USE_UNBOUNDED_READ");};
      if (key === "read") return async (...readArgs: unknown[]) => {
        assert.ok(Buffer.isBuffer(readArgs[0])); assert.equal(readArgs[0].byteLength,8193);
        const result = await Reflect.apply(target.read,target,readArgs);
        readBytes += result.bytesRead;
        return result;
      };
      const value = Reflect.get(target,key,target);
      return typeof value === "function" ? value.bind(target) : value;
    }});
  }};
  try {
    await assert.rejects(loadUnattendedProfile(f.path,io),{message:"UNATTENDED_PROFILE_UNAVAILABLE"});
    assert.equal(grew,true); assert.equal(readBytes,8193);
    assert.ok((await fs.stat(f.path)).size > 8192);
  } finally {await f.cleanup();}
});
