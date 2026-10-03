import test from "node:test";
import type {TestContext} from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import {constants} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {UnattendedStore} from "./unattended_store.ts";
import type {UnattendedStoreIO} from "./unattended_store.ts";

const UUID = "99800000-0000-4000-8000-000000000002";
const NEXT_UUID = "99800000-0000-4000-8000-000000000003";
const NAME = `${UUID}.checkpoint.json`;
const NEXT_NAME = `${NEXT_UUID}.checkpoint.json`;
const UNAVAILABLE = "UNATTENDED_JOURNAL_UNAVAILABLE";
const INTEGRITY = "UNATTENDED_JOURNAL_INTEGRITY_REQUIRED";
const RECONCILE = "UNATTENDED_REQUEST_RECONCILIATION_REQUIRED";

async function fixture(t: TestContext, io?: UnattendedStoreIO) {
  const parent = await fs.realpath(await fs.mkdtemp(join(tmpdir(),"collect-unattended-store-")));
  await fs.chmod(parent,0o700);
  t.after(() => fs.rm(parent,{recursive:true,force:true}));
  const directory = join(parent,"journal");
  return {parent,directory,store:new UnattendedStore(directory,io)};
}
async function rejectsCode(operation: Promise<unknown>, code: string) {
  await assert.rejects(operation,(error: unknown) => {
    assert.ok(error instanceof Error);
    assert.equal(error.message,code);
    assert.equal(error.stack,code);
    return true;
  });
}

test("publish survives a new store instance with exact JSON bytes, private ownership and file/directory sync",async t => {
  const syncs: string[] = [];
  const io: UnattendedStoreIO = {...fs,open:async (...args: Parameters<typeof fs.open>) => {
    const handle = await fs.open(...args);
    const sync = handle.sync.bind(handle);
    handle.sync = async () => {syncs.push((await handle.stat()).isDirectory() ? "directory" : "file"); await sync();};
    return handle;
  }};
  const {directory,store} = await fixture(t,io);
  const evidence = {contract_version:2,request_id:UUID,send_action:false,result:{status:"unknown"}};
  await store.publish(NAME,evidence);
  assert.deepEqual(await new UnattendedStore(directory).read(NAME),evidence);
  assert.equal(await fs.readFile(join(directory,NAME),"utf8"),JSON.stringify(evidence) + "\n");
  const info = await fs.lstat(join(directory,NAME));
  assert.equal(info.mode & 0o7777,0o600);
  assert.equal(info.uid,process.getuid!());
  assert.equal(info.nlink,1);
  assert.equal((await fs.lstat(directory)).mode & 0o7777,0o700);
  assert.deepEqual(syncs,["directory","file","directory"]);
  assert.deepEqual(await fs.readdir(directory),[NAME]);
});

test("every lifecycle kind and principal overlap claim uses the same append-only storage API",async t => {
  const {store,directory} = await fixture(t);
  for (const kind of ["checkpoint","armed","outcome","lookup","run","step","closed"]) {
    const name = `${UUID}.${kind}.json`;
    await store.publish(name,{kind});
    assert.deepEqual(await new UnattendedStore(directory).read(name),{kind});
  }
  const lock = `principal-${UUID}.lock.json`;
  await store.publish(lock,{run_id:NEXT_UUID});
  await rejectsCode(new UnattendedStore(directory).publish(lock,{run_id:UUID}),RECONCILE);
  assert.deepEqual(await store.read(lock),{run_id:NEXT_UUID});
});

test("parallel publishers across instances have exactly one atomic winner and retain its original bytes",async t => {
  const {directory,store} = await fixture(t);
  const settled = await Promise.allSettled(Array.from({length:12},(_,index) => new UnattendedStore(directory).publish(NAME,{index})));
  assert.equal(settled.filter(result => result.status === "fulfilled").length,1);
  for (const result of settled) {
    if (result.status === "rejected") assert.equal(result.reason.message,RECONCILE);
  }
  const original = await fs.readFile(join(directory,NAME));
  await rejectsCode(store.publish(NAME,{replacement:true}),RECONCILE);
  assert.deepEqual(await fs.readFile(join(directory,NAME)),original);
  // An ordinary collision is a reconciliation requirement, not a broken disk.
  await store.publish(NEXT_NAME,{independent:true});
  assert.deepEqual((await fs.readdir(directory)).sort(),[NAME,NEXT_NAME].sort());
});

