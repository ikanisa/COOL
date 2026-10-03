import test from "node:test";
import type {TestContext} from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {createHash, generateKeyPairSync, sign, verify} from "node:crypto";
import {spawn} from "node:child_process";
import {once} from "node:events";
import {UnattendedJournal, unattendedNegativeLookupHorizonMs} from "./unattended_journal.ts";
import {UnattendedStore} from "./unattended_store.ts";
import type {UnattendedStoreIO} from "./unattended_store.ts";
import {envelope, unattendedAudience, unattendedEndpoint, unattendedScope} from "./unattended_contract.ts";
import type {Json, UnattendedIdentity, UnattendedRequest} from "./unattended_contract.ts";
import type {UnattendedSigner} from "./unattended_client.ts";

const NOW = Date.UTC(2026,8,30,23,0,0);
const PRINCIPAL = "99800000-0000-4000-8000-000000000001";
const REQUEST = "99800000-0000-4000-8000-000000000002";
const LOOKUP = "99800000-0000-4000-8000-000000000003";
const RUN = "99800000-0000-4000-8000-000000000004";
const NEXT = "99800000-0000-4000-8000-000000000005";
// Entirely synthetic, in-memory P-256 keys; no credentials or Keychain access.
const pair = generateKeyPairSync("ec",{namedCurve:"prime256v1"});
const keySha256 = createHash("sha256").update(pair.publicKey.export({format:"der",type:"spki"})).digest("hex");
const identity: UnattendedIdentity = {principalId:PRINCIPAL,keySha256,expiresAt:new Date(NOW + 86_400_000).toISOString()};
const request: UnattendedRequest = {action:"begin_run",requestId:REQUEST,payload:{}};
const signer: UnattendedSigner = async (bytes,signal) => {
  signal.throwIfAborted();
  return {keySha256,signature:sign("sha256",bytes,pair.privateKey).toString("base64")};
};

async function fixture(t: TestContext, io?: UnattendedStoreIO) {
  const parent = await fs.realpath(await fs.mkdtemp(join(tmpdir(),"collect-unattended-journal-")));
  await fs.chmod(parent,0o700);
  t.after(() => fs.rm(parent,{recursive:true,force:true}));
  const directory = join(parent,"journal");
  return {parent,directory,journal:new UnattendedJournal(directory,new UnattendedStore(directory,io))};
}
function beginResult(at = NOW): Json {
  return {contract_version:2,principal_id:PRINCIPAL,request_id:REQUEST,action:"begin_run",observed_at:new Date(at).toISOString(),
    ok:true,code:"RUN_STARTED",run_id:RUN,fence_version:1,mode:"Dry-run",expires_at:new Date(at + 120_000).toISOString()};
}
function response(options: RequestInit | undefined, result: Json, status = 200) {
  const body = JSON.parse(options!.body as string);
  return new Response(JSON.stringify({contract_version:2,principal_id:PRINCIPAL,request_id:body.request_id,action:body.action,result}),
    {status,headers:{"content-type":"application/json"}});
}
function lookupResult(status: "recorded" | "not_recorded" | "in_progress", receipt: Json | null = null): Json {
  return {contract_version:2,target_request_id:REQUEST,status,receipt};
}
async function files(directory: string): Promise<Record<string,string>> {
  const names = await fs.readdir(directory);
  return Object.fromEntries(await Promise.all(names.map(async name => [name,await fs.readFile(join(directory,name),"utf8")])));
}
async function unknown(journal: UnattendedJournal) {
  return journal.once(identity,request,signer,async () => {throw Error("PRIVATE_NETWORK_ERROR");},() => NOW);
}
function assertOriginalPreserved(before: Record<string,string>, after: Record<string,string>) {
  for (const [name,bytes] of Object.entries(before)) assert.equal(after[name],bytes,name);
}

