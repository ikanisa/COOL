// Synthetic adapter tests only. PostgreSQL authority, race and storage behavior
// require the separate full-chain rehearsal; these doubles cannot prove them.
import {registerHooks} from 'node:module';
import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';

const legacy=new URL('../domain/admin_accounts_legacy.js',import.meta.url).href;
registerHooks({resolve(specifier,context,next){
 if(context.parentURL?.endsWith('/domain/admin_burimunsi_observations.js')&&specifier==='./admin_accounts.js')
  return {url:'data:text/javascript,'+encodeURIComponent(`export {accountDatabase} from ${JSON.stringify(legacy)};
   export async function adminAccountSession(){return globalThis.__observationAdminFixture.latest;}
   export async function adminCanonicalActor(){return globalThis.__observationAdminFixture.currentActor;}`),shortCircuit:true};
 return next(specifier,context);
}});
const {adminMomoRoute}=await import('../domain/admin_momo.js');
const {managedAdminObservationsEnabled}=await import('../domain/admin_burimunsi_observations.js');
const {nativeObservationsEnabled}=await import('../domain/burimunsi/collect-runtime.js');
const {attestAdminEmailAccount,bindAdminEmailActor}=await import('../domain/admin_email_policy.js');
const {encrypt}=await import('../domain/encryption.js');
const {digest}=await import('../domain/core.js');
const {canonicalJson}=await import('../domain/burimunsi/values.js');
const gid='synthetic-group',other='other-group',principal='11111111-1111-4111-8111-111111111111',
 admin='22222222-2222-4222-8222-222222222222',session='33333333-3333-4333-8333-333333333333',
 auth='44444444-4444-4444-8444-444444444444',publicId='55555555-5555-4555-8555-555555555555',
 proof='66666666-6666-4666-8666-666666666666',sourceId='77777777-7777-4777-8777-777777777777',
 requestId='88888888-8888-4888-8888-888888888888';
