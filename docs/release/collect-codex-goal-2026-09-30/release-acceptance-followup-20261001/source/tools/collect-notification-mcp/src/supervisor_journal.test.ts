import test from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {createHash} from "node:crypto";
import {spawn} from "node:child_process";
import {once} from "node:events";
import {SupervisorJournal, supervisorNegativeLookupHorizonMs} from "./supervisor_journal.ts";
import type {SupervisorIdentity, SupervisorSigner} from "./supervisor_client.ts";

const NOW = Date.UTC(2026,8,30,23,0,0);
const principal = "99800000-0000-4000-8000-000000000001";
const request = "99800000-0000-4000-8000-000000000002";
const lookup = "99800000-0000-4000-8000-000000000003";
const identity: SupervisorIdentity = {principalId:principal,keySha256:"b".repeat(64),expiresAt:new Date(NOW+86400000).toISOString()};
const signature = Buffer.from([0x30,0x06,0x02,0x01,0x01,0x02,0x01,0x01]).toString("base64");
const signer: SupervisorSigner = async () => ({keySha256:identity.keySha256,signature});
function observation(action = "shadow_health") {
  const result = {contract_version:1,principal_id:principal,request_id:request,action,observed_at:new Date(NOW).toISOString(),
    expires_at:identity.expiresAt,scope:"rw_receipt_shadow",mode:"Shadow",business_handled:false,financial_action:false,send_action:false};
  return action === "shadow_health" ? {...result,sample_valid_until:new Date(NOW+60000).toISOString(),
    queued_count:2,unknown_count:1,failed_no_send_count:0,dispatch_enabled:false} : result;
}
function response(options: RequestInit | undefined, result: unknown) {
  const body = JSON.parse(options!.body as string);
  return new Response(JSON.stringify({contract_version:1,principal_id:principal,request_id:body.request_id,action:body.action,result}),{status:200,headers:{"content-type":"application/json"}});
}
async function fixture(t: any, io?: ConstructorParameters<typeof SupervisorJournal>[1]) {
  const parent = await fs.realpath(await fs.mkdtemp(join(tmpdir(),"collect-supervisor-journal-")));
  await fs.chmod(parent,0o700);
  t.after(() => fs.rm(parent,{recursive:true,force:true}));
  const directory = join(parent,"journal");
  return {parent,directory,journal:new SupervisorJournal(directory,io)};
}
async function unknown(journal: SupervisorJournal) {
  return journal.once(identity,{action:"shadow_health",requestId:request},signer,async()=>{throw new Error("PRIVATE_BACKEND_DETAIL");},()=>NOW);
}
async function files(directory: string) {
  const names = await fs.readdir(directory);
  return Object.fromEntries(await Promise.all(names.map(async name => [name,await fs.readFile(join(directory,name),"utf8")])));
}

test("reservation and exact signed envelope are private, fsynced and read back before the single HTTP call",async t=>{
  let syncs=0, calls=0;
  const io={...fs,open:async(...args:Parameters<typeof fs.open>)=>{
    const handle=await fs.open(...args);const original=handle.sync.bind(handle);
    handle.sync=async()=>{syncs++;await original();};return handle;
  }};
  const {journal,directory}=await fixture(t,io);
  const result=await journal.once(identity,{action:"shadow_health",requestId:request},signer,async(_url,options)=>{
    calls++;
    assert.ok(syncs>=4);
    const checkpoint=JSON.parse(await fs.readFile(join(directory,request+".checkpoint.json"),"utf8"));
    const armed=JSON.parse(await fs.readFile(join(directory,request+".armed.json"),"utf8"));
    assert.equal(checkpoint.scope,"rw_receipt_shadow");assert.equal(checkpoint.action,"shadow_health");
    assert.equal(armed.envelope_sha256,createHash("sha256").update(options!.body as string).digest("hex"));
    assert.equal(armed.issued_at,JSON.parse(options!.body as string).issued_at);
    for(const name of await fs.readdir(directory))assert.equal((await fs.stat(join(directory,name))).mode&0o777,0o600);
    assert.equal((await fs.stat(directory)).mode&0o777,0o700);
    return response(options,observation());
  },()=>NOW);
  assert.equal(calls,1);assert.equal(result.outcome,"recorded");
  assert.equal(result.send_action,false);assert.equal(result.financial_action,false);
  assert.deepEqual(await new SupervisorJournal(directory).readOriginal(request),result);
  assert.ok(!JSON.stringify(await files(directory)).includes(signature));
  assert.ok(!JSON.stringify(await files(directory)).includes("queued_count"));
});

