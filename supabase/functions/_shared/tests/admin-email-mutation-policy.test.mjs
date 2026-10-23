import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {isAbsolute,join} from 'node:path';
import {pathToFileURL} from 'node:url';
const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root==='string'&&isAbsolute(root),'Use the coherent actual _shared source graph.');
const actual=name=>import(pathToFileURL(join(root,name)).href);
const {mutation,retainedResponse}=await actual('domain/mutations.js');
const {accountDatabase}=await actual('domain/admin_accounts_legacy.js');
const {attestAdminEmailAccount,bindAdminEmailActor}=await actual('domain/admin_email_policy.js');
const {ApiError,digest,stableJson}=await actual('domain/core.js');
const NOW=1792497600,A='11111111-1111-4111-8111-111111111111',P='22222222-2222-4222-8222-222222222222';
const U='33333333-3333-4333-8333-333333333333',S='44444444-4444-4444-8444-444444444444',B='55555555-5555-4555-8555-555555555555';
const R='66666666-6666-4666-8666-666666666666',PROOF='77777777-7777-4777-8777-777777777777';
const account=()=>({id:A,principal_id:P,auth_user_id:U,auth_session_id:S,token_hash:'a'.repeat(64),public_id:B,origin:'https://admin-supabase-qa.collect.ikanisa.com',auth_version:1,role:'owner',issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null});
const accountProof=a=>attestAdminEmailAccount(a,{contract_version:1,public_session_id:B,email_verified_at:NOW,proof_id:PROOF});
function database(row=null){
 const batches=[],reads=[];
 return{batches,reads,prepare(sql){return{sql,values:[],bind(...values){this.values=values;return this;},async first(){reads.push(this);assert.equal(sql,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?');return row;}};},async batch(statements){batches.push(statements);return statements.map(s=>({results:[{source:s.sql}]}));}};
}
const actor=(surface='admin',assuranceLevel=1)=>({surface,userId:P,sessionId:S,assuranceLevel,mfaAt:assuranceLevel===2?NOW:null,permissions:new Set(['payments.write'])});
const failure=(code,status=403)=>e=>e instanceof ApiError&&e.status===status&&e.code===code;
test('Admin requested sensitive policy is satisfied by independent email proof, members retain actual MFA rules', {concurrency:false},async t=>{
 const oldNow=Date.now;Date.now=()=>NOW*1000;try{
  await t.test('AAL1 remains AAL1 while SQL receives sensitive-policy2 and null expected MFA',async()=>{
   const a=accountProof(account()),who=bindAdminEmailActor(actor(),a),db=database(),env=accountDatabase({DB:db},a,'payments.write',{mfa:true,fresh:true});
   await mutation(env,who,'payment.synthetic',R,{}, {ok:true},[],{permission:'payments.write',minimumAssurance:2,freshSeconds:300});
   const statements=db.batches[0];assert.equal(statements[0].sql,'SELECT private.set_admin_email_context(?::text,?::text,?::text,?::text) AS result');assert.deepEqual(statements[0].values,[A,a.token_hash,a.origin,B]);
   assert.ok(statements[1].sql.startsWith('INSERT INTO admin_account_guards'));const gate=statements.find(s=>s.sql.startsWith('INSERT INTO mutation_guards'));
   assert.equal(gate.values[11],2);assert.equal(gate.values[12],null);assert.equal(gate.values[7],300);assert.equal(who.assuranceLevel,1);assert.equal(who.mfaAt,null);
   const receipt=statements.find(s=>s.sql.startsWith('INSERT INTO request_receipts'));assert.equal(receipt.values[3],S);
  });
  await t.test('fresh TOTP/AAL2 alone never grants the new Admin email policy',async()=>{
   const db=database();await assert.rejects(mutation({DB:db},actor('admin',2),'payment.synthetic',R,{}, {},[],{minimumAssurance:2}),failure('recent_email_sign_in_required'));assert.deepEqual(db.batches,[]);
  });
  await t.test('member AAL1 is still refused by existing minimum assurance2',async()=>{
   const db=database();await assert.rejects(mutation({DB:db},actor('member',1),'payment.synthetic',R,{}, {},[],{minimumAssurance:2}),failure('mfa_required'));assert.deepEqual(db.batches,[]);
  });
  await t.test('member AAL2 still passes genuine expected MFA timestamp',async()=>{
   const db=database();await mutation({DB:db},actor('member',2),'payment.synthetic',R,{}, {},[],{minimumAssurance:2,freshSeconds:300});const gate=db.batches[0][0];assert.equal(gate.values[11],2);assert.equal(gate.values[12],NOW);
  });
  await t.test('reauthentication does not transfer a retained receipt to a different SID',async()=>{
   const body={amount:1},row={operation:'payment.synthetic',body_sha256:await digest(stableJson(body)),session_id:PROOF,response_json:'{"ok":true}'},db=database(row),a=accountProof(account()),who=bindAdminEmailActor(actor(),a);
   await assert.rejects(retainedResponse(accountDatabase({DB:db},a),who,'payment.synthetic',R,body,{minimumAssurance:2,freshSeconds:300}),failure('request_conflict',409));assert.equal(db.batches.length,1);assert.equal(db.batches[0].some(s=>s.sql.startsWith('INSERT INTO request_receipts')),false);
  });
  await t.test('account wrapper preserves caller result indices after context and guard prefix',async()=>{
   const db=database(),a=accountProof(account()),env=accountDatabase({DB:db},a,'payments.write',{mfa:true,fresh:true});const result=await env.DB.batch([env.DB.prepare('SELECT synthetic_result')]);assert.deepEqual(result,[{results:[{source:'SELECT synthetic_result'}]}]);
  });
  await t.test('proof expiring inside the actual batch preserves the dedicated403 recovery code',async()=>{
   const db=database(),a=accountProof(account());db.batch=async()=>{throw new Error('recent_email_sign_in_required');};
   await assert.rejects(accountDatabase({DB:db},a,'payments.write',{mfa:true,fresh:true}).DB.batch([]),failure('recent_email_sign_in_required'));
  });
  await t.test('stale or replaced account proof cannot dispatch protected batch',async()=>{
   const db=database(),a=accountProof(account());a.public_id=PROOF;const env=accountDatabase({DB:db},a,'payments.write',{mfa:true,fresh:true});await assert.rejects(env.DB.batch([]),failure('recent_email_sign_in_required'));assert.deepEqual(db.batches,[]);
  });
 }finally{Date.now=oldNow;}
});
