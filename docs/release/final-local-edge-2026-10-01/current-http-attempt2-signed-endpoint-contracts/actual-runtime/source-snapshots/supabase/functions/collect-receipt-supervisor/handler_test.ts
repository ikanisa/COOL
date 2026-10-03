import {createSupervisorHandler, type SupervisorDependencies} from "./handler.ts";
const ID="99800000-0000-4000-8000-000000000001";
const REQUEST="99800000-0000-4000-8000-000000000002";
const TARGET="99800000-0000-4000-8000-000000000003";
const NOW=Date.parse("2026-09-30T23:30:00Z");
const TIME=new Date(NOW).toISOString();
const EXPIRES=new Date(NOW+86400000).toISOString();
const encode=new TextEncoder();
const b64=(b:Uint8Array)=>btoa(String.fromCharCode(...b));
async function digest(b:Uint8Array){return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new Uint8Array(b))),(v)=>v.toString(16).padStart(2,"0")).join("");}
function assert(v:unknown):asserts v{if(!v)throw Error("assertion_failed");}
function equal(a:unknown,b:unknown){assert(JSON.stringify(a)===JSON.stringify(b));}
function der(raw:Uint8Array){
 const parts=[raw.slice(0,32),raw.slice(32)].map(p=>{
  while(p.length>1&&p[0]===0)p=p.slice(1);
  if(p[0]&128)p=Uint8Array.from([0,...p]);
  return Uint8Array.from([2,p.length,...p]);
 });return Uint8Array.from([48,parts[0].length+parts[1].length,...parts[0],...parts[1]]);
}
const envelope=(action="shadow_health",payload:unknown={})=>({contract_version:1,
 audience:"collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt",action,principal_id:ID,
 request_id:REQUEST,issued_at:TIME,payload});
const observation=(action="shadow_health",request=REQUEST)=>({contract_version:1,
 principal_id:ID,request_id:request,action,observed_at:TIME,expires_at:EXPIRES,
 scope:"rw_receipt_shadow",mode:"Shadow",business_handled:false,financial_action:false,
 send_action:false,...(action==="shadow_health"?{sample_valid_until:new Date(NOW+60000).toISOString(),
 queued_count:3,unknown_count:1,failed_no_send_count:2,dispatch_enabled:false}:{})});