test("checkpoint and armed envelope are durably private and reloadable before the injected HTTP call",async t => {
  const syncs: string[] = [];
  const io: UnattendedStoreIO = {...fs,open:async (...args: Parameters<typeof fs.open>) => {
    const handle = await fs.open(...args);
    const sync = handle.sync.bind(handle);
    handle.sync = async () => {syncs.push((await handle.stat()).isDirectory() ? "directory" : String(args[0])); await sync();};
    return handle;
  }};
  const {journal,directory} = await fixture(t,io);
  let calls = 0;
  const result = await journal.once(identity,request,signer,async (url,options) => {
    calls++;
    assert.equal(url,unattendedEndpoint);
    const checkpoint = await new UnattendedStore(directory).read(`${REQUEST}.checkpoint.json`) as Json;
    const armed = await new UnattendedStore(directory).read(`${REQUEST}.armed.json`) as Json;
    assert.deepEqual(checkpoint,{contract_version:2,scope:unattendedScope,audience:unattendedAudience,identity,request,created_at:new Date(NOW).toISOString()});
    assert.equal(armed.contract_version,2);
    assert.equal(armed.request_id,REQUEST);
    assert.equal(armed.envelope_sha256,createHash("sha256").update(options!.body as string).digest("hex"));
    assert.equal(armed.not_recorded_before,new Date(NOW + unattendedNegativeLookupHorizonMs).toISOString());
    assert.ok(syncs.some(path => path.includes(".checkpoint.json.")));
    assert.ok(syncs.some(path => path.includes(".armed.json.")));
    assert.equal(syncs.filter(path => path === "directory").length,3);
    const signature = new Headers(options!.headers).get("X-Collect-Supervisor-Signature")!;
    assert.equal(verify("sha256",Buffer.from(options!.body as string),pair.publicKey,Buffer.from(signature,"base64")),true);
    for (const name of [`${REQUEST}.checkpoint.json`,`${REQUEST}.armed.json`]) {
      const info = await fs.stat(join(directory,name));
      assert.equal(info.mode & 0o7777,0o600); assert.equal(info.uid,process.getuid!()); assert.equal(info.nlink,1);
    }
    return response(options,beginResult());
  },() => NOW);
  assert.equal(calls,1);
  assert.equal(result.contract_version,2); assert.equal(result.request_id,REQUEST); assert.equal(result.outcome,"recorded");
  assert.deepEqual(result.result,beginResult());
  assert.deepEqual(await new UnattendedJournal(directory).readOriginal(REQUEST),result);
  assert.ok(Object.values(await files(directory)).every(value => !value.includes("signature")));
});

for (const stage of ["checkpoint-file","checkpoint-directory","armed-file","armed-directory"]) {
  test(`${stage} sync failure prevents all HTTP and preserves the caller UUID`,async t => {
    let directory = "", linkedKind = "", signed = 0, calls = 0, failed = false;
    const io: UnattendedStoreIO = {...fs,
      link:async (from,to) => {await fs.link(from,to); linkedKind = String(to).endsWith(".armed.json") ? "armed" : "checkpoint";},
      open:async (...args: Parameters<typeof fs.open>) => {
        const handle = await fs.open(...args);
        const sync = handle.sync.bind(handle);
        handle.sync = async () => {
          const path = String(args[0]);
          const [kind,type] = stage.split("-");
          const match = type === "file" ? path.includes(`.${kind}.json.`) : path === directory && linkedKind === kind;
          if (match && !failed) {failed = true; throw Error("PRIVATE_FSYNC_DETAIL");}
          await sync();
        };
        return handle;
      },
    };
    const item = await fixture(t,io); directory = item.directory;
    const result = await item.journal.once(identity,request,async (...args) => {signed++; return signer(...args);},
      async () => {calls++; throw Error("MUST_NOT_HTTP");},() => NOW);
    assert.equal(failed,true); assert.equal(calls,0);
    assert.equal(signed,stage.startsWith("checkpoint") ? 0 : 1);
    assert.equal(result.request_id,REQUEST); assert.equal(result.outcome,"unknown");
    assert.equal(result.reason_code,"UNATTENDED_JOURNAL_UNAVAILABLE");
    assert.ok(!JSON.stringify(result).includes("PRIVATE_"));
  });
}

