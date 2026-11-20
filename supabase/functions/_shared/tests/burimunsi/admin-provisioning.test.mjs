// Real PinHasher/encryption, source adapter and transaction ownership checks.
// Procedure results below are explicit doubles, not PostgreSQL/RLS qualification.
import test from 'node:test';import assert from 'node:assert/strict';
import {AdminNativeProvisioning,provisioningCommand} from '../../domain/burimunsi/admin-provisioning.js';
import {nativePinHasher} from '../../domain/burimunsi/native-secrets.js';
import {digest} from '../../domain/core.js';

const G='provisioning-fixture',P='31000000-0000-4000-8000-000000000001',A='31000000-0000-4000-8000-000000000002';
const S='31000000-0000-4000-8000-000000000003',R='31000000-0000-4000-8000-000000000004',D='31000000-0000-4000-8000-000000000005';
const pepper=Buffer.alloc(32,37).toString('base64');
const pin=()=>({operation:'set_pin',requestId:R,collectionId:G,scopeVersion:2,principalId:P,approvalVersion:3,
 expectedAccountVersion:0,reason:'Initial owner setup',pin:'8492'});
const grant=()=>({operation:'grant_installation',requestId:R,collectionId:G,scopeVersion:2,principalId:P,approvalVersion:3,
 expectedAccountVersion:4,accountId:A,grantId:null,installationId:D,profile:'staff',expectedGrantVersion:0,reason:'Approved managed installation'});
function fixture(){
 const state={queries:[],receipt:null,record:null,ciphertext:null,denied:false,lostCommit:false,revoked:false};
 const db={applicationWork:{assert:async()=>{if(state.revoked)throw Error('request_revoked');}},
  context:async()=>{state.context=(state.context??0)+1;},readContext:async()=>{throw Error('Owner helper requires guarded write context');},
  transaction:async fn=>{
   const before=structuredClone({receipt:state.receipt,record:state.record,ciphertext:state.ciphertext});
   let result;try{result=await fn(sql);}catch(e){Object.assign(state,before);throw e;}
   if(state.lostCommit&&before.receipt===null&&state.receipt!==null){state.lostCommit=false;throw Error('Synthetic lost COMMIT response');}return result;
  }};
 const sql={unsafe:async(q,args=[])=>{
  state.queries.push({q,args});if(q.startsWith('SELECT pg_advisory')||q.startsWith('SELECT set_config'))return [];
  assert.equal(args[0],A);assert.equal(args[1],'a'.repeat(64));assert.equal(args[4],G);
  if(state.denied)throw Error('admin_invitation_authority');
  const lookup=()=>({contractVersion:1,collectionId:G,requestId:R,found:!!state.receipt,...(state.receipt?{receipt:state.receipt}:{})});
  if(q.includes('_lookup('))return [{result:lookup()}];
  if(q.includes('_directory('))return [{result:{contractVersion:1,collectionId:G,configured:true,scopeEnabled:false,scopeVersion:2,
   accounts:[{principalId:P,accountId:null,phone:'+250780000002',name:'QA approved operator',role:'staff',capabilities:['records.read'],
    approvalVersion:3,approved:true,version:0,credentialVersion:0,active:false,removed:false}],grants:[]}}];
  if(q.includes('_cancel(')){
   state.receipt??={contractVersion:1,collectionId:G,requestId:R,operation:'cancelled',applied:false};return [{result:state.receipt}];
  }
  if(q.includes('_delivery('))return [{result:{receipt:state.receipt,ciphertext:state.ciphertext,tokenHash:state.record.tokenHash}}];
  assert(q.includes('_apply('));const c=JSON.parse(args[5]);
  if(state.receipt){if(args[6]!==state.fingerprint||state.receipt.operation!==c.operation)throw Error('burimunsi_provisioning_request_conflict');return [{result:state.receipt}];}
  state.record=c;state.fingerprint=args[6];state.ciphertext=args[7];
  state.receipt={contractVersion:1,requestId:R,collectionId:G,operation:c.operation,principalId:P,
   accountId:c.operation==='set_pin'?c.accountId:A,accountVersion:c.operation==='set_pin'?1:4,credentialVersion:1,
   approvalVersion:3,scopeVersion:2,applied:true,...(c.operation==='set_pin'?{}:{grantId:c.grantId,installationId:D,
    profile:c.profile,grantVersion:1,active:c.operation==='grant_installation',deliveryExpiresAt:Date.now()+900000})};
  return [{result:state.receipt}];
 }};
 const env={DB:db,BURIMUNSI_PIN_PEPPER_BASE64:pepper,BURIMUNSI_PIN_PEPPER_ID:'fixture-pin',
  DATA_KEY_ID:'fixture-data',DATA_ENCRYPTION_KEY:Buffer.alloc(32,14).toString('base64')};
 const options={env,groupId:G,actorArgs:[A,'a'.repeat(64),'https://admin.example.invalid',S],actorId:P,sessionId:S,profileSha:'b'.repeat(64)};
 return {state,env,db,options,service:new AdminNativeProvisioning(options)};
}

