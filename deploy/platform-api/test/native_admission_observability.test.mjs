import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID,createHash,generateKeyPairSync,verify as verifySignature} from 'node:crypto';
import {fixture} from './support/auth_fixture.mjs';
import {functionRpc,nativeRpc} from '../src/native_integrity.js';

// Admission executes its production code against actual workerd D1 bindings.
// Google responses, credentials and approval assertions are controlled fixtures;
// these tests do not establish real provider approval, admission or alert delivery.
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{format:'pem',type:'pkcs8'},publicKeyEncoding:{format:'pem',type:'spki'}});
const hash=value=>createHash('sha256').update(value).digest('hex');
const certificate=Buffer.from(hash('isolated-publisher-certificate'),'hex').toString('base64url');

async function setup(t,{limit=6}={}){
 const f=await fixture();t.after(()=>f.close());const session=await f.login(),resolved=await f.actor(session),actor={...resolved.body,permissions:new Set(resolved.body.permissions)};
 const policy={schema_version:1,purpose:'collect_native_admission',status:'approved',enabled:true,provider:'google_play_integrity',package_name:'app.cool.mobile',approval_id:randomUUID(),approval_evidence_sha256:'1'.repeat(64),project_id:'collect-fixture',cloud_project_number:'123456789012',service_account_email:'play@collect-fixture.iam.gserviceaccount.com',certificate_sha256:[certificate],minimum_version_code:1,capability_ttl_seconds:120,actor_hour_limit:limit,project_day_limit:100,approved_at:new Date(Date.now()-60000).toISOString(),valid_until:new Date(Date.now()+3600000).toISOString()};
 const raw=JSON.stringify(policy),env={DB:f.db,DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DATA_KEY_ID:'observability-fixture-v1',PLAY_INTEGRITY_POLICY_JSON:raw,PLAY_INTEGRITY_POLICY_SHA256:hash(raw),PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:policy.project_id,client_email:policy.service_account_email,private_key:privateKey,token_uri:'https://oauth2.googleapis.com/token'})};
 await nativeRpc('record_sms_access_consent',{enabled:true,momo_number_hash:hash('+250788123456'),build_channel:'android_group_create_attested'},env,actor);
 return {f,actor,env};
}
function request(actor){
 const receiver=hash('+250788123456'),payload={group_name:'PRIVATE-GROUP-NAME',group_description:'PRIVATE-CLIENT-DESCRIPTION',receiver_momo_number:'0788123456',receiver_momo_number_hash:receiver,receiver_label:'PRIVATE-RECEIVER-NAME',group_collection_type:'ikimina',group_category_subtype:null,group_purpose_label:null,group_is_public:false};
 const value={action:'group.create',subject_id:actor.userId,nonce:randomUUID(),receiver_momo_number_hash:receiver,sms_permission_granted:true,sms_access_enabled:true,group_request:payload};
 return {...value,request_hash:hash(JSON.stringify(value)),integrity_token:'PRIVATE-INTEGRITY-TOKEN-'+randomUUID()};
}
function capture(t){
 const events=[],previous={warn:console.warn,error:console.error};
 for(const level of Object.keys(previous))console[level]=value=>{const record=JSON.parse(value);assert.equal(record.event,'native_admission_failure');events.push({level,record});};
 t.after(()=>{console.warn=previous.warn;console.error=previous.error;});return events;
}
function assertRecord(event,{code,phase,status,level},body,actor){
 assert.equal(event.level,level);assert.deepEqual(Object.keys(event.record).sort(),['automatic_retry','code','duration_ms','event','phase','schema_version','status']);
 assert.equal(event.record.schema_version,1);assert.equal(event.record.code,code);assert.equal(event.record.phase,phase);assert.equal(event.record.status,status);assert.equal(event.record.automatic_retry,false);
 assert.ok(Number.isSafeInteger(event.record.duration_ms)&&event.record.duration_ms>=0&&event.record.duration_ms<=60000);
 const serialized=JSON.stringify(event);
 for(const secret of [body.integrity_token,body.nonce,body.request_hash,actor.userId,actor.sessionId,'0788123456','PRIVATE-GROUP-NAME','PRIVATE-CLIENT-DESCRIPTION','PRIVATE-RECEIVER-NAME','PRIVATE-PROVIDER-BODY','PRIVATE-GOOGLE-TOKEN','PRIVATE KEY'])assert.ok(!serialized.includes(secret),secret);
}
function provider(t,body,{failure=null}={}){
 const previous=globalThis.fetch,calls=[];globalThis.fetch=async(url,options)=>{
  calls.push(String(url));
  if(url==='https://oauth2.googleapis.com/token'){
   const assertion=new URLSearchParams(options.body).get('assertion'),[header,payload,signature]=assertion.split('.');assert.equal(verifySignature('RSA-SHA256',Buffer.from(header+'.'+payload),publicKey,Buffer.from(signature,'base64url')),true);
   if(failure==='oauth')return new Response('PRIVATE-PROVIDER-BODY',{status:503});
   return Response.json({access_token:'PRIVATE-GOOGLE-TOKEN',token_type:'Bearer',expires_in:3600});
  }
  assert.equal(url,'https://playintegrity.googleapis.com/v1/app.cool.mobile:decodeIntegrityToken');assert.equal(options.headers.Authorization,'Bearer PRIVATE-GOOGLE-TOKEN');assert.equal(JSON.parse(options.body).integrity_token,body.integrity_token);
  if(failure==='decode')return new Response('PRIVATE-PROVIDER-BODY',{status:503});
  return Response.json({tokenPayloadExternal:{requestDetails:{requestPackageName:'app.cool.mobile',requestHash:body.request_hash,timestampMillis:String(Date.now())},appIntegrity:{packageName:'app.cool.mobile',appRecognitionVerdict:'PLAY_RECOGNIZED',versionCode:'12',certificateSha256Digest:[certificate]},accountDetails:{appLicensingVerdict:'LICENSED'},deviceIntegrity:{deviceRecognitionVerdict:['MEETS_DEVICE_INTEGRITY']}}});
 };t.after(()=>{globalThis.fetch=previous;});return calls;
}