async function fixture(state="active",timeout=5000){
 const pair=await crypto.subtle.generateKey({name:"ECDSA",namedCurve:"P-256"},true,["sign","verify"]);
 const spki=new Uint8Array(await crypto.subtle.exportKey("spki",pair.publicKey));
 const keyHash=await digest(spki);const calls:{name:string;args:Record<string,unknown>}[]=[];
 let key:unknown={contract_version:1,principal_id:ID,state,scope:"rw_receipt_shadow",
  public_key_spki_base64:b64(spki),key_sha256:keyHash,expires_at:EXPIRES};
 let result:unknown=observation();let error:{code?:string}|null=null;
 let pendingAt:string|null=null;let aborted=false;
 const dependencies:SupervisorDependencies={now:()=>NOW,timeoutMs:timeout,rpc:async(name,args,signal)=>{
  calls.push({name,args});
  if(name===pendingAt)return await new Promise(resolve=>signal.addEventListener("abort",()=>{
   aborted=true;resolve({data:null,error:{code:"cancelled"}});
  },{once:true}));
  if(error)return{data:null,error};
  return {data:name==="receipt_supervisor_key_v1"?key:result,error:null};
 }};
 const handler=createSupervisorHandler(dependencies);
 async function request(body:unknown=envelope(),patch:Record<string,string>={},raw?:string,method="POST",url="https://example.invalid/supervisor"){
  const bytes=encode.encode(raw??JSON.stringify(body));
  const signature=der(new Uint8Array(await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"},pair.privateKey,new Uint8Array(bytes))));
  return new Request(url,{method,headers:{"content-type":"application/json",
   "X-Collect-Supervisor-Key-Id":keyHash,"X-Collect-Supervisor-Signature":b64(signature),...patch},
   ...(method==="POST"?{body:bytes}:{})});
 }
 return{handler,request,calls,setKey:(v:unknown)=>key=v,key:()=>key,
  setResult:(v:unknown)=>result=v,setError:(v:{code:string})=>error=v,
  setPending:(v:string)=>pendingAt=v,aborted:()=>aborted};
}
Deno.test("real signed P256 health maps only to narrow service RPCs",async()=>{
 const f=await fixture();const r=await f.handler(await f.request());equal(r.status,200);
 equal(f.calls.map(x=>x.name),["receipt_supervisor_key_v1","receipt_supervisor_observe_v1"]);
 const args=f.calls[1].args;equal(args.p_action,"shadow_health");equal(args.p_key_sha256,(f.key()as Record<string,unknown>).key_sha256);
 assert(typeof args.p_request_sha256==="string"&&args.p_request_sha256.length===64);
 equal((await r.json()).result.send_action,false);equal(r.headers.get("cache-control"),"no-store");
});
for(const [name,patch]of Object.entries({principal:{principal_id:"ABCDEF00-0000-4000-8000-000000000001"},request:{request_id:"ABCDEF00-0000-4000-8000-000000000002"},target:{action:"reconcile",payload:{target_request_id:"ABCDEF00-0000-4000-8000-000000000003"}}})){
 Deno.test("canonical lowercase UUID required for "+name+" before RPC",async()=>{
  const f=await fixture();const r=await f.handler(await f.request({...envelope(),...patch}));equal(r.status,400);equal(f.calls.length,0);
 });
}
for(const raw of [String.raw`{"x":"\uXXXX"}`,String.raw`{"x":"\q"}`]){
 Deno.test("malformed string escape remains a client refusal: "+raw,async()=>{
  const f=await fixture();const r=await f.handler(await f.request(undefined,{},raw));equal(r.status,400);equal(await r.json(),{ok:false,code:"SUPERVISOR_REQUEST_INVALID"});equal(f.calls.length,0);
 });
}
Deno.test("oversized streamed body uses supervisor refusal before RPC",async()=>{
 const f=await fixture();const r=await f.handler(await f.request(undefined,{},"x".repeat(8193)));equal(r.status,413);equal(await r.json(),{ok:false,code:"SUPERVISOR_BODY_TOO_LARGE"});equal(f.calls.length,0);
});
Deno.test("pending identity can prove key but cannot read health",async()=>{
 const f=await fixture("pending");f.setResult(observation("prove_key"));
 equal((await f.handler(await f.request(envelope("prove_key")))).status,200);
 equal((await f.handler(await f.request())).status,403);equal(f.calls.filter(x=>x.name==="receipt_supervisor_observe_v1").length,1);
});
for(const [name,patch]of Object.entries({audience:{audience:"other_project"},version:{contract_version:2},
 send:{action:"send"},enqueue:{action:"ensure_receipt"},member:{principal_id:"not_uuid"},
 unknownField:{recipient:"+250788000000"},stale:{issued_at:new Date(NOW-31000).toISOString()},
 future:{issued_at:new Date(NOW+11000).toISOString()},date:{issued_at:"2026-02-30T00:00:00Z"},
 payload:{payload:{destination:"+250788000000"}},reconcile:{action:"reconcile",payload:{target_request_id:"bad"}}})){
 Deno.test("closed signed protocol refuses "+name+" before key lookup",async()=>{
  const f=await fixture();equal((await f.handler(await f.request({...envelope(),...patch}))).status,400);equal(f.calls.length,0);
 });
}
for(const [name,raw]of Object.entries({duplicate:JSON.stringify(envelope()).replace('"action":"shadow_health"','"action":"prove_key","action":"shadow_health"'),
 extraText:JSON.stringify(envelope())+" trailing",bom:"\ufeff"+JSON.stringify(envelope()),
 nested:JSON.stringify({...envelope(),payload:Array.from({length:10}).reduce<Record<string,unknown>>((v)=>({x:v}),{})})})){
 Deno.test("strict byte parser refuses "+name,async()=>{
  const f=await fixture();equal((await f.handler(await f.request(undefined,{},raw))).status,400);equal(f.calls.length,0);
 });
}
Deno.test("signed bytes cannot be modified without losing proof",async()=>{
 const f=await fixture();const original=await f.request();const altered=JSON.stringify({...envelope(),request_id:TARGET});
 const r=await f.handler(new Request(original.url,{method:"POST",headers:original.headers,body:altered}));
 equal(r.status,401);equal(f.calls.length,1);
});
Deno.test("gateway signature envelope cannot authorize supervisor calls",async()=>{
 const f=await fixture();equal((await f.handler(await f.request({contract_version:1,action:"heartbeat",device_id:ID,request_id:REQUEST,issued_at:TIME,payload:{}}))).status,400);equal(f.calls.length,0);
});
for(const [name,patch]of Object.entries({revoked:{state:"revoked"},scope:{scope:"platform_owner"},keyHash:{key_sha256:"a".repeat(64)},
 expiry:{expires_at:TIME},spki:{public_key_spki_base64:"invalid"},secret:{private_key:"secret"}})){
 Deno.test("strict key readback refuses "+name,async()=>{
  const f=await fixture();f.setKey({...f.key()as Record<string,unknown>,...patch});equal((await f.handler(await f.request())).status,401);equal(f.calls.length,1);
 });
}
for(const [name,patch]of Object.entries({send:{send_action:true},finance:{financial_action:true},handled:{business_handled:true},mode:{mode:"Live"},
 principal:{principal_id:TARGET},request:{request_id:TARGET},fraction:{queued_count:1.5},overflow:{queued_count:1e9+1},
 foreignExpiry:{expires_at:new Date(NOW+90000000).toISOString()},futureObservation:{observed_at:new Date(NOW+11000).toISOString()},
 renewedSample:{sample_valid_until:new Date(NOW+61000).toISOString()},privateField:{body:"private"}})){
 Deno.test("post-proof malformed outcome remains unknown: "+name,async()=>{
  const f=await fixture();f.setResult({...observation(),...patch});const r=await f.handler(await f.request());equal(r.status,502);equal((await r.json()).code,"SUPERVISOR_OUTCOME_UNKNOWN");
 });
}
Deno.test("reconciliation uses original request UUID and historical observation",async()=>{
 const f=await fixture();const historical={...observation("shadow_health",TARGET),observed_at:new Date(NOW-100000).toISOString(),sample_valid_until:new Date(NOW-40000).toISOString()};
 f.setResult({contract_version:1,target_request_id:TARGET,status:"recorded",receipt:historical});
 const r=await f.handler(await f.request(envelope("reconcile",{target_request_id:TARGET})));equal(r.status,200);
 equal(f.calls[1].name,"receipt_supervisor_reconcile_v1");equal(f.calls[1].args.p_target_request_id,TARGET);equal((await r.json()).result.receipt.sample_valid_until,historical.sample_valid_until);
});
for(const status of ["not_recorded","in_progress"]){Deno.test("lookup "+status+" conveys no receipt or replay",async()=>{
 const f=await fixture();f.setResult({contract_version:1,target_request_id:TARGET,status,receipt:null});
 equal((await f.handler(await f.request(envelope("reconcile",{target_request_id:TARGET})))).status,200);
});}
Deno.test("mismatched reconciled receipt stays unknown",async()=>{
 const f=await fixture();f.setResult({contract_version:1,target_request_id:TARGET,status:"recorded",receipt:observation()});
 equal((await f.handler(await f.request(envelope("reconcile",{target_request_id:TARGET})))).status,502);
});
Deno.test("readback outage aborts within deadline before service action",async()=>{
 const f=await fixture("active",70);f.setPending("receipt_supervisor_key_v1");const r=await f.handler(await f.request());equal(r.status,503);equal((await r.json()).code,"SUPERVISOR_AUTH_UNAVAILABLE");assert(f.aborted());equal(f.calls.length,1);
});
Deno.test("uncertain post-proof response aborts without retry",async()=>{
 const f=await fixture("active",70);f.setPending("receipt_supervisor_observe_v1");const r=await f.handler(await f.request());equal(r.status,503);equal((await r.json()).code,"SUPERVISOR_OUTCOME_UNKNOWN");assert(f.aborted());equal(f.calls.length,2);
});
for(const [code,status,label]of [["42501",403,"SUPERVISOR_AUTHORITY_REFUSED"],["55P03",409,"SUPERVISOR_AUTHORITY_BUSY"],["22023",409,"SUPERVISOR_REQUEST_REFUSED"],["unknown",503,"SUPERVISOR_AUTH_UNAVAILABLE"]]as const){
 Deno.test("backend "+code+" is redacted",async()=>{
  const f=await fixture();f.setError({code});const r=await f.handler(await f.request());equal(r.status,status);equal(await r.json(),{ok:false,code:label});
 });
}
Deno.test("method query and malformed DER are rejected before database",async()=>{
 const f=await fixture();equal((await f.handler(await f.request(undefined,{},undefined,"GET"))).status,405);
 equal((await f.handler(await f.request(undefined,{},undefined,"POST","https://example.invalid/supervisor?rpc=send"))).status,400);
 equal((await f.handler(await f.request(undefined,{"X-Collect-Supervisor-Signature":b64(new Uint8Array(64))}))).status,400);equal(f.calls.length,0);
});
