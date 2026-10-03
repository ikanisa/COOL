import { assertEquals } from "../_shared/test_assert.ts";
import { createSuccessorGatewayHandler, type SuccessorDependencies } from "./handler.ts";
import { AUDIENCE, digest, FAMILY, type Json, result, route } from "./wire.ts";
import GRANT from "./fixtures/observed-first-successor-grant.json" with { type: "json" };
import ARM from "./fixtures/observed-first-successor-arm.json" with { type: "json" };
import RECOVERY from "./fixtures/observed-exact-grant-recovery.json" with { type: "json" };
const device = GRANT.device_id;
const encode = new TextEncoder();
const b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
const copy = <T>(v: T): T => structuredClone(v);
function der(raw: Uint8Array): Uint8Array {
 const parts = [raw.slice(0,32),raw.slice(32)].map(p => {while(p.length>1 && p[0]===0) p=p.slice(1);if(p[0]&128)p=Uint8Array.from([0,...p]);return Uint8Array.from([2,p.length,...p]);});
 return Uint8Array.from([48,parts[0].length+parts[1].length,...parts[0],...parts[1]]);
}
function envelope(action: string, id: string, p: Json, issued = GRANT.issued_at): Json {
 return {contract_version:1,protocol_family:FAMILY,audience:AUDIENCE,action,device_id:device,request_id:id,issued_at:issued,payload:p};
}
const armPayload = (): Json => ({route:copy(ARM.route),attempt_id:ARM.attempt_id,fence_version:ARM.fence_version,body_sha256:GRANT.body_sha256,destination_sha256:GRANT.destination_sha256,reservation_sha256:ARM.reservation_sha256,callbacks:Array.from({length:GRANT.segment_count},(_,segment_index)=>({segment_index,sent_callback_id:crypto.randomUUID(),delivery_callback_id:crypto.randomUUID()}))});
async function fixture(value: unknown, now = Date.parse(GRANT.issued_at), state = "active", error: {code?:string}|null = null, forDevice = device) {
 const pair = await crypto.subtle.generateKey({name:"ECDSA",namedCurve:"P-256"},true,["sign","verify"]);
 const spki = new Uint8Array(await crypto.subtle.exportKey("spki",pair.publicKey));const keyId = await digest(spki);const calls:{name:string;args:Json}[]=[];
 const deps:SuccessorDependencies={now:()=>now,timeoutMs:25,rpc:(name,args)=>{calls.push({name,args});return Promise.resolve(name==="gateway_device_key_v1"?{data:{device_id:forDevice,state,public_key_spki_base64:b64(spki),key_sha256:keyId,installation_id:crypto.randomUUID(),signing_certificate_sha256:"f".repeat(64)},error:null}:{data:value,error});}};
 async function signed(e:Json, raw = JSON.stringify(e)) {
  const bytes=encode.encode(raw);const signature=der(new Uint8Array(await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"},pair.privateKey,bytes)));
  return new Request("https://gateway.test/collect-receipt-successor-gateway",{method:"POST",headers:{"content-type":"application/json","X-Collect-Gateway-Key-Id":keyId,"X-Collect-Gateway-Signature":b64(signature)},body:bytes});
 }
 return {calls,signed,deps,handler:createSuccessorGatewayHandler(deps)};
}
Deno.test("actual SQL first-job grant is consumed by strict signed route transport",async()=>{
 const f=await fixture(GRANT);const e=envelope("dispatch_grant",GRANT.request_id,{});const response=await f.handler(await f.signed(e));const body=await response.json();assertEquals(response.status,200);assertEquals(body.result,GRANT);assertEquals(f.calls.map(c=>c.name),["gateway_device_key_v1","gateway_receipt_successor_grant_v1"]);assertEquals(f.calls[1].args.p_request_sha256,await digest(encode.encode(JSON.stringify(e))));assertEquals(body.result.send_authority,false);assertEquals(route(body.result.route),true);
});
Deno.test("actual SQL final arm preserves exact route digest and own authority",async()=>{
 const f=await fixture(ARM,Date.parse(ARM.armed_at));const e=envelope("arm_dispatch",ARM.request_id,armPayload(),ARM.armed_at);const response=await f.handler(await f.signed(e));assertEquals(response.status,200);assertEquals((await response.json()).result,ARM);assertEquals(f.calls[1].name,"gateway_receipt_successor_arm_v1");
});
Deno.test("actual SQL original UUID recovery stays redacted and nonauthorizing",async()=>{
 const id=crypto.randomUUID();const f=await fixture(RECOVERY);const response=await f.handler(await f.signed(envelope("reconcile",id,{target_request_id:GRANT.request_id})));assertEquals(response.status,200);const v=(await response.json()).result;assertEquals(v,RECOVERY);assertEquals(v.send_authority,false);assertEquals("body"in v.recorded_result,false);
});
Deno.test("signed old family version and audience cannot reach new RPCs",async()=>{
 for(const patch of [{protocol_family:"primary_v1"},{contract_version:2},{audience:"collect-android-gateway"},{action:"callback"},{extra:true}]){
  const f=await fixture(GRANT);const response=await f.handler(await f.signed({...envelope("dispatch_grant",GRANT.request_id,{}),...patch}));assertEquals(response.status,400);assertEquals(f.calls.length,0);
 }
});
Deno.test("signed duplicate JSON keys are rejected before verification",async()=>{
 const f=await fixture(GRANT);const e=envelope("dispatch_grant",GRANT.request_id,{});const text=JSON.stringify(e).replace('"contract_version":1','"contract_version":1,"contract_version":1');assertEquals((await f.handler(await f.signed(e,text))).status,400);assertEquals(f.calls.length,0);
});
Deno.test("old ordinary receipt_id alias and permissive result extras are unknown",async()=>{
 for(const patch of [{receipt_id:GRANT.route.dispatch_job_id},{route:{...GRANT.route,extra:true}},{route:{...GRANT.route,dispatch_job_id:GRANT.route.primary_receipt_id}},{body:GRANT.body+" "},{send_authority:true}]){
  const f=await fixture({...GRANT,...patch});const response=await f.handler(await f.signed(envelope("dispatch_grant",GRANT.request_id,{})));assertEquals(response.status,502);assertEquals((await response.json()).send_authority,false);
 }
});
Deno.test("final arm changed route or reservation cannot validate",async()=>{
 for(const patch of [{route:{...ARM.route,approval_id:crypto.randomUUID()}},{reservation_sha256:"0".repeat(64)},{send_authority:false},{carrier_proof:true}])assertEquals(await result("arm_dispatch",{...ARM,...patch},device,ARM.request_id,armPayload(),Date.parse(ARM.armed_at)),false);
});
Deno.test("final arm repeated callback IDs cannot reach SQL",async()=>{
 const f=await fixture(ARM,Date.parse(ARM.armed_at));const p=armPayload();const cb=(p.callbacks as Json[])[0];cb.delivery_callback_id=cb.sent_callback_id;const response=await f.handler(await f.signed(envelope("arm_dispatch",ARM.request_id,p,ARM.armed_at)));assertEquals(response.status,400);assertEquals(f.calls.length,0);
});
Deno.test("redacted arm replay never reconstructs authority",async()=>{
 const refusal={contract_version:1,protocol_family:FAMILY,ok:false,code:"ORIGINAL_REQUEST_RECORDED",device_id:device,request_id:ARM.request_id,replay:true,send_authority:false,carrier_proof:false,delivery_proven:false};const f=await fixture(refusal,Date.parse(ARM.armed_at));const response=await f.handler(await f.signed(envelope("arm_dispatch",ARM.request_id,armPayload(),ARM.armed_at)));assertEquals(response.status,200);assertEquals((await response.json()).result.send_authority,false);
});
Deno.test("revoked device permits readonly original lookup and refuses arm",async()=>{
 const f=await fixture(ARM,Date.parse(ARM.armed_at),"revoked");assertEquals((await f.handler(await f.signed(envelope("arm_dispatch",ARM.request_id,armPayload(),ARM.armed_at)))).status,403);assertEquals(f.calls.length,1);const read=await fixture(RECOVERY,Date.parse(GRANT.issued_at),"revoked");assertEquals((await read.handler(await read.signed(envelope("reconcile",crypto.randomUUID(),{target_request_id:GRANT.request_id})))).status,200);
});
Deno.test("expired grant result is unknown without body release",async()=>{
 const f=await fixture(GRANT,Date.parse(GRANT.expires_at)+1);const response=await f.handler(await f.signed(envelope("dispatch_grant",GRANT.request_id,{},GRANT.expires_at)));assertEquals(response.status,502);assertEquals("result"in await response.json(),false);
});
Deno.test("unknown lookup cannot invent a route or recorded receipt",async()=>{
 const target=crypto.randomUUID();const v={contract_version:1,protocol_family:FAMILY,target_request_id:target,outcome:"unknown",recorded_action:null,recorded_route:null,recorded_result:null,send_authority:false,carrier_proof:false,delivery_proven:false};assertEquals(await result("reconcile",v,device,crypto.randomUUID(),{target_request_id:target},Date.parse(GRANT.issued_at)),true);assertEquals(await result("reconcile",{...v,recorded_route:GRANT.route},device,crypto.randomUUID(),{target_request_id:target},Date.parse(GRANT.issued_at)),false);
});
Deno.test("known refusal recovery retains actual refusal rather than empty success",async()=>{
 const target=crypto.randomUUID();const refused={contract_version:1,protocol_family:FAMILY,ok:false,code:"SUCCESSORS_DISABLED",device_id:device,request_id:target,replay:false,send_authority:false,carrier_proof:false,delivery_proven:false};const v={contract_version:1,protocol_family:FAMILY,target_request_id:target,outcome:"recorded",recorded_action:"dispatch_grant",recorded_route:null,recorded_result:refused,send_authority:false,carrier_proof:false,delivery_proven:false};assertEquals(await result("reconcile",v,device,crypto.randomUUID(),{target_request_id:target},Date.parse(GRANT.issued_at)),true);
});
Deno.test("signed backend denial is explicit and grants no response authority",async()=>{
 for(const code of ["42501","22023","55000","XX000"]){const f=await fixture(null,Date.parse(GRANT.issued_at),"active",{code});const response=await f.handler(await f.signed(envelope("dispatch_grant",GRANT.request_id,{})));assertEquals(response.status,code==="42501"?403:code==="XX000"?503:409);assertEquals((await response.json()).send_authority,false);}
});

import CALLBACKS from "./fixtures/observed-multipart-callbacks.json" with { type: "json" };
import OBSGRANT from "./fixtures/observed-successor-grant.json" with { type: "json" };
import ACK from "./fixtures/observed-exact-successor-archive-ack.json" with { type: "json" };
import STATUS from "./fixtures/observed-armed-status.json" with { type: "json" };
import LATESTATUS from "./fixtures/observed-late-conflicting-status.json" with { type: "json" };
import LATERECOVERY from "./fixtures/observed-late-original-request-recovery.json" with { type: "json" };
import INCOMPLETE from "./fixtures/observed-incomplete-archive.json" with { type: "json" };
const archivePayload = (): Json => ({route:ACK.route,attempt_id:ACK.attempt_id,fence_version:ACK.fence_version,body_sha256:ACK.body_sha256,destination_sha256:ACK.destination_sha256,callback_requests:ACK.callback_requests});
Deno.test("actual SQL callback observations survive revoked device and exact route", async()=>{
 for(const cb of CALLBACKS){const f=await fixture(cb.result,Date.parse(cb.result.recorded_at),"revoked",null,OBSGRANT.device_id);const e={...envelope("callback",cb.request_id,cb.payload,cb.result.recorded_at),device_id:OBSGRANT.device_id};const r=await f.handler(await f.signed(e));assertEquals(r.status,200);assertEquals((await r.json()).result,cb.result);assertEquals(f.calls[1].name,"gateway_receipt_successor_callback_v1");}
});
Deno.test("actual SQL current and late contradictory status remain nonauthorizing", async()=>{
 for(const st of [STATUS,LATESTATUS]){const id=crypto.randomUUID();const p={route:st.route,attempt_id:st.attempt_id,fence_version:st.fence_version};const f=await fixture(st,Date.parse(OBSGRANT.issued_at),"revoked",null,OBSGRANT.device_id);const r=await f.handler(await f.signed({...envelope("attempt_status",id,p,OBSGRANT.issued_at),device_id:OBSGRANT.device_id}));assertEquals(r.status,200);assertEquals((await r.json()).result,st);assertEquals(f.calls[1].name,"gateway_receipt_successor_attempt_status_v1");}
});
Deno.test("actual SQL archive ACK binds exact callback originals without delivery claim",async()=>{
 const f=await fixture(ACK,Date.parse(ACK.recorded_at),"revoked",null,OBSGRANT.device_id);const r=await f.handler(await f.signed({...envelope("archive_attempt",ACK.request_id,archivePayload(),ACK.recorded_at),device_id:OBSGRANT.device_id}));assertEquals(r.status,200);assertEquals((await r.json()).result,ACK);assertEquals(f.calls[1].name,"gateway_receipt_successor_archive_v1");assertEquals(ACK.delivery_proven,false);
});
Deno.test("actual SQL incomplete archive remains an explicit immutable refusal",async()=>{
 assertEquals(await result("archive_attempt",INCOMPLETE,INCOMPLETE.device_id,INCOMPLETE.request_id,archivePayload(),Date.parse(ACK.recorded_at)),true);
});
Deno.test("actual late original UUID reconciliation keeps contradictory facts",async()=>{
 const id=crypto.randomUUID();const f=await fixture(LATERECOVERY,Date.parse(OBSGRANT.issued_at),"revoked",null,OBSGRANT.device_id);const r=await f.handler(await f.signed({...envelope("reconcile",id,{target_request_id:LATERECOVERY.target_request_id},OBSGRANT.issued_at),device_id:OBSGRANT.device_id}));assertEquals(r.status,200);assertEquals((await r.json()).result,LATERECOVERY);
});
Deno.test("callback route and closed facts cannot invent delivery or send permission",async()=>{
 const cb=CALLBACKS[0];for(const patch of [{delivery_proven:true},{send_authority:true},{extra:true},{route:{...cb.result.route,dispatch_job_id:crypto.randomUUID()}},{sent_observations:11}])assertEquals(await result("callback",{...cb.result,...patch},OBSGRANT.device_id,cb.request_id,cb.payload,Date.parse(cb.result.recorded_at)),false);
});
Deno.test("archive altered exact original references and old receipt aliases are refused",async()=>{
 for(const patch of [{receipt_id:ACK.route.dispatch_job_id},{callback_requests:ACK.callback_requests.map((v,i)=>i? v:{...v,request_sha256:"0".repeat(64)})},{route:{...ACK.route,approval_id:crypto.randomUUID()}},{journal_ack:false}])assertEquals(await result("archive_attempt",{...ACK,...patch},OBSGRANT.device_id,ACK.request_id,archivePayload(),Date.parse(ACK.recorded_at)),false);
});
Deno.test("recorded callback and archive reconciliation rejects permissive nested results",async()=>{
 const p={target_request_id:LATERECOVERY.target_request_id};for(const patch of [{recorded_result:{...LATERECOVERY.recorded_result,extra:true}},{recorded_route:{...LATERECOVERY.recorded_route,approval_id:crypto.randomUUID()}},{recorded_result:{...LATERECOVERY.recorded_result,send_authority:true}}])assertEquals(await result("reconcile",{...LATERECOVERY,...patch},OBSGRANT.device_id,crypto.randomUUID(),p,Date.parse(OBSGRANT.issued_at)),false);
});
Deno.test("wrong exact signature never reaches the mutation RPC",async()=>{
 const f=await fixture(GRANT);const request=await f.signed(envelope("dispatch_grant",GRANT.request_id,{}));const h=new Headers(request.headers);h.set("X-Collect-Gateway-Signature",b64(der(new Uint8Array(64).fill(1))));const r=await f.handler(new Request(request.url,{method:"POST",headers:h,body:await request.arrayBuffer()}));assertEquals(r.status,401);assertEquals(f.calls.length,1);
});
Deno.test("bounded SQL timeout returns unknown and performs one mutation invocation",async()=>{
 const f=await fixture(GRANT);let mutations=0;const timed=createSuccessorGatewayHandler({...f.deps,timeoutMs:5,rpc:(name,args,signal)=>{if(name==="gateway_device_key_v1")return f.deps.rpc(name,args,signal);mutations++;return new Promise(()=>{});}});const r=await timed(await f.signed(envelope("dispatch_grant",GRANT.request_id,{})));assertEquals(r.status,504);assertEquals((await r.json()).send_authority,false);assertEquals(mutations,1);assertEquals(f.calls.length,1);
});
Deno.test("oversized and malformed UTF8 bodies are rejected before key discovery",async()=>{
 const f=await fixture(GRANT);for(const bytes of [new Uint8Array(8193).fill(32),new Uint8Array([0xff,0xfe])]){const r=await f.handler(new Request("https://gateway.test",{method:"POST",headers:{"content-type":"application/json"},body:bytes}));assertEquals([400,413].includes(r.status),true);}assertEquals(f.calls.length,0);
});
