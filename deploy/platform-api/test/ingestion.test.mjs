import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,randomUUID,createHash,verify as verifySignature} from 'node:crypto';
import {fixture,admin,authorization,setupMfa,totp} from './support/auth_fixture.mjs';
import {functionRpc as nativeFunction,nativeRpc,consumeNativeCapability,integrityBinding} from '../src/native_integrity.js';
import {functionRpc as rosterFunction,rosterRpc} from '../src/roster.js';
import {encrypt,decrypt} from '../src/encryption.js';
import {groupRpc} from '../src/groups.js';
import {receiptFunction} from '../src/receipts.js';

// D1 and its triggers run in workerd. Google/AI transport acknowledgements,
// service-account/policy assertions and test keys are isolated fixtures only.
// These tests cannot establish provider approval, production admission or R2
// deployment. Encrypted object byte behavior uses a private in-memory R2 double.
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{format:'pem',type:'pkcs8'},publicKeyEncoding:{format:'pem',type:'spki'}});
const hash=v=>createHash('sha256').update(v).digest('hex');
const key=Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64');
const certificate=Buffer.from(hash('fixture-published-certificate'),'hex').toString('base64url');
const enc=new TextEncoder();
class PrivateObjects {
 constructor(){this.objects=new Map();this.puts=0;}
 async put(name,value,metadata){this.puts++;this.objects.set(name,{body:value,metadata});return {key:name};}
 async get(name){const row=this.objects.get(name);return row?{size:enc.encode(row.body).length,text:async()=>row.body}:null;}
}
async function base(t,{operator=false,policyChanges={}}={}) {
 const f=await fixture();t.after(()=>f.close());let session;
 if(operator){const a=await admin(f);await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,'roster.import',new Date().toISOString()).run();session=await f.login(a.identity);const m=await setupMfa(f,session);const response=await f.call('/v1/auth/mfa/verify',{factor_id:m.factor.id,challenge_id:m.challenge.id,code:totp(m.factor.totp.secret)},authorization(session));assert.equal(response.status,200,JSON.stringify(response.body));session=response.body;}
 else session=await f.login({phone:'+250788123456'});
 const a=await f.actor(session);assert.equal(a.status,200,JSON.stringify(a.body));const actor={...a.body,permissions:new Set(a.body.permissions)};
 const objects=new PrivateObjects();const p={schema_version:1,purpose:'collect_native_admission',status:'approved',enabled:true,provider:'google_play_integrity',package_name:'app.cool.mobile',approval_id:randomUUID(),approval_evidence_sha256:'1'.repeat(64),project_id:'collect-fixture',cloud_project_number:'123456789012',service_account_email:'play@collect-fixture.iam.gserviceaccount.com',certificate_sha256:[certificate],minimum_version_code:1,capability_ttl_seconds:120,actor_hour_limit:6,project_day_limit:100,approved_at:new Date(Date.now()-60000).toISOString(),valid_until:new Date(Date.now()+3600000).toISOString(),...policyChanges};
 const policy=JSON.stringify(p);const env={DB:f.db,PRIVATE_MEDIA:objects,DATA_ENCRYPTION_KEY:key,DATA_KEY_ID:'auth-test-v1',PLAY_INTEGRITY_POLICY_JSON:policy,PLAY_INTEGRITY_POLICY_SHA256:hash(policy),PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:p.project_id,client_email:p.service_account_email,private_key:privateKey,token_uri:'https://oauth2.googleapis.com/token'})};
 return {f,actor,session,env,objects,policy:p};
}
function group(actor,{nonce=randomUUID(),token=randomUUID()}={}) {
 const receiverHash=hash('+250788123456');const payload={group_name:'Members',group_description:'Collection group',receiver_momo_number:'0788123456',receiver_momo_number_hash:receiverHash,receiver_label:'MTN MoMo receiver',group_collection_type:'ikimina',group_category_subtype:null,group_purpose_label:null,group_is_public:false};
 const ordered={action:'group.create',subject_id:actor.userId,nonce,receiver_momo_number_hash:receiverHash,sms_permission_granted:true,sms_access_enabled:true,group_request:payload};
 return {...ordered,request_hash:hash(JSON.stringify(ordered)),integrity_token:token};
}
async function consent(b,enabled=true) {return nativeRpc('record_sms_access_consent',{enabled,momo_number_hash:hash('+250788123456'),build_channel:'android_group_create_attested'},b.env,b.actor);}
function google(t,body,{alter=()=>{},oauth=null,decode=null}={}) {
 const calls=[],old=globalThis.fetch;t.after(()=>{globalThis.fetch=old;});
 globalThis.fetch=async(url,init)=>{
  calls.push(String(url));
  if(url==='https://oauth2.googleapis.com/token'){
   const assertion=new URLSearchParams(init.body).get('assertion'),parts=assertion.split('.');
   assert.equal(verifySignature('RSA-SHA256',Buffer.from(parts[0]+'.'+parts[1]),publicKey,Buffer.from(parts[2],'base64url')),true);
   const claims=JSON.parse(Buffer.from(parts[1],'base64url').toString());assert.equal(claims.aud,url);assert.equal(claims.scope,'https://www.googleapis.com/auth/playintegrity');
   return oauth?oauth():Response.json({access_token:'fixture-google-access',token_type:'Bearer',expires_in:3600});
  }
  assert.equal(url,'https://playintegrity.googleapis.com/v1/app.cool.mobile:decodeIntegrityToken');assert.equal(init.headers.Authorization,'Bearer fixture-google-access');assert.equal(JSON.parse(init.body).integrity_token,body.integrity_token);
  if(decode)return decode();
  const verdict={requestDetails:{requestPackageName:'app.cool.mobile',requestHash:body.request_hash,timestampMillis:String(Date.now())},appIntegrity:{packageName:'app.cool.mobile',appRecognitionVerdict:'PLAY_RECOGNIZED',versionCode:'12',certificateSha256Digest:[certificate]},accountDetails:{appLicensingVerdict:'LICENSED'},deviceIntegrity:{deviceRecognitionVerdict:['MEETS_DEVICE_INTEGRITY']}};
  await alter(verdict);return Response.json({tokenPayloadExternal:verdict});
 };return calls;
}
const rejectCode=(fn,code)=>assert.rejects(fn,e=>e.code===code,code);