test("names require canonical lowercase UUIDs and exact kinds before any directory is created",async t => {
  const {directory,store} = await fixture(t);
  for (const name of [
    "../" + NAME,"/" + NAME,NAME + "/child",NAME + "\n",NAME.replace("998","99A"),
    "------------------------------------.checkpoint.json",`${UUID}.observation.json`,`${UUID}.lock.json`,
    `principal-${UUID}.checkpoint.json`,`${UUID}.checkpoint.json\0`,"",
  ]) {
    await rejectsCode(store.publish(name,{ok:true}),INTEGRITY);
    await rejectsCode(store.read(name,true),INTEGRITY);
  }
  await assert.rejects(fs.lstat(directory),{code:"ENOENT"});
  assert.throws(() => new UnattendedStore("relative/path"),{message:UNAVAILABLE});
});

test("optional reads return null only for a missing record and required reads fail closed",async t => {
  const {directory,store} = await fixture(t);
  assert.equal(await store.read(NAME,true),null);
  await rejectsCode(store.read(NAME),INTEGRITY);
  await fs.writeFile(join(directory,NAME),"PRIVATE_INVALID_JSON",{mode:0o600});
  await rejectsCode(store.read(NAME,true),INTEGRITY);
});

test("public parent cannot create a private journal and an existing public journal is refused",async t => {
  const {parent,directory,store} = await fixture(t);
  await fs.chmod(parent,0o755);
  await rejectsCode(store.publish(NAME,{ok:true}),UNAVAILABLE);
  await assert.rejects(fs.lstat(directory),{code:"ENOENT"});
  await fs.chmod(parent,0o700);
  await fs.mkdir(directory,{mode:0o755});
  await rejectsCode(new UnattendedStore(directory).publish(NAME,{ok:true}),UNAVAILABLE);
  await rejectsCode(new UnattendedStore(directory).read(NAME,true),UNAVAILABLE);
});

test("symlink journal and symlink ancestors are refused before publication or optional read",async t => {
  const {parent,directory} = await fixture(t);
  await fs.mkdir(directory,{mode:0o700});
  const alias = join(parent,"alias");
  await fs.symlink(directory,alias);
  for (const path of [alias,join(alias,"nested")]) {
    await rejectsCode(new UnattendedStore(path).publish(NAME,{ok:true}),UNAVAILABLE);
    await rejectsCode(new UnattendedStore(path).read(NAME,true),UNAVAILABLE);
  }
  assert.deepEqual(await fs.readdir(directory),[]);
});

test("symlink, hardlink, public-mode and nonregular records cannot be accepted",async t => {
  const {parent,directory,store} = await fixture(t);
  await store.publish(NAME,{ok:true});
  const path = join(directory,NAME);
  await fs.chmod(path,0o644);
  await rejectsCode(store.read(NAME),INTEGRITY);
  await fs.chmod(path,0o600);
  const hardlink = join(parent,"linked-evidence");
  await fs.link(path,hardlink);
  await rejectsCode(store.read(NAME),INTEGRITY);
  await fs.unlink(hardlink);
  const saved = join(parent,"saved-evidence");
  await fs.rename(path,saved);
  await fs.symlink(saved,path);
  await rejectsCode(store.read(NAME,true),INTEGRITY);
  await fs.unlink(path);
  await fs.mkdir(path,{mode:0o700});
  await rejectsCode(store.read(NAME),INTEGRITY);
});

test("canonical JSON readback rejects duplicate keys, whitespace, missing newline, malformed and invalid UTF-8 bytes",async t => {
  const {directory,store} = await fixture(t);
  await store.publish(NAME,{ok:true});
  const path = join(directory,NAME);
  for (const data of [
    '{"ok":false,"ok":true}\n','{ "ok": true }\n','{"ok":true}',"PRIVATE_BAD_JSON\n",
    Buffer.from([0x22,0xff,0x22,0x0a]),'{"ok":true}\n\n',"1e0\n",
  ]) {
    await fs.writeFile(path,data);
    await rejectsCode(new UnattendedStore(directory).read(NAME),INTEGRITY);
  }
});