test("restart and repeated original UUID never sign, send, generate another request, or alter original records",async t => {
  const {journal,directory} = await fixture(t);
  const original = await unknown(journal);
  const before = await files(directory);
  const restarted = new UnattendedJournal(directory);
  assert.deepEqual(await restarted.readOriginal(REQUEST),original);
  let calls = 0;
  const duplicate = await restarted.once(identity,request,async () => {calls++; throw Error("SECOND_SIGN");},
    async () => {calls++; throw Error("SECOND_HTTP");},() => NOW + 300_000);
  assert.equal(calls,0); assert.equal(duplicate.request_id,REQUEST);
  assert.equal(duplicate.outcome,"unknown"); assert.equal(duplicate.reason_code,"UNATTENDED_REQUEST_RECONCILIATION_REQUIRED");
  assert.deepEqual(await files(directory),before);
});

test("a killed process leaves its durable checkpoint reserved and a new instance cannot replay it",async t => {
  const {directory} = await fixture(t);
  const script = `import {UnattendedJournal} from ${JSON.stringify(new URL("./unattended_journal.ts",import.meta.url).href)};
    const journal = new UnattendedJournal(process.argv[1]);
    await journal.once(${JSON.stringify(identity)},${JSON.stringify(request)},
      async () => {process.stdout.write('RESERVED\\n'); return await new Promise(() => {});},
      async () => {throw Error('MUST_NOT_HTTP');},() => ${NOW},15000);`;
  const child = spawn(process.execPath,["--experimental-strip-types","--input-type=module","--eval",script,directory],
    {env:{},stdio:["ignore","pipe","pipe"]});
  t.after(() => child.kill()); child.stderr.resume();
  await new Promise<void>((resolve,reject) => {
    const timer = setTimeout(() => reject(Error("SYNTHETIC_CHILD_TIMEOUT")),5000);
    child.on("error",() => {clearTimeout(timer); reject(Error("SYNTHETIC_CHILD_FAILED"));});
    child.stdout.on("data",data => {if (data.toString().includes("RESERVED")) {clearTimeout(timer); resolve();}});
  });
  const stopped = once(child,"exit"); child.kill("SIGKILL"); await stopped;
  const restarted = new UnattendedJournal(directory);
  assert.equal((await restarted.readOriginal(REQUEST)).reason_code,"UNATTENDED_REQUEST_RECONCILIATION_REQUIRED");
  let calls = 0;
  const result = await restarted.once(identity,request,async () => {calls++; throw Error("SIGN");},
    async () => {calls++; throw Error("HTTP");},() => NOW);
  assert.equal(calls,0); assert.equal(result.request_id,REQUEST); assert.equal(result.reason_code,"UNATTENDED_REQUEST_RECONCILIATION_REQUIRED");
  assert.deepEqual(await fs.readdir(directory),[`${REQUEST}.checkpoint.json`]);
});

test("network loss and malformed v2 success stay unknown after reload, without retaining private details or retrying",async t => {
  const responses: Array<(options: RequestInit | undefined) => Response> = [
    () => {throw Error("PRIVATE_NETWORK_FAILURE");},
    () => new Response('{"PRIVATE_RESPONSE_BODY":true}',{status:200,headers:{"content-type":"application/json"}}),
    options => response(options,{...beginResult(),unexpected:"PRIVATE_RESULT_FIELD"}),
    options => response(options,{...beginResult(),contract_version:1}),
    options => response(options,{...beginResult(),code:"PRIVATE_ARBITRARY_CODE"}),
  ];
  for (let index = 0; index < responses.length; index++) {
    const {journal,directory} = await fixture(t); let calls = 0;
    const result = await journal.once(identity,request,signer,async (_url,options) => {calls++; return responses[index]!(options);},() => NOW);
    assert.equal(calls,1); assert.equal(result.outcome,"unknown"); assert.equal(result.reason_code,"UNATTENDED_OUTCOME_UNKNOWN");
    assert.equal(result.request_id,REQUEST); assert.equal(result.result,null);
    assert.deepEqual(await new UnattendedJournal(directory).readOriginal(REQUEST),result);
    assert.ok(!JSON.stringify(await files(directory)).includes("PRIVATE_"));
  }
});