test('missing approved configuration emits a bounded 503 event without spending provider quota or retaining extra audit rows',async t=>{
 const b=await setup(t),body=request(b.actor),events=capture(t),calls=provider(t,body);delete b.env.PLAY_INTEGRITY_POLICY_JSON;
 await assert.rejects(()=>functionRpc('verify-play-integrity',body,b.env,b.actor),error=>error.status===503&&error.code==='play_integrity_unavailable');
 assert.equal(events.length,1);assertRecord(events[0],{code:'play_integrity_unavailable',phase:'configuration',status:503,level:'error'},body,b.actor);assert.equal(calls.length,0);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_reservations').first()).n,0);assert.equal((await b.f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action LIKE 'native.admission.%'").first()).n,0);
});

for(const phase of ['oauth','decode'])test('provider '+phase+' outage remains ambiguous without re-dispatch and logs only fixed server fields',async t=>{
 const b=await setup(t),body=request(b.actor),events=capture(t),calls=provider(t,body,{failure:phase});
 await assert.rejects(()=>functionRpc('verify-play-integrity',body,b.env,b.actor),error=>error.status===503&&error.code==='play_integrity_unavailable');
 assert.equal(events.length,1);assertRecord(events[0],{code:'play_integrity_unavailable',phase,status:503,level:'error'},body,b.actor);assert.equal(calls.length,phase==='oauth'?1:2);
 await assert.rejects(()=>functionRpc('verify-play-integrity',body,b.env,b.actor),error=>error.status===409&&error.code==='integrity_request_replayed');assert.equal(events.length,1);assert.equal(calls.length,phase==='oauth'?1:2);
 assert.equal((await b.f.db.prepare('SELECT state FROM native_reservations').first()).state,'ambiguous');assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capabilities').first()).n,0);
});

test('actor quota failure remains 429 and emits a distinct warning without another provider call or attacker-controlled audit rows',async t=>{
 const b=await setup(t,{limit:1}),body=request(b.actor),events=capture(t),calls=provider(t,body);assert.equal((await functionRpc('verify-play-integrity',body,b.env,b.actor)).value.status,'pass');
 const blocked=request(b.actor);await assert.rejects(()=>functionRpc('verify-play-integrity',blocked,b.env,b.actor),error=>error.status===429&&error.code==='integrity_budget_exhausted');
 assert.equal(events.length,1);assertRecord(events[0],{code:'integrity_budget_exhausted',phase:'reservation',status:429,level:'warn'},blocked,b.actor);assert.equal(calls.length,2);
 assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_reservations').first()).n,1);assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capabilities').first()).n,1);
 assert.equal((await b.f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action LIKE 'native.admission.%'").first()).n,2);
});

test('malformed client bindings do not generate operational outage events or capabilities',async t=>{
 const b=await setup(t),body=request(b.actor),events=capture(t),calls=provider(t,body);
 await assert.rejects(()=>functionRpc('verify-play-integrity',{...body,request_hash:'0'.repeat(64)},b.env,b.actor),error=>error.status===400&&error.code==='integrity_binding_mismatch');
 assert.equal(events.length,0);assert.equal(calls.length,0);assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capabilities').first()).n,0);
});

test('a failing operational logger cannot change the fail-closed admission outcome',async t=>{
 const b=await setup(t),body=request(b.actor);delete b.env.PLAY_INTEGRITY_POLICY_JSON;const previous=console.error;console.error=()=>{throw new Error('controlled_logger_failure');};t.after(()=>{console.error=previous;});
 await assert.rejects(()=>functionRpc('verify-play-integrity',body,b.env,b.actor),error=>error.status===503&&error.code==='play_integrity_unavailable');assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM native_capabilities').first()).n,0);
});