test("actual filesystem restart retains unknown and cannot sign or replay the original UUID",async t=>{
  const {journal,directory}=await fixture(t);const result=await unknown(journal);assert.equal(result.outcome,"unknown");
  const prior=await files(directory);let calls=0;
  const restarted=new SupervisorJournal(directory);
  assert.equal((await restarted.readOriginal(request)).request_id,request);
  const duplicate=await restarted.once(identity,{action:"shadow_health",requestId:request},async()=>{calls++;return signer(new Uint8Array(),new AbortController().signal);},async()=>{calls++;throw Error("REPLAY");},()=>NOW);
  assert.equal(duplicate.outcome,"unknown");assert.equal(duplicate.reason_code,"SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED");
  assert.equal(calls,0);assert.deepEqual(await files(directory),prior);
});

test("overlapping independent callers atomically reserve one UUID and only one can invoke HTTP",async t=>{
  const {journal,directory}=await fixture(t);let release!:()=>void;let entered!:()=>void;let http=0;
  const held=new Promise<void>(resolve=>{release=resolve;});const ready=new Promise<void>(resolve=>{entered=resolve;});
  const first=journal.once(identity,{action:"shadow_health",requestId:request},async()=>{entered();await held;return {keySha256:identity.keySha256,signature};},async(_url,options)=>{http++;return response(options,observation());},()=>NOW);
  await ready;
  const second=await new SupervisorJournal(directory).once(identity,{action:"shadow_health",requestId:request},async()=>{throw Error("SECOND_SIGNATURE");},async()=>{throw Error("SECOND_HTTP");},()=>NOW);
  assert.equal(second.reason_code,"SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED");release();
  assert.equal((await first).outcome,"recorded");assert.equal(http,1);
});

for(const stage of ["checkpoint","armed"]){
  test("actual "+stage+" fsync failure prevents HTTP and preserves the supplied UUID",async t=>{
    let http=0;let signed=0;
    const io={...fs,open:async(...args:Parameters<typeof fs.open>)=>{
      const handle=await fs.open(...args);
      if(String(args[0]).includes("."+stage+".json.")&&String(args[0]).endsWith(".tmp"))handle.sync=async()=>{throw Error("PRIVATE_DISK_DETAIL");};
      return handle;
    }};
    const {journal}=await fixture(t,io);
    const result=await journal.once(identity,{action:"shadow_health",requestId:request},async(...args)=>{signed++;return signer(...args);},async()=>{http++;throw Error("MUST_NOT_CALL");},()=>NOW);
    assert.equal(result.request_id,request);assert.equal(result.outcome,"unknown");assert.equal(http,0);
    assert.equal(signed,stage==="checkpoint"?0:1);assert.ok(!JSON.stringify(result).includes("PRIVATE_DISK"));
  });
}

test("outcome persistence failure after a valid response retains uncertainty and durable original bindings",async t=>{
  const io={...fs,link:async(from:Parameters<typeof fs.link>[0],to:Parameters<typeof fs.link>[1])=>{
    if(String(to).endsWith(".outcome.json"))throw Error("PRIVATE_PERSISTENCE_FAILURE");await fs.link(from,to);
  }};
  const {journal,directory}=await fixture(t,io);let calls=0;
  const result=await journal.once(identity,{action:"shadow_health",requestId:request},signer,async(_url,options)=>{calls++;return response(options,observation());},()=>NOW);
  assert.equal(calls,1);assert.equal(result.outcome,"unknown");assert.equal(result.request_id,request);
  const restarted=new SupervisorJournal(directory);assert.equal((await restarted.readOriginal(request)).outcome,"unknown");
  assert.equal(JSON.parse(await fs.readFile(join(directory,request+".armed.json"),"utf8")).envelope_sha256,result.envelope_sha256);
});