test("an unanswered HTTP deadline remains unknown and the journal never retries the mutation",async t => {
  const {journal,directory} = await fixture(t); let calls = 0;
  const result = await journal.once(identity,request,signer,async () => {calls++; return await new Promise<Response>(() => {});},() => NOW,5000);
  assert.equal(calls,1); assert.equal(result.outcome,"unknown"); assert.equal(result.request_id,REQUEST);
  assert.equal(result.reason_code,"UNATTENDED_OUTCOME_UNKNOWN");
  const before = await files(directory);
  await new UnattendedJournal(directory).once(identity,request,signer,async () => {calls++; throw Error("RETRY");},() => NOW + 200_000);
  assert.equal(calls,1); assert.deepEqual(await files(directory),before);
});

test("outcome persistence failure cannot accept the valid HTTP response and retains original envelope evidence",async t => {
  const io: UnattendedStoreIO = {...fs,link:async (from,to) => {
    if (String(to).endsWith(".outcome.json")) throw Error("PRIVATE_OUTCOME_PERSISTENCE_ERROR");
    await fs.link(from,to);
  }};
  const {journal,directory} = await fixture(t,io); let calls = 0;
  const result = await journal.once(identity,request,signer,async (_url,options) => {calls++; return response(options,beginResult());},() => NOW);
  assert.equal(calls,1); assert.equal(result.outcome,"unknown"); assert.equal(result.result,null);
  assert.equal(result.request_id,REQUEST); assert.equal(result.reason_code,"UNATTENDED_JOURNAL_UNAVAILABLE");
  const store = new UnattendedStore(directory);
  assert.equal(await store.read(`${REQUEST}.outcome.json`,true),null);
  assert.ok(await store.read(`${REQUEST}.checkpoint.json`)); assert.ok(await store.read(`${REQUEST}.armed.json`));
  assert.equal((await new UnattendedJournal(directory).readOriginal(REQUEST)).outcome,"unknown");
  assert.ok(!JSON.stringify(result).includes("PRIVATE_"));
});

for (const elapsed of [30_000,unattendedNegativeLookupHorizonMs - 1,unattendedNegativeLookupHorizonMs,unattendedNegativeLookupHorizonMs + 1]) {
  test(`manual absence lookup at ${elapsed}ms retains the conservative signed horizon and original evidence`,async t => {
    const {journal,directory} = await fixture(t); await unknown(journal);
    const before = await files(directory); let calls = 0;
    const result = await new UnattendedJournal(directory).reconcile(identity,REQUEST,LOOKUP,signer,async (_url,options) => {
      calls++; const body = JSON.parse(options!.body as string);
      assert.equal(body.contract_version,2); assert.equal(body.action,"reconcile_request"); assert.equal(body.request_id,LOOKUP);
      assert.deepEqual(body.payload,{target_request_id:REQUEST});
      return response(options,lookupResult("not_recorded"));
    },() => NOW + elapsed);
    assert.equal(calls,1); assert.equal(result.request_id,REQUEST); assert.equal(result.lookup_request_id,LOOKUP);
    assert.equal(result.outcome,elapsed < unattendedNegativeLookupHorizonMs ? "unknown" : "not_recorded");
    assert.equal(result.reason_code,elapsed < unattendedNegativeLookupHorizonMs ? "UNATTENDED_ORIGINAL_REQUEST_WINDOW_OPEN" : "UNATTENDED_ORIGINAL_REQUEST_NOT_RECORDED");
    const after = await files(directory); assertOriginalPreserved(before,after);
    assert.deepEqual(JSON.parse(after[`${LOOKUP}.lookup.json`]!),result);
    let replay = 0;
    await journal.once(identity,request,async () => {replay++; throw Error("SIGN");},async () => {replay++; throw Error("HTTP");},() => NOW + elapsed);
    assert.equal(replay,0); assert.equal((await new UnattendedJournal(directory).readOriginal(REQUEST)).outcome,"unknown");
  });
}