test('initial PIN uses the actual salted policy; SQL never receives plaintext or a low-entropy PIN digest',async()=>{
 const f=fixture(),input=pin(),receipt=await f.service.apply(input);
 assert.equal(receipt.operation,'set_pin');assert.equal(f.state.record.pin,undefined);
 assert.equal(f.state.record.pinHash.iterations,600000);assert(await nativePinHasher(f.env).verify('+250780000002',input.pin,f.state.record.pinHash));
 assert(!await nativePinHasher(f.env).verify('+250780000003',input.pin,f.state.record.pinHash));
 assert(!Object.hasOwn(f.state.record,'pin'));assert(!JSON.stringify(f.state.queries).includes('"pin":'));
 assert.notEqual(f.state.fingerprint,await digest(input.pin));
 assert(f.state.queries.some(x=>x.q.includes('pg_advisory_xact_lock(734636924058501')));
 assert.equal(f.state.ciphertext,null);
});
test('grant retains only hash plus purpose-bound encrypted custody; explicit readback releases same token',async()=>{
 const f=fixture(),receipt=await f.service.apply(grant());
 const delivery=await f.service.delivery(R,{collectionId:G,installationId:D,profile:'staff',grantVersion:1});
 assert.match(delivery.installationToken,/^[a-f0-9]{64}$/);assert.equal(await digest(delivery.installationToken),f.state.record.tokenHash);
 assert.equal(JSON.stringify(receipt).includes(delivery.installationToken),false);
 assert.equal(JSON.stringify(f.state.queries).includes(delivery.installationToken),false);
 assert.equal(JSON.stringify(f.state.receipt).includes('ciphertext'),false);
 assert.deepEqual(await f.service.delivery(R,{collectionId:G,installationId:D,profile:'staff',grantVersion:1}),delivery);
});
test('independent grants produce independently random tokens',async()=>{
 const a=fixture(),b=fixture();await a.service.apply(grant());await b.service.apply(grant());
 assert.notEqual(a.state.record.tokenHash,b.state.record.tokenHash);assert.notEqual(a.state.ciphertext,b.state.ciphertext);
});
for(const [field,value] of [['actorId',A],['sessionId',A],['profileSha','c'.repeat(64)]])test('delivery cannot cross '+field,async()=>{
 const f=fixture();await f.service.apply(grant());const other=new AdminNativeProvisioning({...f.options,[field]:value});
 await assert.rejects(other.delivery(R,{collectionId:G,installationId:D,profile:'staff',grantVersion:1}));
});
test('delivery verifies digest and exact current descriptor before exposing token',async()=>{
 const f=fixture();await f.service.apply(grant());f.state.record.tokenHash='0'.repeat(64);
 await assert.rejects(f.service.delivery(R,{collectionId:G,installationId:D,profile:'staff',grantVersion:1}));
 await assert.rejects(f.service.delivery(R,{collectionId:G,installationId:D,profile:'internal_receiver',grantVersion:1}));
});
test('an idempotent original request never generates a second grant/secret',async()=>{
 const f=fixture();await f.service.apply(grant());const original=structuredClone(f.state);
 const receipt=await f.service.apply(grant());assert.deepEqual(receipt,original.receipt);
 assert.deepEqual(f.state.record,original.record);assert.equal(f.state.ciphertext,original.ciphertext);
});
for(const [name,command] of [['set_pin',pin],['grant_installation',grant]])test(name+' and original-receipt lookup preserve PostgreSQL JSON command transport',async()=>{
 const f=fixture();await f.service.apply(command());await f.service.apply(command());
 const calls=f.state.queries.filter(x=>x.q.includes('private.burimunsi_provisioning_'));
 const applies=calls.filter(x=>x.q.includes('_apply('));assert.equal(applies.length,2);
 for(const call of applies){
  assert.equal(call.q,'SELECT private.burimunsi_provisioning_apply($1,$2,$3,$4,$5,$6::text::jsonb,$7,$8) AS result');
  assert.equal(typeof call.args[5],'string');assert.equal(JSON.parse(call.args[5]).operation,name);
  assert.equal(JSON.parse(call.args[5]).requestId,R);assert.match(call.args[6],/^[a-f0-9]{64}$/);
 }
 assert.deepEqual(Object.keys(JSON.parse(applies[1].args[5])).sort(),['operation','requestId']);
 assert.equal(applies[1].args[7],null);
 for(const call of calls.filter(x=>!x.q.includes('_apply(')))assert(!call.q.includes('::text::jsonb'));
});
test('lookup, directory, delivery and cancel preserve their original PostgreSQL parameter types',async()=>{
 const f=fixture();await f.service.apply(grant());await f.service.directory();
 await f.service.delivery(R,{collectionId:G,installationId:D,profile:'staff',grantVersion:1});await f.service.cancel(R);
 const calls=f.state.queries.filter(x=>x.q.includes('private.burimunsi_provisioning_')&&!x.q.includes('_apply('));
 for(const name of ['lookup','directory','delivery','cancel']){
  const call=calls.find(x=>x.q.includes('_'+name+'('));assert(call);
  assert(!call.q.includes('::text::jsonb'));assert(!call.q.includes('::jsonb'));
 }
});
test('an actual simulated lost COMMIT response retains one outcome, lookup does not redispatch',async()=>{
 const f=fixture();f.state.lostCommit=true;await assert.rejects(f.service.apply(grant()),/lost COMMIT/);
 assert(f.state.record);const original=structuredClone(f.state.record);
 const n=f.state.queries.filter(q=>q.q.includes('_apply(')).length;
 assert((await f.service.lookup(R)).found);assert.equal(f.state.queries.filter(q=>q.q.includes('_apply(')).length,n);
 await f.service.apply(grant());assert.deepEqual(f.state.record,original);
});
test('same original key with another PIN is refused by retained HMAC, not silently accepted',async()=>{
 const f=fixture();await f.service.apply(pin());await assert.rejects(f.service.apply({...pin(),pin:'7316'}),/request_conflict/);
});
test('missing pepper and shared-key substitution fail before credential hashing or mutation',async()=>{
 const f=fixture();delete f.env.BURIMUNSI_PIN_PEPPER_BASE64;
 await assert.rejects(f.service.apply(pin()),e=>e.code==='burimunsi_provisioning_unavailable');assert.equal(f.state.queries.length,0);
 for(const raw of ['',Buffer.alloc(31).toString('base64'),' '+pepper,pepper+'\n'])assert.throws(()=>nativePinHasher({...f.env,BURIMUNSI_PIN_PEPPER_BASE64:raw}));
 assert.throws(()=>nativePinHasher({...f.env,BURIMUNSI_PIN_PEPPER_BASE64:f.env.DATA_ENCRYPTION_KEY}));
});
test('missing encryption settings never issues an unrecoverable grant',async()=>{
 const f=fixture();delete f.env.DATA_ENCRYPTION_KEY;await assert.rejects(f.service.apply(grant()));assert.equal(f.state.record,null);
});
test('revoked/replaced request ownership denies lookup before owner SQL',async()=>{
 for(const change of [f=>f.state.revoked=true,f=>f.db.applicationWork={assert:async()=>{}}]){
  const f=fixture();change(f);await assert.rejects(f.service.lookup(R));assert.equal(f.state.queries.length,0);
 }
});
test('cancelled original key fences late PIN issuance; cancellation never accepts a secret',async()=>{
 const f=fixture();const receipt=await f.service.cancel(R);assert.equal(receipt.operation,'cancelled');
 assert.equal((await f.service.lookup(R)).receipt.applied,false);
 await assert.rejects(f.service.apply(pin()),e=>e.code==='burimunsi_provisioning_changed');assert.equal(f.state.record,null);
});
test('cancel races return the original committed outcome rather than erasing or rolling it back',async()=>{
 const f=fixture();const receipt=await f.service.apply(grant());assert.deepEqual(await f.service.cancel(R),receipt);
});
for(const mutate of [x=>x.collectionId='other',x=>x.extra=true,x=>x.scopeVersion=0,x=>x.requestId='F1000000-0000-4000-8000-000000000004',
 x=>x.pin='12345',x=>x.reason='PIN '+x.pin,x=>x.approvalVersion=1.5])test('strict original provisioning envelope rejects mutation '+String(mutate),()=>{
 const input=pin();mutate(input);assert.throws(()=>provisioningCommand(input,G));
});
