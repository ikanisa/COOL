import test from "node:test";
import assert from "node:assert/strict";
import {generateKeyPairSync, createHash, sign} from "node:crypto";
import {readFile} from "node:fs/promises";
import {callSupervisor, supervisorAudience, type SupervisorIdentity, type SupervisorSigner, type SupervisorRequest} from "./supervisor_client.ts";
import {createSupervisorHandler} from "../../../supabase/functions/collect-receipt-supervisor/handler.ts";
const id="99800000-0000-4000-8000-000000000001",request="99800000-0000-4000-8000-000000000002",target="99800000-0000-4000-8000-000000000003";
const now=Date.parse("2026-10-01T00:00:00Z"),expiry=new Date(now+86400000).toISOString();
const input:SupervisorRequest={action:"shadow_health",requestId:request};
async function fixture() {
  const pair=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
  const spki=pair.publicKey.export({format:"der",type:"spki"});const keyHash=createHash("sha256").update(spki).digest("hex");
  const identity:SupervisorIdentity={principalId:id,keySha256:keyHash,expiresAt:expiry};
  let rpcCalls=0,httpCalls=0;let original:Uint8Array|null=null;
  const observation=(action="shadow_health",requestId=request)=>({contract_version:1,principal_id:id,request_id:requestId,action,
    observed_at:new Date(now).toISOString(),expires_at:expiry,scope:"rw_receipt_shadow",mode:"Shadow",business_handled:false,
    financial_action:false,send_action:false,...(action==="shadow_health"?{sample_valid_until:new Date(now+60000).toISOString(),queued_count:2,unknown_count:0,failed_no_send_count:1,dispatch_enabled:false}:{})});
  let result:unknown=observation();
  const handler=createSupervisorHandler({now:()=>now,rpc:async(name)=>{
    rpcCalls++;
    return {data:name==="receipt_supervisor_key_v1"?{contract_version:1,principal_id:id,key_sha256:keyHash,
      public_key_spki_base64:spki.toString("base64"),scope:"rw_receipt_shadow",state:"active",expires_at:expiry}:result,error:null};
  }});
  const signer:SupervisorSigner=async(bytes)=>{original=bytes;return{keySha256:keyHash,signature:sign("sha256",bytes,pair.privateKey).toString("base64")};};
  const fetcher:typeof fetch=async(url,options)=>{
    httpCalls++;assert.equal(url,"https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-supervisor");
    assert.equal(options?.redirect,"error");assert.equal(options?.cache,"no-store");
    const headers=new Headers(options?.headers);assert.equal(headers.has("authorization"),false);assert.equal(headers.has("apikey"),false);
    assert.equal(options?.body,new TextDecoder().decode(original!));
    return handler(new Request(url,options));
  };
  return{identity,signer,fetcher,observation,setResult:(v:unknown)=>result=v,calls:()=>({rpcCalls,httpCalls}),bytes:()=>original};
}
test("dedicated client and Edge verify real signed canonical bytes without operator credentials",async()=>{
  const f=await fixture();const result=await callSupervisor(f.identity,input,f.signer,f.fetcher,()=>now);
  assert.equal(result.result.send_action,false);assert.deepEqual(f.calls(),{rpcCalls:2,httpCalls:1});
  const text=new TextDecoder().decode(f.bytes()!);const body=JSON.parse(text);
  assert.equal(body.audience,supervisorAudience);assert.deepEqual(Object.keys(body),Object.keys(body).sort());
  assert.equal(body.request_id,request);assert.equal(body.action,"shadow_health");
});
test("key possession proof is explicit and creates no sender authority",async()=>{
  const f=await fixture();f.setResult(f.observation("prove_key"));
  assert.equal((await callSupervisor(f.identity,{action:"prove_key",requestId:request},f.signer,f.fetcher,()=>now)).result.send_action,false);
});
for(const [name,bad]of Object.entries({send:{...input,action:"send"},missing:{action:"shadow_health"},unknown:{...input,recipient:"+250788000000"},invalid:{...input,requestId:"bad"},
  lookupMissing:{action:"reconcile",requestId:request},lookupOriginal:{action:"reconcile",requestId:request,targetRequestId:request},uppercase:{...input,requestId:"ABCDEF00-0000-4000-8000-000000000001"},null:null})){
  test("client rejects "+name+" before signer or network",async()=>{
    const f=await fixture();let signed=0;
    await assert.rejects(callSupervisor(f.identity,bad as SupervisorRequest,async()=>{signed++;return f.signer(new Uint8Array(),new AbortController().signal);},f.fetcher,()=>now),/SUPERVISOR_ARGUMENTS_INVALID/);
    assert.equal(signed,0);assert.equal(f.calls().httpCalls,0);
  });
}
for(const [name,patch]of Object.entries({expired:{expiresAt:new Date(now).toISOString()},nearExpiry:{expiresAt:new Date(now+4999).toISOString()},badKey:{keySha256:"secret"},uppercase:{principalId:"ABCDEF00-0000-4000-8000-000000000001"},badDate:{expiresAt:"2026-02-30T00:00:00Z"},unknown:{operatorToken:"secret"}})){
  test("client rejects identity "+name+" before signing",async()=>{
    const f=await fixture();await assert.rejects(callSupervisor({...f.identity,...patch},input,f.signer,f.fetcher,()=>now),/SUPERVISOR_ARGUMENTS_INVALID/);
    assert.equal(f.calls().httpCalls,0);
  });
}
test("local key mismatch never reaches endpoint",async()=>{
  const f=await fixture();await assert.rejects(callSupervisor(f.identity,input,async b=>({...await f.signer(b,new AbortController().signal),keySha256:"b".repeat(64)}),f.fetcher,()=>now),/SUPERVISOR_SIGNING_UNAVAILABLE/);assert.equal(f.calls().httpCalls,0);
});
test("signature modification fails at real Edge verifier",async()=>{
  const f=await fixture();await assert.rejects(callSupervisor(f.identity,input,async b=>({...await f.signer(b,new AbortController().signal),signature:Buffer.alloc(8).toString("base64")}),f.fetcher,()=>now),/SUPERVISOR_REQUEST_INVALID/);
  assert.equal(f.calls().rpcCalls,0);
});
for(const [name,patch]of Object.entries({send:{send_action:true},handled:{business_handled:true},finance:{financial_action:true},mode:{mode:"Live"},destination:{recipient:"private"},expiredSample:{sample_valid_until:new Date(now).toISOString()}})){
  test("unsafe or stale observation "+name+" preserves unknown outcome",async()=>{
    const f=await fixture();f.setResult({...f.observation(),...patch});await assert.rejects(callSupervisor(f.identity,input,f.signer,f.fetcher,()=>now),/SUPERVISOR_OUTCOME_UNKNOWN/);assert.equal(f.calls().httpCalls,1);
  });
}
test("uncertain network outcome is never retried or replaced with a new UUID",async()=>{
  const f=await fixture();let attempts=0;
  await assert.rejects(callSupervisor(f.identity,input,f.signer,async()=>{attempts++;throw Error("private network detail");},()=>now),/^Error: SUPERVISOR_OUTCOME_UNKNOWN$/);assert.equal(attempts,1);
});
test("signature timeout performs no HTTP request",async()=>{
  const f=await fixture();await assert.rejects(callSupervisor(f.identity,input,async()=>await new Promise(()=>{}),f.fetcher,()=>now,20),/SUPERVISOR_SIGNING_UNAVAILABLE/);assert.equal(f.calls().httpCalls,0);
});
test("response stream timeout keeps original request unresolved",async()=>{
  const f=await fixture();let calls=0;
  const fetcher:typeof fetch=async()=>{calls++;return new Response(new ReadableStream({start(){},cancel(){}}),{headers:{"content-type":"application/json"}});};
  await assert.rejects(callSupervisor(f.identity,input,f.signer,fetcher,()=>now,30),/SUPERVISOR_OUTCOME_UNKNOWN/);assert.equal(calls,1);
});
for(const status of ["recorded","not_recorded","in_progress"]){
  test("manual lookup "+status+" retains original request and does not replay health",async()=>{
    const f=await fixture();const receipt=status==="recorded"?{...f.observation("shadow_health",target),observed_at:new Date(now-100000).toISOString(),sample_valid_until:new Date(now-40000).toISOString()}:null;
    f.setResult({contract_version:1,target_request_id:target,status,receipt});
    const response=await callSupervisor(f.identity,{action:"reconcile",requestId:request,targetRequestId:target},f.signer,f.fetcher,()=>now);
    assert.equal(response.result.status,status);assert.equal(JSON.parse(new TextDecoder().decode(f.bytes()!)).payload.target_request_id,target);assert.equal(f.calls().httpCalls,1);
  });
}
test("lookup transport failure cannot be treated as a missing receipt",async()=>{
  const f=await fixture();await assert.rejects(callSupervisor(f.identity,{action:"reconcile",requestId:request,targetRequestId:target},f.signer,async()=>{throw Error("secret");},()=>now),/^Error: SUPERVISOR_LOOKUP_UNAVAILABLE$/);
});
test("unrecognized server errors reveal no raw text",async()=>{
  const f=await fixture();const fetcher:typeof fetch=async()=>new Response(JSON.stringify({error:"private"}),{status:500,headers:{"content-type":"application/json"}});
  await assert.rejects(callSupervisor(f.identity,input,f.signer,fetcher,()=>now),/^Error: SUPERVISOR_OUTCOME_UNKNOWN$/);
});
test("actual synthetic SQL health shape reaches client without timestamp renewal",async()=>{
  const health=JSON.parse(await readFile(new URL("../../../supabase/functions/collect-receipt-supervisor/fixtures/observed-health.json",import.meta.url),"utf8"));
  const f=await fixture();const sampled=Date.parse(health.observed_at);const identity={...f.identity,principalId:health.principal_id,expiresAt:health.expires_at};
  const fetcher:typeof fetch=async()=>new Response(JSON.stringify({contract_version:1,principal_id:health.principal_id,request_id:health.request_id,action:"shadow_health",result:health}),{headers:{"content-type":"application/json"}});
  const result=await callSupervisor(identity,{action:"shadow_health",requestId:health.request_id},f.signer,fetcher,()=>sampled);
  assert.deepEqual(result.result,health);
});