const key=Buffer.alloc(32,7).toString('base64'),message='Received 250 RWF. Reference: 1234. Thank you.';
const denied=()=>Object.assign(new Error('synthetic scope denied'),{code:'42501'});
const error=(status,code)=>e=>e.status===status&&e.code===code;
async function fixture(){
 const account={id:admin,principal_id:principal,auth_user_id:auth,auth_session_id:session,token_hash:'a'.repeat(64),
  public_id:publicId,origin:'https://admin.example.invalid',auth_version:1,role:'owner',issued_assurance_level:1,
  issued_mfa_at:null,issued_mfa_factor_id:null};
 attestAdminEmailAccount(account,{contract_version:1,public_session_id:publicId,email_verified_at:Math.floor(Date.now()/1000),proof_id:proof});
 const actor=bindAdminEmailActor({surface:'admin',userId:principal,sessionId:session,assuranceLevel:1,mfaAt:null,
  permissions:new Set(['sms.read','sms.reveal'])},account);
 const f={account,actor,latest:account,currentActor:actor,allowed:new Set([gid]),batches:[],audits:[],revision:'b'.repeat(64),failAudit:false};
 const env={BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED:'true',BURIMUNSI_CURSOR_KEY_BASE64:key,DATA_KEY_ID:'test-key',DATA_ENCRYPTION_KEY:key};
 const payload={raw_sender:'Synthetic',raw_body:message,source_mode:'catch_up',complete:false,provenance:'native_observation_unverified'},encoded=new TextEncoder().encode(JSON.stringify(payload));
 const profileJson=JSON.stringify({sender_allowlist:['Synthetic'],incoming_prefixes:['Received'],currency_aliases:['RWF'],transaction_id_prefixes:['Reference:'],date_format:'YMD_HMS',utc_offset_minutes:120});
 f.hintProfile={profileSha256:await digest(profileJson),profile:{provider:'mtn_momo',status:'active',profile_status:'approved',profile_version:'synthetic-v1',profile_json:profileJson,currency:'RWF',timezone:'Africa/Kigali'}};
 const objHash=await digest(encoded),bodyHash=await digest(message),fingerprint='c'.repeat(64);
 const descriptor={scope:{ownerId:principal,purpose:'sms_receipt',entityId:sourceId},aad:`sms:${sourceId}:${objHash}`,
  keyId:'test-key',plaintextSha256:objHash,requestDigest:fingerprint,httpMetadata:{contentType:'application/octet-stream'},
  customMetadata:{sha256:objHash,key_id:'test-key'}};
 const sourceFingerprint=await digest(canonicalJson(descriptor)),sealed=await encrypt(env,encoded,descriptor.aad),sealedBytes=new TextEncoder().encode(sealed);
 f.source={collectionId:gid,sourceId,requestId,bodySha256:bodyHash,ownerUserId:principal,objectKey:'sms/'+sourceId,
  objectSha256:objHash,sizeBytes:encoded.length,fingerprint,keyId:'test-key',sourceFingerprint,
  storageOperationId:'synthetic-operation',storageFingerprint:'d'.repeat(64),cipherSha256:await digest(sealedBytes),cipherSize:sealedBytes.length,admittedAt:Date.now()};
 f.rows=[{...f.source,retentionState:'retained'}];
 env.PRIVATE_MEDIA={get:async()=>({key:f.source.objectKey,size:f.source.cipherSize,sha256:f.source.cipherSha256,
  customMetadata:{sha256:objHash,key_id:'test-key',source_fingerprint:sourceFingerprint},text:async()=>{if(f.onRead)await f.onRead();return sealed;}})};
 env.DB={prepare(sql){return{sql,args:[],bind(...args){return {sql,args};}};},async batch(statements){
  f.batches.push(statements);const pending=[];
  const answers=statements.map(s=>{
   if(s.sql.includes('burimunsi_observation_admin_collections()'))return {results:[{result:[...f.allowed].map(collectionId=>({collectionId,label:'Synthetic group'}))}]};
   if(s.sql.includes('burimunsi_observation_admin_page(')){
    const [collectionId,limit,offset]=s.args;if(!f.allowed.has(collectionId))throw denied();
    return {results:[{result:{collectionId,totalCount:f.rows.length,revision:f.revision,items:f.rows.slice(offset,offset+limit)}}]};
   }
   if(s.sql.startsWith('SELECT private.burimunsi_observation_admin_hint_profile(')){
    if(!f.allowed.has(s.args[0]))throw denied();return {results:[{result:f.hintProfile?structuredClone(f.hintProfile):null}]};
   }
   if(s.sql.startsWith('SELECT private.burimunsi_observation_admin_source(')){
    if(!f.allowed.has(s.args[0]))throw denied();return {results:[{result:s.args[1]===sourceId?structuredClone(f.source):null}]};
   }
   if(s.sql.startsWith('INSERT INTO admin_bridge_guards')){
    if(!f.allowed.has(s.args[1])||canonicalJson(s.args[3])!==canonicalJson(f.source)||
     s.args.length>4&&canonicalJson(s.args[6])!==canonicalJson(f.hintProfile))throw denied();
   }
   if(s.sql.startsWith('INSERT INTO audit_log')){if(f.failAudit)throw Error('synthetic audit failure');pending.push(s.args);}
   return {results:[]};
  });f.audits.push(...pending);return answers;
 }};
 f.env=env;globalThis.__observationAdminFixture=f;return f;
}
async function call(f,path,headers={}){
 const url=new URL('https://admin.example.invalid/api/admin/momo/'+path),request=new Request(url,{headers});
 const parts=url.pathname.split('/').slice(4);return adminMomoRoute(request,f.env,f.account,f.actor,parts,url);
}
test('disabled observations stay unavailable before any database access',async()=>{
 const f=await fixture();delete f.env.BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED;f.env.BURIMUNSI_SMS_OBSERVATIONS_ENABLED='true';
 await assert.rejects(call(f,'observations/collections'),error(404,'not_found'));assert.equal(f.batches.length,0);
});
test('native intake and managed Admin flags are independently selected',async()=>{
 for(const native of [false,true])for(const adminEnabled of [false,true]){
  const env={BURIMUNSI_SMS_OBSERVATIONS_ENABLED:String(native),BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED:String(adminEnabled)};
  assert.equal(nativeObservationsEnabled(env),native);assert.equal(managedAdminObservationsEnabled(env),adminEnabled);
 }
 assert.equal(nativeObservationsEnabled({}),false);assert.equal(managedAdminObservationsEnabled({}),false);
 const f=await fixture();f.env.BURIMUNSI_SMS_OBSERVATIONS_ENABLED='false';
 const data=await(await call(f,'observations/collections')).json();assert.equal(data.items[0].collectionId,gid);
});
test('collection listing and metadata are scoped and never return private journal fields',async()=>{
 const f=await fixture(),collections=await(await call(f,'observations/collections')).json();
 assert.deepEqual(collections.items,[{collectionId:gid,label:'Synthetic group'}]);
 const page=await(await call(f,`observations?collectionId=${gid}`)).json();
 assert.equal(page.items[0].retentionState,'retained');assert.equal(page.items[0].bodySha256,await digest(message));
 assert.deepEqual(Object.keys(page.items[0]).sort(),['admittedAt','bodySha256','requestId','retentionState','sourceId']);
 assert.ok(!JSON.stringify(page).includes(message));
 await assert.rejects(call(f,`observations?collectionId=${other}`),error(403,'permission_required'));
});
test('a changed reservation fingerprint remains unresolved even with an apparent source row',async()=>{
 const f=await fixture();f.rows[0].sourceFingerprint='0'.repeat(64);
 const page=await(await call(f,`observations?collectionId=${gid}`)).json();
 assert.equal(page.items[0].retentionState,'unresolved');assert.equal(page.items[0].bodySha256,null);
});
test('cursor is bound to collection, session, filter and current revision',async()=>{
 const f=await fixture();f.rows.push({...f.rows[0],sourceId:'99999999-9999-4999-8999-999999999999',retentionState:'unresolved',bodySha256:null});
 const page=await(await call(f,`observations?collectionId=${gid}&limit=1`)).json();assert.ok(page.nextCursor);
 const token=encodeURIComponent(page.nextCursor);f.revision='e'.repeat(64);
 await assert.rejects(call(f,`observations?collectionId=${gid}&limit=1&cursor=${token}`),error(409,'cursor_changed'));
 f.revision='b'.repeat(64);f.actor.sessionId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 await assert.rejects(call(f,`observations?collectionId=${gid}&limit=1&cursor=${token}`),error(409,'cursor_changed'));
});
test('reveal returns verified content only after current email, grants, scope and audit',async()=>{
 const f=await fixture(),response=await call(f,`observations/${sourceId}/content?collectionId=${gid}`,{'X-Collect-Review-Reason':'Review this source'});
 const result=await response.json();assert.equal(result.rawBody,message);assert.equal(result.bodySha256,await digest(message));assert.equal(f.audits.length,1);
 const audit=f.audits[0];assert.ok(!JSON.stringify(audit).includes(message));
 const final=f.batches.at(-1);assert.ok(final.some(s=>s.sql.includes('private.assert_admin_email_context(300)')));
 assert.ok(final.some(s=>s.sql.includes('burimunsi_observation_admin_source')));
});
test('scope revocation or audit failure after retrieval never returns plaintext',async()=>{
 for(const cause of ['revoke','audit']){
  const f=await fixture();if(cause==='revoke')f.onRead=()=>f.allowed.clear();else f.failAudit=true;
  await assert.rejects(call(f,`observations/${sourceId}/content?collectionId=${gid}`,{'X-Collect-Review-Reason':'Review this source'}));
  assert.equal(f.audits.length,0);
 }
});