test("the 65536-byte limit is enforced on encoded publication and on disk reload",async t => {
  const {directory,store} = await fixture(t);
  const largest = "x".repeat(65_533);
  await store.publish(NAME,largest);
  assert.equal((await fs.stat(join(directory,NAME))).size,65_536);
  assert.equal(await new UnattendedStore(directory).read(NAME),largest);
  await rejectsCode(store.publish(NEXT_NAME,"x".repeat(65_534)),INTEGRITY);
  await assert.rejects(fs.lstat(join(directory,NEXT_NAME)),{code:"ENOENT"});
  await fs.writeFile(join(directory,NAME),JSON.stringify("x".repeat(65_534)) + "\n");
  await rejectsCode(new UnattendedStore(directory).read(NAME),INTEGRITY);
});

test("unencodable values expose a constant code and reserve no filename",async t => {
  const {directory,store} = await fixture(t);
  const circular: {self?: unknown} = {}; circular.self = circular;
  for (const value of [undefined,1n,circular,() => {}]) await rejectsCode(store.publish(NAME,value),INTEGRITY);
  await assert.rejects(fs.lstat(directory),{code:"ENOENT"});
});

test("canonical tampering between link and readback prevents publish acceptance and seals further publishing",async t => {
  const io: UnattendedStoreIO = {...fs,link:async (from,to) => {
    await fs.link(from,to);
    await fs.writeFile(to,'{"ok":"PRIVATE_TAMPERED_VALUE"}\n');
  }};
  const {directory,store} = await fixture(t,io);
  await rejectsCode(store.publish(NAME,{ok:true}),INTEGRITY);
  await rejectsCode(store.publish(NEXT_NAME,{ok:true}),UNAVAILABLE);
  assert.deepEqual(await fs.readdir(directory),[NAME]);
});

test("replacing a record while its descriptor is read cannot turn stale bytes into accepted evidence",async t => {
  const {parent,directory,store} = await fixture(t);
  await store.publish(NAME,{ok:true});
  const path = join(directory,NAME);
  const io: UnattendedStoreIO = {...fs,open:async (...args: Parameters<typeof fs.open>) => {
    const handle = await fs.open(...args);
    if (String(args[0]) === path) {
      await fs.rename(path,join(parent,"old-evidence"));
      await fs.writeFile(path,'{"ok":true}\n',{mode:0o600});
    }
    return handle;
  }};
  await rejectsCode(new UnattendedStore(directory,io).read(NAME),INTEGRITY);
});

for (const stage of ["file","directory"] as const) {
  test(`${stage} sync failure cannot accept publication or allow later publishes on the same instance`,async t => {
    let failed = false;
    const io: UnattendedStoreIO = {...fs,open:async (...args: Parameters<typeof fs.open>) => {
      const handle = await fs.open(...args);
      const sync = handle.sync.bind(handle);
      const info = await handle.stat();
      const match = stage === "file" ? info.isFile() : info.isDirectory() && String(args[0]).endsWith("/journal");
      handle.sync = async () => {
        if (match && !failed) {failed = true; throw Error("PRIVATE_DISK_SYNC_FAILURE");}
        await sync();
      };
      return handle;
    }};
    const {directory,store} = await fixture(t,io);
    await rejectsCode(store.publish(NAME,{ok:true}),UNAVAILABLE);
    assert.equal(failed,true);
    await rejectsCode(store.publish(NEXT_NAME,{ok:true}),UNAVAILABLE);
    assert.equal(await new UnattendedStore(directory).read(NEXT_NAME,true),null);
    if (stage === "file") assert.equal(await new UnattendedStore(directory).read(NAME,true),null);
    else assert.deepEqual(await new UnattendedStore(directory).read(NAME),{ok:true});
    assert.ok((await fs.readdir(directory)).every(name => !name.endsWith(".tmp")));
  });
}

test("the final file is opened with O_NOFOLLOW and validated after reads, not followed through a pathname",async t => {
  const opens: number[] = [];
  const io: UnattendedStoreIO = {...fs,open:async (...args: Parameters<typeof fs.open>) => {
    if (String(args[0]).endsWith(NAME)) opens.push(Number(args[1]));
    return fs.open(...args);
  }};
  const {store} = await fixture(t,io);
  await store.publish(NAME,{ok:true});
  await store.read(NAME);
  assert.equal(opens.length,2);
  assert.ok(opens.every(flags => (flags & constants.O_NOFOLLOW) !== 0));
});
