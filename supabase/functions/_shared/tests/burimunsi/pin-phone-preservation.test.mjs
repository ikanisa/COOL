import test from 'node:test';import assert from 'node:assert/strict';
import {PinHasher,retainPhoneBoundPin} from '../../domain/burimunsi/pin.js';
import {PostgresNativeAuthStore} from '../../domain/burimunsi/postgres-auth-store.js';
import {NativeAuthService} from '../../domain/burimunsi/auth-service.js';

const oldPhone='+250780000011',newPhone='+250780000012',thirdPhone='+250780000013';
const id='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',rid='33333333-3333-4333-8333-333333333333';
const hasher=new PinHasher({pepper:new Uint8Array(32).fill(27),pepperId:'synthetic'});
test('real PBKDF2 credentials survive an authorized phone move, not a copied or wrong login',async()=>{
 const legacy=await hasher.hash(oldPhone,'0123');assert.equal(await hasher.verify(oldPhone,'0123',legacy),true);
 const moved=retainPhoneBoundPin(legacy,oldPhone,newPhone);
 assert.equal(await hasher.verify(newPhone,'0123',moved),true);
 assert.equal(await hasher.verify(oldPhone,'0123',moved),false);
 assert.equal(await hasher.verify(newPhone,'9999',moved),false);
 const movedAgain=retainPhoneBoundPin(moved,newPhone,thirdPhone);
 assert.equal(movedAgain.phoneBinding.derivationPhone,oldPhone);assert.equal(await hasher.verify(thirdPhone,'0123',movedAgain),true);
 const rotated=await hasher.hash(thirdPhone,'0042');assert.equal(Object.hasOwn(rotated,'phoneBinding'),false);
 assert.equal(await hasher.verify(thirdPhone,'0042',rotated),true);assert.equal(await hasher.verify(thirdPhone,'0123',rotated),false);
});
test('malformed or mismatched protected phone binding fails closed',async()=>{
 const hash=await hasher.hash(oldPhone,'0123'),bound=retainPhoneBoundPin(hash,oldPhone,newPhone);
 for(const phoneBinding of [null,{}, {...bound.phoneBinding,currentPhone:oldPhone},{...bound.phoneBinding,derivationPhone:'invalid'}])
  assert.equal(await hasher.verify(newPhone,'0123',{...bound,phoneBinding}),false);
 assert.throws(()=>retainPhoneBoundPin(bound,oldPhone,thirdPhone),/credential_unavailable/);
 assert.throws(()=>retainPhoneBoundPin({...hash,hash:'bad'},oldPhone,newPhone),/credential_unavailable/);
});
test('self-service PIN rotation after a phone move hashes the new PIN against the current phone',async()=>{
 const legacy=await hasher.hash(oldPhone,'0123');
 const account={id,groupId:'g',phone:newPhone,pinHash:retainPhoneBoundPin(legacy,oldPhone,newPhone),credentialVersion:2,version:2};
 const actor={...account,sessionId:sid,role:'staff',active:true,revoked:false,capabilities:['records.read'],expiresAt:100000};
 const unused=async()=>{throw Error('unexpected call')};
 const store=Object.fromEntries(['findDeviceGrant','createSessionIfCurrent','loadSession','mutateStaff','findStaff','retainedStaffCommand','revokeSession'].map(k=>[k,unused]));
 store.consumeAttempts=async()=>true;store.findAccount=async(g,phone)=>g==='g'&&phone===newPhone?account:null;
 store.changePinIfCurrent=async c=>{assert.equal(c.expectedAccountVersion,2);assert.equal(c.expectedCredentialVersion,2);
  account.pinHash=c.pinHash;account.version++;account.credentialVersion++;return {rotated:true,expiresAt:61000};};
 const service=new NativeAuthService({store,hasher,groupId:'g',clock:()=>1000,sessionTtlMs:60000});
 assert.equal((await service.changePasscode(actor,{current:'0123',newPin:'0042',confirm:'0042',replacementToken:'a'.repeat(64)})).reauthenticationRequired,false);
 assert.equal(Object.hasOwn(account.pinHash,'phoneBinding'),false);
 assert.equal(await hasher.verify(newPhone,'0042',account.pinHash),true);assert.equal(await hasher.verify(newPhone,'0123',account.pinHash),false);
});
function fixture({available=true,denyPhone=null,helperMissing=false,helperDenied=false}={}){
 const calls=[],checks=[];
 const row={id,collection_id:'g',principal_user_id:'staff-principal',role:'staff',removed:false,active:true,version:1,
  credential_version:1,name:'Synthetic staff',phone:oldPhone,capabilities:['records.read'],
  pin_hash:{algorithm:'pbkdf2-sha256+hmac-v1',pepperId:'synthetic',iterations:600000,salt:'a'.repeat(32),hash:'b'.repeat(64)}};
 const actor={id:'44444444-4444-4444-8444-444444444444',sessionId:sid,groupId:'g',role:'admin',active:true,revoked:false,
  capabilities:['records.read','staff.manage'],expiresAt:100000,installationId:'55555555-5555-4555-8555-555555555555'};
 const sql={unsafe:async(q,v=[])=>{calls.push({q,v});
  if(q.startsWith('SELECT * FROM private.burimunsi_accounts'))return[row];
  if(q.startsWith('SELECT private.burimunsi_pin_staff_phone_available')){
   if(helperMissing)throw Object.assign(new Error('synthetic missing migration'),{code:'42883'});
   if(helperDenied)throw Object.assign(new Error('burimunsi_staff_phone_denied'),{code:'42501'});return[{available}];}
  return[];}};
 const db={applicationWork:{assert:async()=>{}},transaction:fn=>fn(sql),context:async()=>{},readContext:async()=>{}};
 const directory={permits:async()=>true,assertInTransaction:async(_sql,input)=>{checks.push(input.phone);if(input.phone===denyPhone)throw Error('access_denied');}};
 const store=new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:async()=>null,operatorDirectory:directory,clock:()=>1000});
 store.write=fn=>fn(sql);store.session=async()=>actor;store.retained=async()=>null;
 return {calls,checks,store,command:{groupId:'g',actorSessionId:sid,actorId:actor.id,requestId:rid,fingerprint:'a'.repeat(64),
  action:'edit',id,expectedVersion:1,phone:newPhone,retainPhoneBoundPin:true}};
}
test('protected phone update checks current and replacement authority then revokes sessions',async()=>{
 const f=fixture();const result=await f.store.mutateStaff(f.command);assert.equal(result.applied,true);
 assert.deepEqual(f.checks,[oldPhone,newPhone]);
 const update=f.calls.find(c=>c.q.startsWith('UPDATE private.burimunsi_accounts SET name'));
 assert.equal(update.v[1],newPhone);assert.deepEqual(update.v[3].phoneBinding,{version:1,derivationPhone:oldPhone,currentPhone:newPhone});
 assert.equal(f.calls.some(c=>c.q.startsWith('UPDATE private.burimunsi_sessions SET revoked=true')),true);
 assert.equal(JSON.stringify(result).includes(oldPhone),false);
});
for(const options of [{available:false},{denyPhone:oldPhone},{denyPhone:newPhone},{helperMissing:true},{helperDenied:true}])
 test('unavailable phone or authority produces no account/session write '+JSON.stringify(options),async()=>{
  const f=fixture(options);await assert.rejects(f.store.mutateStaff(f.command),e=>options.helperDenied?e.code==='access_denied'&&e.status===403:true);
  assert.equal(f.calls.some(c=>c.q.startsWith('UPDATE private.burimunsi_accounts')||c.q.startsWith('UPDATE private.burimunsi_sessions')),false);
 });