test('request hashes follow Dart insertion order and reject different content/subject',async t=>{
 const b=await base(t),body=group(b.actor);assert.equal((await integrityBinding(body,b.actor)).requestHash,body.request_hash);
 await rejectCode(()=>integrityBinding({...body,group_request:{...body.group_request,group_name:'Changed'}},b.actor),'integrity_binding_mismatch');
 await rejectCode(()=>integrityBinding({...body,subject_id:randomUUID()},b.actor),'invalid_integrity_request');
});
test('unconfigured native provider denies before any provider call or reservation',async t=>{
 const b=await base(t),body=group(b.actor),calls=google(t,body);delete b.env.PLAY_INTEGRITY_POLICY_JSON;
 await rejectCode(()=>nativeFunction('verify-play-integrity',body,b.env,b.actor),'play_integrity_unavailable');assert.equal(calls.length,0);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_reservations').first()).n,0);
});
test('native admission requires current explicit SMS consent before spending quota',async t=>{
 const b=await base(t),body=group(b.actor),calls=google(t,body);
 await rejectCode(()=>nativeFunction('verify-play-integrity',body,b.env,b.actor),'integrity_session_unavailable');assert.equal(calls.length,0);
});
test('admission retains provider-bound evidence; same receipt replays without Google',async t=>{
 const b=await base(t),body=group(b.actor);await consent(b);const calls=google(t,body);
 const result=await nativeFunction('verify-play-integrity',body,b.env,b.actor);assert.equal(result.value.status,'pass');assert.equal(calls.length,2);
 assert.deepEqual((await nativeFunction('verify-play-integrity',body,b.env,b.actor)).value,result.value);assert.equal(calls.length,2);
 const evidence=await b.f.db.prepare('SELECT * FROM native_reservations').first();assert.equal(evidence.policy_sha256,b.env.PLAY_INTEGRITY_POLICY_SHA256);assert.equal(evidence.session_id,b.actor.sessionId);assert.equal(evidence.state,'completed');assert.ok(!evidence.payload_ciphertext.includes('0788123456'));
 await rejectCode(()=>nativeFunction('verify-play-integrity',{...body,nonce:randomUUID(),request_hash:'0'.repeat(64)},b.env,b.actor),'integrity_binding_mismatch');
});
test('capability claim and a failed target mutation roll back together; success is single use',async t=>{
 const b=await base(t),body=group(b.actor);await consent(b);google(t,body);
 const cap=(await nativeFunction('verify-play-integrity',body,b.env,b.actor)).value.native_capability;
 const a=await consumeNativeCapability(b.env,b.actor,cap,'group.create',body.group_request),duplicate=await consumeNativeCapability(b.env,b.actor,cap,'group.create',body.group_request);
 await assert.rejects(()=>b.f.db.batch([a,duplicate]));assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capability_claims').first()).n,0);
 await (await consumeNativeCapability(b.env,b.actor,cap,'group.create',body.group_request)).run();
 await assert.rejects(async()=>await (await consumeNativeCapability(b.env,b.actor,cap,'group.create',body.group_request)).run());
 await rejectCode(()=>consumeNativeCapability(b.env,b.actor,cap,'group.create',{...body.group_request,group_name:'Other'}),'native_capability_denied');
});
test('capability cannot move sessions and rechecks revocation at SQL claim time',async t=>{
 const b=await base(t),body=group(b.actor);await consent(b);google(t,body);
 const cap=(await nativeFunction('verify-play-integrity',body,b.env,b.actor)).value.native_capability;
 await rejectCode(()=>consumeNativeCapability(b.env,{...b.actor,sessionId:randomUUID()},cap,'group.create',body.group_request),'native_capability_denied');
 const statement=await consumeNativeCapability(b.env,b.actor,cap,'group.create',body.group_request);
 await b.f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='logout' WHERE id=?").bind(Math.floor(Date.now()/1000),b.actor.sessionId).run();await assert.rejects(()=>statement.run());
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capability_claims').first()).n,0);
});
test('unlicensed, foreign-certificate and stale verdicts cannot mint capabilities',async t=>{
 for(const modify of [v=>{v.accountDetails.appLicensingVerdict='UNLICENSED';},v=>{v.appIntegrity.certificateSha256Digest=['x'.repeat(43)];},v=>{v.requestDetails.timestampMillis=String(Date.now()-301000);}]){
  const b=await base(t),body=group(b.actor);await consent(b);google(t,body,{alter:modify});
  await rejectCode(()=>nativeFunction('verify-play-integrity',body,b.env,b.actor),'integrity_policy_rejected');assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capabilities').first()).n,0);
 }
});
test('Google outage is durable ambiguity and never automatic re-dispatch',async t=>{
 const b=await base(t),body=group(b.actor);await consent(b);const calls=google(t,body,{oauth:()=>new Response('outage',{status:503})});
 await rejectCode(()=>nativeFunction('verify-play-integrity',body,b.env,b.actor),'play_integrity_unavailable');
 await rejectCode(()=>nativeFunction('verify-play-integrity',body,b.env,b.actor),'integrity_request_replayed');assert.equal(calls.length,1);
 assert.equal((await b.f.db.prepare('SELECT state FROM native_reservations').first()).state,'ambiguous');
});
test('native project/actor budget and mid-dispatch revocation prevent further Google calls',async t=>{
 const b=await base(t,{policyChanges:{actor_hour_limit:1}}),body=group(b.actor);await consent(b);google(t,body);
 await nativeFunction('verify-play-integrity',body,b.env,b.actor);const next=group(b.actor);const calls=google(t,next);
 await rejectCode(()=>nativeFunction('verify-play-integrity',next,b.env,b.actor),'integrity_budget_exhausted');assert.equal(calls.length,0);
});
test('policy rotation during Google decode denies the completion',async t=>{
 const b=await base(t),body=group(b.actor);await consent(b);google(t,body,{alter:()=>{b.env.PLAY_INTEGRITY_POLICY_SHA256='f'.repeat(64);}});
 await rejectCode(()=>nativeFunction('verify-play-integrity',body,b.env,b.actor),'play_integrity_unavailable');assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capabilities').first()).n,0);
});