test("invalid caller inputs do not create a directory, sign or invoke HTTP",async t=>{
  const {journal,directory}=await fixture(t);let calls=0;
  for(const input of [{action:"send",requestId:request},{action:"shadow_health",requestId:"bad"},{action:"reconcile",requestId:request},{action:"shadow_health",requestId:request,scope:"global"}]){
    await assert.rejects(journal.once(identity,input as any,async()=>{calls++;throw Error("SIGN");},async()=>{calls++;throw Error("HTTP");},()=>NOW),/SUPERVISOR_ARGUMENTS_INVALID/);
  }
  assert.equal(calls,0);await assert.rejects(fs.stat(directory),{code:"ENOENT"});
});

test("public directory permissions and symlink paths fail closed without signing or HTTP",async t=>{
  const {directory,parent}=await fixture(t);await fs.mkdir(directory,{mode:0o755});let calls=0;
  const run=(journal:SupervisorJournal)=>journal.once(identity,{action:"shadow_health",requestId:request},async()=>{calls++;throw Error("SIGN");},async()=>{calls++;throw Error("HTTP");},()=>NOW);
  assert.equal((await run(new SupervisorJournal(directory))).outcome,"unknown");
  const link=join(parent,"alias");await fs.symlink(directory,link);
  assert.equal((await run(new SupervisorJournal(link))).outcome,"unknown");assert.equal(calls,0);
});

test("invalid signer output cannot arm a request or reach HTTP",async t=>{
  const {journal,directory}=await fixture(t);let calls=0;
  const result=await journal.once(identity,{action:"shadow_health",requestId:request},async()=>({keySha256:"c".repeat(64),signature}),async()=>{calls++;throw Error("HTTP");},()=>NOW);
  assert.equal(result.outcome,"unknown");assert.equal(result.reason_code,"SUPERVISOR_SIGNING_UNAVAILABLE");assert.equal(calls,0);
  await assert.rejects(fs.stat(join(directory,request+".armed.json")),{code:"ENOENT"});
});

test("timeout and malformed lifecycle response never replay and expose only a safe code",async t=>{
  const {journal}=await fixture(t);let calls=0;
  const result=await journal.once(identity,{action:"shadow_health",requestId:request},signer,async()=>{calls++;return new Response('{"PRIVATE_BACKEND_DETAIL":true}',{status:200,headers:{"content-type":"application/json"}});},()=>NOW);
  assert.equal(result.outcome,"unknown");assert.equal(calls,1);assert.ok(!JSON.stringify(result).includes("PRIVATE_BACKEND"));
});

test("missing HTTP response remains unknown after its deadline and does not retry",async t=>{
  const {journal}=await fixture(t);let calls=0;
  const result=await journal.once(identity,{action:"shadow_health",requestId:request},signer,async()=>{calls++;return await new Promise<Response>(()=>{});},()=>NOW,500);
  assert.equal(result.outcome,"unknown");assert.equal(calls,1);assert.equal(result.request_id,request);
  assert.equal(result.reason_code,"SUPERVISOR_OUTCOME_UNKNOWN");
  await journal.once(identity,{action:"shadow_health",requestId:request},signer,async()=>{calls++;throw Error("RETRY");},()=>NOW);
  assert.equal(calls,1);
});