test('expired fresh-email proof, missing reveal grant and absent reason block retrieval',async()=>{
 for(const cause of ['email','grant','reason']){
  const f=await fixture();
  if(cause==='email')attestAdminEmailAccount(f.account,{contract_version:1,public_session_id:publicId,email_verified_at:Math.floor(Date.now()/1000)-301,proof_id:proof});
  if(cause==='grant')f.actor.permissions.delete('sms.reveal');
  let reads=0;const get=f.env.PRIVATE_MEDIA.get;f.env.PRIVATE_MEDIA.get=async key=>{reads++;return get(key);};
  const headers=cause==='reason'?{}:{'X-Collect-Review-Reason':'Review this source'};
  await assert.rejects(call(f,`observations/${sourceId}/content?collectionId=${gid}`,headers));
  assert.equal(reads,0);assert.equal(f.audits.length,0);
 }
});
test('a changed session or immutable source during retrieval prevents disclosure',async()=>{
 for(const cause of ['session','source']){
  const f=await fixture();
  f.onRead=()=>{if(cause==='session')f.latest={...f.account,auth_session_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'};
   else f.source.fingerprint='f'.repeat(64);};
  await assert.rejects(call(f,`observations/${sourceId}/content?collectionId=${gid}`,{'X-Collect-Review-Reason':'Review this source'}));
  assert.equal(f.audits.length,0);
 }
});

test('C1 control characters in an Admin review reason are rejected before retrieval',async()=>{
 const f=await fixture();let reads=0;const get=f.env.PRIVATE_MEDIA.get;f.env.PRIVATE_MEDIA.get=async key=>{reads++;return get(key);};
 await assert.rejects(call(f,`observations/${sourceId}/content?collectionId=${gid}`,
  {'X-Collect-Review-Reason':'Review'+String.fromCharCode(0x85)+'this source'}),error(400,'reason_required'));
 assert.equal(reads,0);assert.equal(f.audits.length,0);
});

test('opt-in Admin hint disclosure is audit-bound and contains only exact unverified quotations',async()=>{
 const f=await fixture();f.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED='true';
 const response=await call(f,`observations/${sourceId}/content?collectionId=${gid}&displayHintsVersion=1`,{'X-Collect-Review-Reason':'Review this source'});
 const result=await response.json();assert.equal(result.displayHints.kind,'partial_inbox_display_only');
 assert.equal(result.displayHints.bodySha256,await digest(message));assert.equal(result.displayHints.profileSha256,f.hintProfile.profileSha256);
 for(const hint of result.displayHints.hints)assert.equal(result.rawBody.slice(hint.start,hint.end),hint.text);
 assert.equal(f.audits.length,1);assert.ok(f.batches.at(-1).some(s=>s.sql.includes('burimunsi_observation_admin_hint_profile')));
});
test('opt-in Admin hint response is null for disabled or changed profile without inventing a source',async()=>{
 for(const mode of ['disabled','missing','changed','wrong_hash','version_control']){
  const f=await fixture();f.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED=mode==='disabled'?'false':'true';
  if(mode==='missing')f.hintProfile=null;
  if(mode==='wrong_hash')f.hintProfile.profileSha256='0'.repeat(64);
  if(mode==='version_control')f.hintProfile.profile.profile_version='synthetic\u0085v1';
  if(mode==='changed')f.onRead=()=>{f.hintProfile=null;};
  const response=await call(f,`observations/${sourceId}/content?collectionId=${gid}&displayHintsVersion=1`,{'X-Collect-Review-Reason':'Review this source'});
  const result=await response.json();assert.equal(result.displayHints,null,mode);assert.equal(result.rawBody,message);assert.equal(f.audits.length,1);
 }
});
test('legacy Admin reveal omits the optional hint field even when hinting is enabled',async()=>{
 const f=await fixture();f.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED='true';
 const result=await(await call(f,`observations/${sourceId}/content?collectionId=${gid}`,{'X-Collect-Review-Reason':'Review this source'})).json();
 assert.equal(Object.hasOwn(result,'displayHints'),false);
});