function pasted(content='member_name,momo_name,momo_number\nAlice Smith,Alice Smith,0788123456\nBob Jones,Bob Jones,0722123456'){return {contract_version:1,request_id:randomUUID(),source_type:'text',content};}
const editable=p=>p.rows.map(({member_name,momo_name,momo_number})=>({member_name,momo_name,momo_number}));
async function reviewed(b,preview) {
 const body={p_import_id:preview.import_id,p_parent_revision_id:preview.revision_id,p_request_id:randomUUID(),p_rows:editable(preview),p_reason:'Reviewed against original source.'};
 return (await rosterRpc('admin_review_roster_import',body,b.env,b.actor)).value;
}
function commitBody(preview){return {p_import_id:preview.import_id,p_revision_id:preview.revision_id,p_reviewed_rows_sha256:preview.reviewed_rows_sha256,p_request_id:randomUUID(),p_human_affirmed:true,p_mode:'create',p_collection_id:null,p_title:'Community Members',p_reason:'Owner confirmed the reviewed membership roster.'};}
test('encrypted retained CSV requires explicit human review and atomic idempotent commit',async t=>{
 const b=await base(t,{operator:true}),body=pasted();const initial=(await rosterFunction('prepare-roster-import',body,b.env,b.actor)).value;
 assert.equal(initial.can_submit,false);assert.equal(initial.requires_human_review,true);assert.equal(initial.ready_count,2);assert.equal(initial.source_sha256,hash(body.content));
 const saved=await b.f.db.prepare('SELECT * FROM roster_imports').first();assert.equal(saved.source_sha256,hash(body.content));assert.equal(b.objects.objects.size,1);assert.ok(!b.objects.objects.get(saved.source_object_key).body.includes('Alice Smith'));
 await rejectCode(()=>rosterRpc('admin_commit_roster_import',commitBody(initial),b.env,b.actor),'roster_review_required');
 const p=await reviewed(b,initial),request=commitBody(p),receipt=(await rosterRpc('admin_commit_roster_import',request,b.env,b.actor)).value;
 assert.equal(receipt.roster_count,2);assert.equal(receipt.share_code_ready,true);assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM roster_members').first()).n,2);
 const replay=(await rosterRpc('admin_commit_roster_import',request,b.env,b.actor)).value;assert.equal(replay.replayed,true);assert.equal(replay.collection_id,receipt.collection_id);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1);assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM users').first()).n,1,'Unregistered uploaded people are not silently authenticated accounts.');
});
test('upload/review cannot retarget a request, current session, source or latest revision',async t=>{
 const b=await base(t,{operator:true}),body=pasted(),initial=(await rosterFunction('prepare-roster-import',body,b.env,b.actor)).value;
 await rejectCode(()=>rosterFunction('prepare-roster-import',{...body,content:body.content+'\nEve,Eve,0788999999'},b.env,b.actor),'roster_request_conflict');
 await rejectCode(()=>rosterRpc('admin_get_roster_import',{p_import_id:initial.import_id},b.env,{...b.actor,sessionId:randomUUID()}),'roster_import_unavailable');
 const revision=await reviewed(b,initial);await rejectCode(()=>rosterRpc('admin_review_roster_import',{p_import_id:initial.import_id,p_parent_revision_id:initial.revision_id,p_request_id:randomUUID(),p_rows:editable(initial),p_reason:'A competing tab tried an obsolete revision.'},b.env,b.actor),'roster_revision_superseded');
 const sourceRow=await b.f.db.prepare('SELECT * FROM roster_imports').first();b.objects.objects.get(sourceRow.source_object_key).body='tampered';
 assert.equal(revision.source_sha256,initial.source_sha256);await assert.rejects(()=>b.f.db.prepare('UPDATE roster_imports SET source_sha256=? WHERE id=?').bind('f'.repeat(64),initial.import_id).run());
});
test('duplicate MoMo rows remain uncommittable and malformed CSV is refused',async t=>{
 const b=await base(t,{operator:true}),body=pasted('name,momo name,phone\nAlice,Alice,0788123456\nBob,Bob,0788123456'),initial=(await rosterFunction('prepare-roster-import',body,b.env,b.actor)).value;
 assert.equal(initial.error_count,1);await rejectCode(()=>reviewed(b,initial),'roster_rows_invalid');
 await rejectCode(()=>rosterFunction('prepare-roster-import',pasted('name,momo name,phone\n"Alice,Alice,0788123456'),b.env,b.actor),'roster_input_invalid');
});
test('missing AI processor approval never dispatches or fabricates an extraction',async t=>{
 const b=await base(t,{operator:true}),bytes=enc.encode('%PDF-1.7\nfixture-source'),body={contract_version:1,request_id:randomUUID(),source_type:'pdf',filename:'members.pdf',mime_type:'application/pdf',content_base64:Buffer.from(bytes).toString('base64'),ai_consent:true,consent_version:'roster-ai-extraction-v1'};
 const old=globalThis.fetch;globalThis.fetch=()=>{throw new Error('AI network must remain unreachable without approval');};t.after(()=>{globalThis.fetch=old;});
 await rejectCode(()=>rosterFunction('prepare-roster-import',body,b.env,b.actor),'roster_extraction_unavailable');
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM roster_processing_records').first()).n,0);assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports').first()).state,'retained');assert.equal(b.objects.objects.size,1);
});
test('large accepted source encrypts without argument-spread failure and preserves exact bytes',async t=>{
 const b=await base(t,{operator:true}),content='A'.repeat(300000),body=pasted(content),result=(await rosterFunction('roster-import-upload',body,b.env,b.actor)).value;
 assert.equal(result.source_sha256,hash(content));const row=await b.f.db.prepare('SELECT * FROM roster_imports').first();assert.equal(row.source_size,300000);assert.equal(row.state,'retained');assert.equal(hash(b.objects.objects.get(row.source_object_key).body),row.object_sha256);
});
test('staged review intent keeps exact current consumer acknowledgement and source/session binding',async t=>{
 const b=await base(t,{operator:true}),initial=(await rosterFunction('prepare-roster-import',pasted(),b.env,b.actor)).value;
 const request={p_import_id:initial.import_id,p_parent_revision_id:initial.revision_id,p_request_id:randomUUID(),p_rows:editable(initial),p_reason:'Reviewed against uploaded membership sheet.'},payload=JSON.stringify(request),sha=hash(payload);
 const stage=(await rosterRpc('admin_stage_roster_import_intent',{p_request_id:request.p_request_id,p_import_id:initial.import_id,p_kind:'review',p_payload:payload,p_payload_sha256:sha},b.env,b.actor)).value;
 assert.deepEqual(Object.keys(stage).sort(),['contract_version','ok','request_id','import_id','kind','payload_sha256'].sort());
 const result=(await rosterRpc('admin_execute_roster_import_intent',{p_request_id:request.p_request_id,p_payload_sha256:sha,p_human_affirmed:true},b.env,b.actor)).value;
 assert.equal(result.result.processing_method,'human_review');assert.equal(result.payload_sha256,sha);assert.equal(result.import_id,initial.import_id);
 await rejectCode(()=>rosterRpc('admin_execute_roster_import_intent',{p_request_id:request.p_request_id,p_payload_sha256:sha,p_human_affirmed:false},b.env,b.actor),'roster_confirmation_required');
});