test("an actually killed process leaves a durable UUID reservation that a new process instance cannot replay",async t=>{
  const {directory}=await fixture(t);
  const script=`import {SupervisorJournal} from ${JSON.stringify(new URL("./supervisor_journal.ts",import.meta.url).href)};
    const journal=new SupervisorJournal(process.argv[1]);
    await journal.once(${JSON.stringify(identity)}, {action:'shadow_health',requestId:${JSON.stringify(request)}},
      async()=>{process.stdout.write('RESERVED\\n');return await new Promise(()=>{});},
      async()=>{throw new Error('MUST_NOT_HTTP');},()=>${NOW},15000);`;
  const child=spawn(process.execPath,["--experimental-strip-types","--input-type=module","--eval",script,directory],{env:{},stdio:["ignore","pipe","pipe"]});
  t.after(()=>child.kill());child.stderr.resume();
  await new Promise<void>((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error("SYNTHETIC_CHILD_TIMEOUT")),5000);
    child.on("error",()=>{clearTimeout(timer);reject(Error("SYNTHETIC_CHILD_FAILED"));});
    child.stdout.on("data",data=>{if(data.toString().includes("RESERVED")){clearTimeout(timer);resolve();}});
  });
  child.kill("SIGKILL");await once(child,"exit");
  const restarted=new SupervisorJournal(directory);
  assert.equal((await restarted.readOriginal(request)).outcome,"unknown");let calls=0;
  const result=await restarted.once(identity,{action:"shadow_health",requestId:request},async()=>{calls++;throw Error("SIGN");},async()=>{calls++;throw Error("HTTP");},()=>NOW);
  assert.equal(result.reason_code,"SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED");assert.equal(calls,0);
});

test("manual recorded lookup uses its explicit distinct UUID and never reissues the original action",async t=>{
  const {journal,directory}=await fixture(t);await unknown(journal);const before=await files(directory);let calls=0;
  const restarted=new SupervisorJournal(directory);
  const result=await restarted.reconcile(identity,request,lookup,signer,async(_url,options)=>{
    calls++;const body=JSON.parse(options!.body as string);
    assert.equal(body.action,"reconcile");assert.equal(body.request_id,lookup);assert.deepEqual(body.payload,{target_request_id:request});
    return response(options,{contract_version:1,target_request_id:request,status:"recorded",receipt:observation()});
  },()=>NOW+20000);
  assert.equal(calls,1);assert.equal(result.outcome,"recorded");assert.equal(result.request_id,request);assert.equal(result.lookup_request_id,lookup);
  const after=await files(directory);for(const [name,data]of Object.entries(before))assert.equal(after[name],data);
  assert.equal(JSON.parse(after[lookup+".outcome.json"]!).send_action,false);
  assert.equal((await new SupervisorJournal(directory).readOriginal(request)).outcome,"recorded");
});

test("overlapping lookup callers cannot append an outcome for a UUID they did not reserve",async t=>{
  const {journal,directory}=await fixture(t);await unknown(journal);
  let entered!:()=>void;let release!:()=>void;let calls=0;
  const ready=new Promise<void>(resolve=>{entered=resolve;});const held=new Promise<void>(resolve=>{release=resolve;});
  const first=journal.reconcile(identity,request,lookup,async()=>{entered();await held;return {keySha256:identity.keySha256,signature};},async(_url,options)=>{
    calls++;return response(options,{contract_version:1,target_request_id:request,status:"recorded",receipt:observation()});
  },()=>NOW+180000);
  await ready;const before=await files(directory);
  const duplicate=await new SupervisorJournal(directory).reconcile(identity,request,lookup,async()=>{throw Error("SECOND_SIGN");},async()=>{throw Error("SECOND_HTTP");},()=>NOW+180000);
  assert.equal(duplicate.outcome,"unknown");assert.equal(duplicate.reason_code,"SUPERVISOR_REQUEST_RECONCILIATION_REQUIRED");
  assert.deepEqual(await files(directory),before);
  await assert.rejects(fs.stat(join(directory,lookup+".outcome.json")),{code:"ENOENT"});
  release();assert.equal((await first).outcome,"recorded");assert.equal(calls,1);
  assert.equal(JSON.parse(await fs.readFile(join(directory,lookup+".outcome.json"),"utf8")).outcome,"recorded");
});

test("a later absence cannot contradict an already recorded original observation",async t=>{
  const {journal,directory}=await fixture(t);
  assert.equal((await journal.once(identity,{action:"shadow_health",requestId:request},signer,async(_url,options)=>response(options,observation()),()=>NOW)).outcome,"recorded");
  const before=await files(directory);
  const result=await journal.reconcile(identity,request,lookup,signer,async(_url,options)=>response(options,{contract_version:1,target_request_id:request,status:"not_recorded",receipt:null}),()=>NOW+180000);
  assert.equal(result.outcome,"unknown");assert.equal(result.reason_code,"SUPERVISOR_LOOKUP_UNAVAILABLE");
  assert.equal((await new SupervisorJournal(directory).readOriginal(request)).outcome,"recorded");
  const after=await files(directory);for(const [name,data]of Object.entries(before))assert.equal(after[name],data);
});