test("recorded manual lookup retains the explicit target and caller lookup UUID without reissuing begin_run",async t => {
  const {journal,directory} = await fixture(t); await unknown(journal);
  const before = await files(directory); let calls = 0;
  const result = await new UnattendedJournal(directory).reconcile(identity,REQUEST,LOOKUP,signer,async (_url,options) => {
    calls++; const body = JSON.parse(options!.body as string);
    assert.equal(body.action,"reconcile_request"); assert.equal(body.request_id,LOOKUP); assert.deepEqual(body.payload,{target_request_id:REQUEST});
    return response(options,lookupResult("recorded",beginResult()));
  },() => NOW + 180_000);
  assert.equal(calls,1); assert.equal(result.outcome,"recorded"); assert.equal(result.request_id,REQUEST); assert.equal(result.lookup_request_id,LOOKUP);
  assert.deepEqual(result.result,beginResult()); assertOriginalPreserved(before,await files(directory));
});

test("recorded lookup survives restart and a subsequent fresh absence cannot clear its immutable original alias",async t => {
  const {journal,directory} = await fixture(t); await unknown(journal);
  const original = await files(directory);
  const recorded = await journal.reconcile(identity,REQUEST,LOOKUP,signer,
    async (_url,options) => response(options,lookupResult("recorded",beginResult())),() => NOW + 180_000);
  assert.equal(recorded.outcome,"recorded"); assert.equal(recorded.lookup_request_id,LOOKUP);
  const aliasPath = join(directory,`${REQUEST}.lookup.json`);
  const aliasBytes = await fs.readFile(aliasPath);
  assert.deepEqual(JSON.parse(aliasBytes.toString()),recorded);
  assertOriginalPreserved(original,await files(directory));
  const restarted = new UnattendedJournal(directory);
  assert.deepEqual(await restarted.readOriginal(REQUEST),recorded);
  const beforeAbsence = await files(directory); let calls = 0;
  const absent = await restarted.reconcile(identity,REQUEST,NEXT,signer,async (_url,options) => {
    calls++; const body = JSON.parse(options!.body as string);
    assert.equal(body.action,"reconcile_request"); assert.equal(body.request_id,NEXT); assert.deepEqual(body.payload,{target_request_id:REQUEST});
    return response(options,lookupResult("not_recorded"));
  },() => NOW + 240_000);
  assert.equal(calls,1); assert.equal(absent.outcome,"unknown"); assert.equal(absent.reason_code,"UNATTENDED_LOOKUP_UNAVAILABLE");
  assert.deepEqual(await fs.readFile(aliasPath),aliasBytes);
  assertOriginalPreserved(beforeAbsence,await files(directory));
  assert.deepEqual(await new UnattendedJournal(directory).readOriginal(REQUEST),recorded);
});

