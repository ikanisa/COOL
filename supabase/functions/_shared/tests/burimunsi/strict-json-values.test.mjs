import test from 'node:test';
import assert from 'node:assert/strict';
import {parseWire} from '../../domain/burimunsi/wire/runtime.mjs';
import {canonicalJson,exactKeys,sha256} from '../../domain/burimunsi/values.js';
import {NativeAuthService} from '../../domain/burimunsi/auth-service.js';
import {GatewayRegistry} from '../../domain/burimunsi/gateway-registry.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';

test('strict null-prototype and ordinary JSON objects have identical validation and canonical fingerprints',async()=>{
 const parsed=parseWire('{"z":{"b":2,"a":1},"a":[{"v":3}]}'),plain={a:[{v:3}],z:{a:1,b:2}};
 assert.equal(Object.getPrototypeOf(parsed),null);assert.equal(Object.getPrototypeOf(parsed.z),null);
 assert.equal(exactKeys(parsed,['a','z']),parsed);assert.equal(exactKeys(plain,['a','z']),plain);
 assert.equal(canonicalJson(parsed),canonicalJson(plain));assert.equal(await sha256(canonicalJson(parsed)),await sha256(canonicalJson(plain)));
});
for(const body of [[],new Date(),Object.create({inherited:true}),Object.create({a:1}),null,42])
 test('non-JSON or custom-prototype command objects are rejected '+String(body),()=>assert.throws(()=>exactKeys(body,['a']),/invalid_request/));
test('custom-prototype objects remain invalid inside canonical JSON',()=>assert.throws(()=>canonicalJson({safe:Object.create({bad:true})}),/invalid_json/));
for(const key of ['__proto__','constructor','prototype','extra'])
 test('strict extra or prototype-pollution key is refused: '+key,()=>{
  const body=parseWire('{"a":1,"'+key+'":{"polluted":true}}');
  assert.throws(()=>exactKeys(body,['a']),/invalid_request/);assert.equal({}.polluted,undefined);
 });
test('duplicate JSON keys remain refused by strict parser',()=>assert.throws(()=>parseWire('{"a":1,"a":2}'),/CONTRACT_DUPLICATE_KEY/));

const id='00000000-0000-4000-8000-000000000001',session='00000000-0000-4000-8000-000000000002';
const installation='00000000-0000-4000-8000-000000000003',groupId='group-1',now=1794132000000;
const actor={id,sessionId:session,groupId,principalUserId:'principal-1',installationId:installation,
 role:'admin',active:true,revoked:false,expiresAt:now+60000,capabilities:['records.read','staff.manage']};
function fixture(defaultStaffPin=undefined){
 const calls={staff:0,pair:0,replace:0};
 const unused=async()=>{};
 const store=Object.fromEntries(['consumeAttempts','findAccount','findDeviceGrant','createSessionIfCurrent','changePinIfCurrent','findStaff','revokeSession'].map(k=>[k,unused]));
 store.loadSession=async()=>actor;store.retainedStaffCommand=async()=>null;
 store.mutateStaff=async()=>{calls.staff++;return {applied:true,id:'staff-1',version:1}};
 const hasher={hash:async(_phone,pin)=>{calls.hashedPin=pin;return {fixture:true}},verify:async()=>true,commandFingerprint:async value=>sha256(value)};
 const auth=new NativeAuthService({store,hasher,groupId,clock:()=>now,defaultStaffPin});
 const gateway=new GatewayRegistry({groupId,clock:()=>now,store:{withAuthorityTransaction:unused,withReadSnapshot:unused,
  pair:async()=>{calls.pair++;return {binding:{id:'binding-1',owner_user_id:'principal-1',receiving_account_id:'account-1',
   collection_id:groupId,version:1,provider:'fixture',public_code:'00000',recipient_name:'Fixture',
   currency:'RWF',timezone:'Africa/Kigali',subscription_id:1,created_at:'2026-11-11T00:00:00Z'},gateway_token:'b'.repeat(64)}},
  retire:async(_actor,command)=>{calls.replace++;return {retired:true,handoffId:'00000000-0000-4000-8000-000000000004',requestId:command.requestId,reauthenticationRequired:true}}}});
 const h=createNativeHandler({auth,records:{home:unused,page:unused,detail:unused,exportLedger:unused,commandStatus:unused},
  contributions:{allocate:unused},members:{enroll:unused,setActive:unused},gateway,origin:'https://example.test',networkBucket:unused,strictContract:true,groupId});
 const request=(path,body)=>new Request('https://example.test/v1/burimunsi'+path,{method:'POST',headers:{
  'content-type':'application/json','authorization':'Bearer '+'a'.repeat(64),'x-burimunsi-installation':installation,
  'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':crypto.randomUUID(),'x-burimunsi-generation':'1'},body:typeof body==='string'?body:JSON.stringify(body)});
 return {h,request,calls};
}
test('strict HTTP staff creation reaches the actual auth service',async()=>{
 const {h,request,calls}=fixture();
 const response=await h(request('/staff',{action:'create',phone:'+250780000006',pin:'4682',name:'Synthetic Staff',
  capabilities:['records.read'],requestId:crypto.randomUUID()}));
 assert.equal(response.status,200);assert.equal((await response.json()).data.applied,true);assert.equal(calls.staff,1);
});
test('strict HTTP staff creation uses the server default when no passcode is supplied',async()=>{
 const {h,request,calls}=fixture('1357');
 const response=await h(request('/staff',{action:'create',phone:'+250780000006',name:'Synthetic Staff',
  capabilities:['records.read'],requestId:crypto.randomUUID()}));
 const result=await response.json();assert.equal(response.status,200);assert.equal(result.data.applied,true);
 assert.equal(calls.staff,1);assert.equal(calls.hashedPin,'1357');assert.equal(JSON.stringify(result).includes('1357'),false);
});
test('strict HTTP gateway pair and replacement reach actual gateway registry',async()=>{
 const {h,request,calls}=fixture();
 let response=await h(request('/gateway/pair',{pairingCode:'a'.repeat(64),replace:false,requestId:crypto.randomUUID()}));
 assert.equal(response.status,200);assert.equal(calls.pair,1);
 response=await h(request('/gateway/replace',{replacementCode:'a'.repeat(64),requestId:crypto.randomUUID()}));
 assert.equal(response.status,200);assert.equal(calls.replace,1);
});
for(const key of ['__proto__','constructor','prototype','extra'])test('strict staff HTTP rejects extra '+key+' before any staff write',async()=>{
 const {h,request,calls}=fixture();
 const body='{"action":"create","phone":"+250780000006","pin":"4682","name":"Synthetic Staff","capabilities":["records.read"],"requestId":"'+crypto.randomUUID()+'","'+key+'":{}}';
 const response=await h(request('/staff',body));assert.equal(response.status,400);assert.equal(calls.staff,0);assert.equal({}.polluted,undefined);
});