test("restart retains a reconciled observation and later negative lookup remains unknown",async t=>{
  const {journal,directory}=await fixture(t);await unknown(journal);
  const first=await journal.reconcile(identity,request,lookup,signer,async(_url,options)=>response(options,{contract_version:1,target_request_id:request,status:"recorded",receipt:observation()}),()=>NOW+180000);
  assert.equal(first.outcome,"recorded");const before=await files(directory);
  const restarted=new SupervisorJournal(directory);assert.equal((await restarted.readOriginal(request)).outcome,"recorded");
  const next="99800000-0000-4000-8000-000000000004";
  const later=await restarted.reconcile(identity,request,next,signer,async(_url,options)=>response(options,{contract_version:1,target_request_id:request,status:"not_recorded",receipt:null}),()=>NOW+240000);
  assert.equal(later.outcome,"unknown");assert.equal(later.reason_code,"SUPERVISOR_LOOKUP_UNAVAILABLE");
  const after=await files(directory);for(const [name,data]of Object.entries(before))assert.equal(after[name],data);
  assert.equal((await restarted.readOriginal(request)).outcome,"recorded");
});

test("missing original signed-time evidence never promotes not_recorded after an arbitrary delay",async t=>{
  const {journal}=await fixture(t);
  const original=await journal.once(identity,{action:"shadow_health",requestId:request},async()=>{throw Error("SIGNING_UNAVAILABLE");},async()=>{throw Error("NO_HTTP");},()=>NOW);
  assert.equal(original.issued_at,null);assert.equal(original.outcome,"unknown");
  const result=await journal.reconcile(identity,request,lookup,signer,async(_url,options)=>response(options,{contract_version:1,target_request_id:request,status:"not_recorded",receipt:null}),()=>NOW+180000);
  assert.equal(result.outcome,"unknown");assert.equal(result.reason_code,"SUPERVISOR_JOURNAL_INTEGRITY_REQUIRED");
});

test("tampered armed readback prevents the first HTTP call after signing",async t=>{
  const io={...fs,link:async(from:Parameters<typeof fs.link>[0],to:Parameters<typeof fs.link>[1])=>{
    await fs.link(from,to);
    if(String(to).endsWith(".armed.json"))await fs.writeFile(to,'{"contract_version":1,"unexpected":"PRIVATE_LOCAL_DETAIL"}\n');
  }};
  const {journal}=await fixture(t,io);let calls=0;
  const result=await journal.once(identity,{action:"shadow_health",requestId:request},signer,async()=>{calls++;throw Error("HTTP");},()=>NOW);
  assert.equal(result.outcome,"unknown");assert.equal(calls,0);assert.equal(result.request_id,request);
  assert.ok(!JSON.stringify(result).includes("PRIVATE_LOCAL"));
});

for(const elapsed of [30000,supervisorNegativeLookupHorizonMs-1,supervisorNegativeLookupHorizonMs,supervisorNegativeLookupHorizonMs+1]){
  test("not_recorded manual lookup at "+elapsed+"ms preserves the conservative original window",async t=>{
    const {journal,directory}=await fixture(t);await unknown(journal);const before=await files(directory);let calls=0;
    const result=await new SupervisorJournal(directory).reconcile(identity,request,lookup,signer,async(_url,options)=>{calls++;return response(options,{contract_version:1,target_request_id:request,status:"not_recorded",receipt:null});},()=>NOW+elapsed);
    assert.equal(result.outcome,elapsed<supervisorNegativeLookupHorizonMs?"unknown":"not_recorded");assert.equal(calls,1);
    assert.equal(result.reason_code,elapsed<supervisorNegativeLookupHorizonMs?"SUPERVISOR_ORIGINAL_REQUEST_WINDOW_OPEN":"SUPERVISOR_ORIGINAL_REQUEST_NOT_RECORDED");
    const after=await files(directory);for(const [name,data]of Object.entries(before))assert.equal(after[name],data);
    let replay=0;
    await journal.once(identity,{action:"shadow_health",requestId:request},async()=>{replay++;throw Error("SIGN");},async()=>{replay++;throw Error("HTTP");},()=>NOW+elapsed);
    assert.equal(replay,0);
  });
}