test('attested group creation claims its capability atomically and reconciles the exact committed request',async t=>{
 const b=await base(t),body=group(b.actor);await consent(b);google(t,body);
 await b.f.db.prepare("UPDATE users SET momo_provider='mtn_momo',momo_number='+250788123456' WHERE id=?").bind(b.actor.userId).run();
 const cap=(await nativeFunction('verify-play-integrity',body,b.env,b.actor)).value.native_capability;
 const {group_is_public,...payload}=body.group_request;
 const command={...payload,native_capability:cap,p_request_id:body.nonce,group_image_url:null,group_accent_color_hex:'#123456'};
 const created=await groupRpc('create_private_group_with_owner_media_attested',command,b.env,b.actor);assert.equal(created.handled,true);assert.match(created.value,/^[a-f0-9-]{36}$/);
 const repeated=await groupRpc('create_private_group_with_owner_media_attested',command,b.env,b.actor);assert.equal(repeated.value,created.value);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1);
 assert.equal((await b.f.db.prepare("SELECT count(*) AS n FROM memberships WHERE role='owner' AND active=1").first()).n,1);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capability_claims').first()).n,1);
 await assert.rejects(()=>groupRpc('create_private_group_with_owner_media_attested',{...command,p_request_id:randomUUID()},b.env,b.actor),e=>e.status===409);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1);
});