test("concurrent recorded lookups of the same immutable server receipt retain one original alias and both lookup proofs",{timeout:15_000},async t => {
  let aliasAttempts = 0, release!: () => void;
  const bothAliases = new Promise<void>(resolve => {release = resolve;});
  t.after(() => release());
  const io: UnattendedStoreIO = {...fs,link:async (from,to) => {
    if (String(to).endsWith(`${REQUEST}.lookup.json`)) {
      aliasAttempts++;
      if (aliasAttempts === 2) release();
      await bothAliases;
    }
    await fs.link(from,to);
  }};
  const {journal,directory} = await fixture(t,io); await unknown(journal);
  const original = await files(directory);
  const receipt = beginResult(); let calls = 0;
  const fetcher: typeof fetch = async (_url,options) => {
    calls++; const body = JSON.parse(options!.body as string);
    assert.equal(body.action,"reconcile_request"); assert.deepEqual(body.payload,{target_request_id:REQUEST});
    assert.ok([LOOKUP,NEXT].includes(body.request_id));
    return response(options,lookupResult("recorded",receipt));
  };
  const results = await Promise.all([
    journal.reconcile(identity,REQUEST,LOOKUP,signer,fetcher,() => NOW + 180_000),
    new UnattendedJournal(directory,new UnattendedStore(directory,io)).reconcile(identity,REQUEST,NEXT,signer,fetcher,() => NOW + 180_000),
  ]);
  assert.equal(calls,2); assert.equal(aliasAttempts,2);
  for (const result of results) {assert.equal(result.outcome,"recorded"); assert.equal(result.request_id,REQUEST); assert.deepEqual(result.result,receipt);}
  const names = await fs.readdir(directory);
  assert.equal(names.filter(name => name === `${REQUEST}.lookup.json`).length,1);
  assert.ok(names.every(name => !name.endsWith(".tmp")));
  const recovered = await new UnattendedJournal(directory).readOriginal(REQUEST);
  assert.equal(recovered.outcome,"recorded"); assert.deepEqual(recovered.result,receipt);
  assert.ok([LOOKUP,NEXT].includes(recovered.lookup_request_id!));
  assert.deepEqual(recovered,results.find(result => result.lookup_request_id === recovered.lookup_request_id));
  const store = new UnattendedStore(directory);
  for (const id of [LOOKUP,NEXT]) {
    assert.deepEqual(await store.read(`${id}.lookup.json`),results.find(result => result.lookup_request_id === id));
    assert.ok(await store.read(`${id}.checkpoint.json`)); assert.ok(await store.read(`${id}.armed.json`));
  }
  assertOriginalPreserved(original,await files(directory));
});