test("in_progress, authority busy and lookup unavailable retain unknown after the window",async t=>{
  const {journal}=await fixture(t);await unknown(journal);
  const cases=[async(_url:any,options:any)=>response(options,{contract_version:1,target_request_id:request,status:"in_progress",receipt:null}),
    async()=>new Response(JSON.stringify({ok:false,code:"SUPERVISOR_AUTHORITY_BUSY"}),{status:409,headers:{"content-type":"application/json"}}),async()=>{throw Error("PRIVATE_LOOKUP_ERROR");}];
  for(let i=0;i<cases.length;i++){
    const id="99800000-0000-4000-8000-00000000000"+(i+4);
    const result=await journal.reconcile(identity,request,id,signer,cases[i] as typeof fetch,()=>NOW+180000);
    assert.equal(result.outcome,"unknown");assert.ok(!JSON.stringify(result).includes("PRIVATE_LOOKUP"));
    assert.equal(result.reason_code,["SUPERVISOR_ORIGINAL_REQUEST_IN_PROGRESS","SUPERVISOR_AUTHORITY_BUSY","SUPERVISOR_LOOKUP_UNAVAILABLE"][i]);
  }
});

test("a recorded lookup for the wrong original action retains unknown",async t=>{
  const {journal}=await fixture(t);await unknown(journal);
  const result=await journal.reconcile(identity,request,lookup,signer,async(_url,options)=>response(options,{contract_version:1,target_request_id:request,status:"recorded",receipt:observation("prove_key")}),()=>NOW+180000);
  assert.equal(result.outcome,"unknown");assert.equal(result.reason_code,"SUPERVISOR_LOOKUP_UNAVAILABLE");
});

test("manual lookup rejects changed identity, same UUID, and future local time evidence before HTTP",async t=>{
  const {journal,directory}=await fixture(t);await unknown(journal);let calls=0;
  const never:typeof fetch=async()=>{calls++;throw Error("HTTP");};
  await assert.rejects(journal.reconcile({...identity,principalId:lookup},request,lookup,signer,never,()=>NOW),/INTEGRITY_REQUIRED/);
  await assert.rejects(journal.reconcile(identity,request,request,signer,never,()=>NOW),/ARGUMENTS_INVALID/);
  await assert.rejects(journal.reconcile(identity,request,lookup,signer,never,()=>NOW-11000),/INTEGRITY_REQUIRED/);
  assert.equal(calls,0);await assert.rejects(fs.stat(join(directory,lookup+".checkpoint.json")),{code:"ENOENT"});
});

test("malformed, duplicate-key, private-mode and symlink journal records cannot produce a positive local observation",async t=>{
  const {journal,directory,parent}=await fixture(t);await unknown(journal);
  const path=join(directory,request+".outcome.json");const original=await fs.readFile(path);
  const outcome=JSON.parse(original.toString());
  for(const patch of [{outcome:"recorded",observed_at:null},{send_action:true},{principal_id:lookup},{reason_code:"PRIVATE_ERROR"},{unexpected:"PRIVATE_DATA"}]){
    await fs.writeFile(path,JSON.stringify({...outcome,...patch})+"\n");
    await assert.rejects(new SupervisorJournal(directory).readOriginal(request),/INTEGRITY_REQUIRED/);
  }
  await fs.writeFile(path,original.toString().replace('"outcome":"unknown"','"outcome":"recorded","outcome":"unknown"'));
  await assert.rejects(journal.readOriginal(request),/INTEGRITY_REQUIRED/);
  await fs.writeFile(path,original);await fs.chmod(path,0o644);await assert.rejects(journal.readOriginal(request),/INTEGRITY_REQUIRED/);
  await fs.chmod(path,0o600);const saved=join(parent,"saved");await fs.rename(path,saved);await fs.symlink(saved,path);
  await assert.rejects(journal.readOriginal(request),/INTEGRITY_REQUIRED/);
});