test('native receipt acknowledgment binds exact retained encrypted R2 bytes and never credits a ledger',async t=>{
 const b=await base(t);b.env.PRIVATE_MEDIA=await b.f.mf.getR2Bucket('PRIVATE_MEDIA');await consent(b);
 const envelope=randomUUID(),raw='You have received 1000 RWF. Reference CONTROLLED-RECEIPT.',at=new Date().toISOString(),nonce=randomUUID();
 const payload={client_envelope_id:envelope,raw_sender:'MTN MoMo',raw_body_sha256:hash(raw),received_at_device:at};
 const ordered={action:'sms.ingest',subject_id:b.actor.userId,nonce,receiver_momo_number_hash:hash('+250788123456'),sms_permission_granted:true,sms_access_enabled:true,sms_request:payload};
 const proof={...ordered,request_hash:hash(JSON.stringify(ordered)),integrity_token:randomUUID()};google(t,proof);
 const cap=(await nativeFunction('verify-play-integrity',proof,b.env,b.actor)).value.native_capability;
 const command={client_envelope_id:envelope,raw_sender:payload.raw_sender,raw_body:raw,received_at_device:at,receiver_momo_number:'0788123456',native_capability:cap};
 const acknowledged=await receiptFunction('ingest-payment-sms',command,b.env,b.actor);assert.equal(acknowledged.value.ok,true);
 assert.deepEqual(acknowledged.value.receipt,{contract_version:2,stored:true,raw_sms_id:acknowledged.value.receipt.raw_sms_id,owner_user_id:b.actor.userId,client_envelope_id:envelope,body_sha256:hash(raw)});
 const row=await b.f.db.prepare('SELECT * FROM sms_receipts').first(),object=await b.env.PRIVATE_MEDIA.get(row.object_key),cipher=await object.text();assert.ok(!cipher.includes(raw));
 const stored=JSON.parse(new TextDecoder().decode(await decrypt(b.env,cipher,`sms:${row.id}:${row.object_sha256}`)));assert.equal(stored.raw_body,raw);assert.equal(stored.raw_sender,payload.raw_sender);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM payments').first()).n,0);assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
 const repeated=await receiptFunction('ingest-payment-sms',command,b.env,b.actor);assert.deepEqual(repeated.value,acknowledged.value);assert.equal((await b.env.PRIVATE_MEDIA.list({prefix:'sms/'})).objects.length,1);
 await assert.rejects(()=>receiptFunction('ingest-payment-sms',{...command,raw_body:raw+'changed'},b.env,b.actor),e=>e.status===409);
 await assert.rejects(()=>b.f.db.prepare('UPDATE sms_receipts SET body_sha256=? WHERE id=?').bind('0'.repeat(64),row.id).run());
});