test("canonical stored payload and lookup request-ID tampering cannot pass durable envelope and alias bindings",async t => {
  {
    const {journal,directory} = await fixture(t);
    const preparation: UnattendedRequest = {action:"ensure_receipt",requestId:REQUEST,
      payload:{run_id:RUN,fence_version:1,event_id:NEXT,expected_source_version:1}};
    const result = await journal.once(identity,preparation,signer,async () => {throw Error("SYNTHETIC_NETWORK_LOSS");},() => NOW);
    assert.equal(result.outcome,"unknown");
    const path = join(directory,`${REQUEST}.checkpoint.json`);
    const checkpoint = JSON.parse(await fs.readFile(path,"utf8"));
    // Both source versions are individually valid, but only 1 was signed.
    checkpoint.request.payload.expected_source_version = 2;
    await fs.writeFile(path,JSON.stringify(checkpoint) + "\n");
    await assert.rejects(new UnattendedJournal(directory).readOriginal(REQUEST),{message:"UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
  }
  {
    const {journal,directory} = await fixture(t); await unknown(journal);
    const recorded = await journal.reconcile(identity,REQUEST,LOOKUP,signer,
      async (_url,options) => response(options,lookupResult("recorded",beginResult())),() => NOW + 180_000);
    assert.equal(recorded.outcome,"recorded");
    const checkpointPath = join(directory,`${LOOKUP}.checkpoint.json`), armedPath = join(directory,`${LOOKUP}.armed.json`);
    const checkpoint = JSON.parse(await fs.readFile(checkpointPath,"utf8")), armed = JSON.parse(await fs.readFile(armedPath,"utf8"));
    checkpoint.request.requestId = NEXT; armed.request_id = NEXT;
    // Keep the substitute checkpoint and digest internally consistent: the
    // alias must additionally bind the UUID in its referenced filenames.
    armed.envelope_sha256 = createHash("sha256").update(JSON.stringify(envelope(checkpoint.identity,checkpoint.request,Date.parse(armed.issued_at)))).digest("hex");
    await fs.writeFile(checkpointPath,JSON.stringify(checkpoint) + "\n");
    await fs.writeFile(armedPath,JSON.stringify(armed) + "\n");
    await assert.rejects(new UnattendedJournal(directory).readOriginal(REQUEST),{message:"UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
  }
});

test("in-progress, unavailable and malformed manual lookups stay unknown beyond the original horizon",async t => {
  const cases: Array<(options: RequestInit | undefined) => Response> = [
    options => response(options,lookupResult("in_progress")),
    () => {throw Error("PRIVATE_LOOKUP_TRANSPORT_FAILURE");},
    () => new Response('{"PRIVATE_BACKEND_FAILURE":true}',{status:503,headers:{"content-type":"application/json"}}),
    options => response(options,{...lookupResult("not_recorded"),receipt:beginResult()}),
  ];
  for (let index = 0; index < cases.length; index++) {
    const {journal,directory} = await fixture(t); await unknown(journal);
    const before = await files(directory); let calls = 0;
    const result = await journal.reconcile(identity,REQUEST,LOOKUP,signer,async (_url,options) => {calls++; return cases[index]!(options);},() => NOW + 180_000);
    assert.equal(calls,1); assert.equal(result.outcome,"unknown"); assert.equal(result.request_id,REQUEST); assert.equal(result.lookup_request_id,LOOKUP);
    assert.equal(result.reason_code,index === 0 ? "UNATTENDED_ORIGINAL_REQUEST_IN_PROGRESS" : "UNATTENDED_LOOKUP_UNAVAILABLE");
    assertOriginalPreserved(before,await files(directory)); assert.ok(!JSON.stringify(await files(directory)).includes("PRIVATE_"));
  }
});

test("same lookup UUID, changed principal and changed key are denied before signing, HTTP or lookup reservation",async t => {
  const {journal,directory} = await fixture(t); await unknown(journal);
  const before = await files(directory); let calls = 0;
  const noSign: UnattendedSigner = async () => {calls++; throw Error("SIGN");};
  const noHttp: typeof fetch = async () => {calls++; throw Error("HTTP");};
  for (const [changed,target,lookup] of [
    [identity,REQUEST,REQUEST], [{...identity,principalId:NEXT},REQUEST,LOOKUP], [{...identity,keySha256:"a".repeat(64)},REQUEST,LOOKUP],
  ] as const) await assert.rejects(journal.reconcile(changed,target,lookup,noSign,noHttp,() => NOW + 180_000),{message:"UNATTENDED_ARGUMENTS_INVALID"});
  assert.equal(calls,0); assert.deepEqual(await files(directory),before);
});

test("a duplicate lookup while another process owns its reservation cannot append failure evidence for that UUID",async t => {
  const {journal,directory} = await fixture(t); await unknown(journal);
  let entered!: () => void, release!: () => void, calls = 0;
  const ready = new Promise<void>(resolve => {entered = resolve;});
  const held = new Promise<void>(resolve => {release = resolve;});
  const first = journal.reconcile(identity,REQUEST,LOOKUP,async (...args) => {entered(); await held; return signer(...args);},async (_url,options) => {
    calls++; return response(options,lookupResult("recorded",beginResult()));
  },() => NOW + 180_000);
  await ready;
  const before = await files(directory);
  const duplicate = await new UnattendedJournal(directory).reconcile(identity,REQUEST,LOOKUP,
    async () => {throw Error("SECOND_SIGN");},async () => {throw Error("SECOND_HTTP");},() => NOW + 180_000);
  assert.equal(duplicate.outcome,"unknown"); assert.equal(duplicate.reason_code,"UNATTENDED_REQUEST_RECONCILIATION_REQUIRED");
  assert.deepEqual(await files(directory),before);
  await assert.rejects(fs.stat(join(directory,`${LOOKUP}.outcome.json`)),{code:"ENOENT"});
  release(); assert.equal((await first).outcome,"recorded"); assert.equal(calls,1);
  const completed = await files(directory);
  const later = await new UnattendedJournal(directory).reconcile(identity,REQUEST,LOOKUP,signer,
    async () => {throw Error("MUST_NOT_RETRY_LOOKUP");},() => NOW + 240_000);
  assert.equal(later.reason_code,"UNATTENDED_REQUEST_RECONCILIATION_REQUIRED");
  assert.deepEqual(await files(directory),completed);
});

test("a later absence cannot contradict an already recorded original response",async t => {
  const {journal,directory} = await fixture(t);
  await journal.once(identity,request,signer,async (_url,options) => response(options,beginResult()),() => NOW);
  const before = await files(directory);
  const result = await journal.reconcile(identity,REQUEST,LOOKUP,signer,async (_url,options) => response(options,lookupResult("not_recorded")),() => NOW + 180_000);
  assert.equal(result.outcome,"unknown"); assert.equal(result.reason_code,"UNATTENDED_LOOKUP_UNAVAILABLE");
  assert.equal((await new UnattendedJournal(directory).readOriginal(REQUEST)).outcome,"recorded");
  assertOriginalPreserved(before,await files(directory));
});

test("absence without original signed-time evidence remains unknown after any elapsed horizon",async t => {
  const {journal,directory} = await fixture(t);
  const first = await journal.once(identity,request,async () => {throw Error("PRIVATE_SIGNER_UNAVAILABLE");},async () => {throw Error("MUST_NOT_HTTP");},() => NOW);
  assert.equal(first.outcome,"unknown"); assert.equal(first.reason_code,"UNATTENDED_SIGNING_UNAVAILABLE");
  assert.equal(await journal.store.read(`${REQUEST}.armed.json`,true),null);
  const before = await files(directory);
  const result = await journal.reconcile(identity,REQUEST,LOOKUP,signer,async (_url,options) => response(options,lookupResult("not_recorded")),() => NOW + 180_000);
  assert.equal(result.outcome,"unknown"); assert.equal(result.reason_code,"UNATTENDED_LOOKUP_UNAVAILABLE");
  assertOriginalPreserved(before,await files(directory));
});

test("reloaded recorded timestamps must stay within the original request's evidence window",async t => {
  const {journal,directory} = await fixture(t);
  await journal.once(identity,request,signer,async (_url,options) => response(options,beginResult()),() => NOW);
  const path = join(directory,`${REQUEST}.outcome.json`);
  const original = JSON.parse(await fs.readFile(path,"utf8"));
  for (const at of [NOW - 10_001,Date.parse(identity.expiresAt)]) {
    await fs.writeFile(path,JSON.stringify({...original,result:beginResult(at)}) + "\n");
    await assert.rejects(new UnattendedJournal(directory).readOriginal(REQUEST),{message:"UNATTENDED_JOURNAL_INTEGRITY_REQUIRED"});
  }
});

test("a fresh lookup identity cannot promote a recorded receipt outside the original request's time bounds",async t => {
  for (const at of [NOW - 10_001,Date.parse(identity.expiresAt)]) {
    const {journal,directory} = await fixture(t); await unknown(journal);
    const before = await files(directory);
    const renewed = {...identity,expiresAt:new Date(NOW + 172_800_000).toISOString()};
    const result = await journal.reconcile(renewed,REQUEST,LOOKUP,signer,
      async (_url,options) => response(options,lookupResult("recorded",beginResult(at))),() => NOW + 86_580_000);
    assert.equal(result.outcome,"unknown"); assert.equal(result.reason_code,"UNATTENDED_LOOKUP_UNAVAILABLE");
    assertOriginalPreserved(before,await files(directory));
  }
});

test("invalid action inputs and pre-aborted operations cannot reserve, sign or call HTTP",async t => {
  const {journal,directory} = await fixture(t); let calls = 0;
  const noSign: UnattendedSigner = async () => {calls++; throw Error("SIGN");};
  const noHttp: typeof fetch = async () => {calls++; throw Error("HTTP");};
  for (const invalid of [
    {...request,payload:{recipient:"PRIVATE_RECIPIENT"}}, {...request,action:"send"},
    {action:"reconcile_request",requestId:LOOKUP,payload:{target_request_id:REQUEST}}, {...request,requestId:"invalid"},
  ]) await assert.rejects(journal.once(identity,invalid as UnattendedRequest,noSign,noHttp,() => NOW),{message:"UNATTENDED_ARGUMENTS_INVALID"});
  const controller = new AbortController(); controller.abort();
  const result = await journal.once(identity,request,noSign,noHttp,() => NOW,5000,controller.signal);
  assert.equal(result.request_id,REQUEST); assert.equal(result.outcome,"unknown"); assert.equal(calls,0);
  await assert.rejects(fs.stat(directory),{code:"ENOENT"});
});
