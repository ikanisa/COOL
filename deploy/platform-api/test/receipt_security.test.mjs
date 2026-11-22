import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {randomUUID,createHash,createHmac,generateKeyPairSync,verify as verifySignature} from 'node:crypto';
import {decrypt} from '../src/encryption.js';
import {fixture as adminFixture} from './admin_sms_support/fixture.mjs';

const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??'miniflare');
const require=createRequire(import.meta.url),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
const root=new URL('../',import.meta.url),hash=value=>createHash('sha256').update(value).digest('hex'),phone='+250788123456';
const {privateKey,publicKey}=generateKeyPairSync('rsa',{modulusLength:2048,privateKeyEncoding:{type:'pkcs8',format:'pem'},publicKeyEncoding:{type:'spki',format:'pem'}});
async function modulesUnder(folder){const result=[];for(const item of await readdir(new URL(folder,root),{withFileTypes:true})){const path=folder+item.name;
 if(item.isDirectory())result.push(...await modulesUnder(path+'/'));else if(!item.name.startsWith('._')&&item.name.endsWith('.js'))result.push({type:'ESModule',path:fileURLToPath(new URL(path,root)),contents:await readFile(new URL(path,root),'utf8')});}return result;}

async function fixture(t,{general=false,migrationsThrough=15}={}){
 const messages=[],bindingsByToken=new Map(),providerCalls=[];let gate=async()=>{},r2Failure=false;
 const policy={schema_version:1,purpose:'collect_native_admission',status:'approved',enabled:true,provider:'google_play_integrity',package_name:'app.cool.mobile',approval_id:randomUUID(),approval_evidence_sha256:'1'.repeat(64),project_id:'collect-fixture',cloud_project_number:'123456789012',service_account_email:'play@collect-fixture.iam.gserviceaccount.com',certificate_sha256:['c'.repeat(43)],minimum_version_code:1,capability_ttl_seconds:120,actor_hour_limit:20,project_day_limit:100,approved_at:new Date(Date.now()-60000).toISOString(),valid_until:new Date(Date.now()+3600000).toISOString()};
 const policyJson=JSON.stringify(policy);
 const modules=[{type:'ESModule',path:fileURLToPath(new URL('test/receipt-security-entry.mjs',root)),contents:`
  import worker from '../src/index.js';
  export default {async fetch(request,env,ctx){
   const meta=new WeakMap();let once=false;const pause=async phase=>{if(once||request.headers.get('X-Test-Pause')!==phase)return;once=true;
    const response=await env.TEST_GATE.fetch('https://gate.test',{method:'POST',body:JSON.stringify({phase,path:new URL(request.url).pathname})});if(!response.ok)throw new Error('controlled_failure');};
   const wrap=(stmt,sql)=>{const proxy=new Proxy(stmt,{get(target,key){if(key==='bind')return(...args)=>wrap(target.bind(...args),sql);const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;}});meta.set(proxy,{stmt,sql});return proxy;};
   const db=new Proxy(env.DB,{get(target,key){if(key==='prepare')return sql=>wrap(target.prepare(sql),sql);if(key==='withSession')return()=>db;
    if(key==='batch')return async statements=>{const mutation=statements.some(s=>/INSERT INTO request_receipts/.test(meta.get(s)?.sql??''));if(mutation)await pause('before_commit');const value=await target.batch(statements.map(s=>meta.get(s)?.stmt??s));if(mutation&&request.headers.get('X-Test-Pause')==='lost_reply'){await pause('lost_reply');throw new Error('controlled_lost_reply_after_commit');}return value;};
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;}});
   const media=new Proxy(env.PRIVATE_MEDIA,{get(target,key){if(key==='put')return async(...args)=>{await pause('before_put');return target.put(...args);};if(key==='get')return async(...args)=>{await pause('before_get');return target.get(...args);};const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;}});
   return worker.fetch(request,{...env,DB:db,PRIVATE_MEDIA:media},ctx);
  }};`},...await modulesUnder('src/')];
 const mf=new Miniflare(convertV4MiniflareOptions({modules,modulesRoot:fileURLToPath(root),compatibilityDate:'2026-10-14',cf:false,d1Databases:{DB:randomUUID()},d1Persist:false,r2Buckets:{PRIVATE_MEDIA:randomUUID()},r2Persist:false,
  bindings:{APP_ENVIRONMENT:'test',AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',AUTH_ISSUER:'collect-test',AUTH_AUDIENCE:'collect',AUTH_MEMBER_REGISTRATION_ENABLED:'true',
   OTP_DELIVERY_URL:'https://trusted-relay.example/otp',OTP_DELIVERY_TOKEN:'test-relay-token-123456789',TURNSTILE_REQUIRED:'true',TURNSTILE_SECRET:'test-turnstile-secret-123456',TURNSTILE_HOSTNAME:'collect.example',TURNSTILE_ACTION:'collect-login',ALLOWED_ORIGINS:'https://collect.example',
   DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DATA_KEY_ID:'receipt-security-test-v1',...(general?{}:{PLAY_INTEGRITY_POLICY_JSON:policyJson,PLAY_INTEGRITY_POLICY_SHA256:hash(policyJson),PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:policy.project_id,client_email:policy.service_account_email,private_key:privateKey,token_uri:'https://oauth2.googleapis.com/token'})})},
  serviceBindings:{TEST_GATE:async request=>{await gate(await request.json());return Response.json({ok:true});}},outboundService:async request=>{
   if(request.url==='https://challenges.cloudflare.com/turnstile/v0/siteverify')return Response.json({success:true,hostname:'collect.example',action:'collect-login',challenge_ts:new Date().toISOString()});
   if(request.url==='https://trusted-relay.example/otp'){const value=await request.json();messages.push(value);return Response.json({accepted:true,request_id:value.request_id});}
   providerCalls.push(request.url);
   if(request.url==='https://oauth2.googleapis.com/token'){
    const assertion=new URLSearchParams(await request.text()).get('assertion'),parts=assertion.split('.');assert.equal(verifySignature('RSA-SHA256',Buffer.from(parts[0]+'.'+parts[1]),publicKey,Buffer.from(parts[2],'base64url')),true);
    const claims=JSON.parse(Buffer.from(parts[1],'base64url').toString());assert.equal(claims.scope,'https://www.googleapis.com/auth/playintegrity');assert.equal(claims.aud,request.url);
    return Response.json({access_token:'controlled-google-admission-token',token_type:'Bearer',expires_in:3600});
   }
   assert.equal(request.url,'https://playintegrity.googleapis.com/v1/app.cool.mobile:decodeIntegrityToken');assert.equal(request.headers.get('Authorization'),'Bearer controlled-google-admission-token');const token=(await request.json()).integrity_token,proof=bindingsByToken.get(token);assert.ok(proof);
   return Response.json({tokenPayloadExternal:{requestDetails:{requestPackageName:'app.cool.mobile',requestHash:proof.request_hash,timestampMillis:String(Date.now())},appIntegrity:{packageName:'app.cool.mobile',appRecognitionVerdict:'PLAY_RECOGNIZED',versionCode:'12',certificateSha256Digest:policy.certificate_sha256},accountDetails:{appLicensingVerdict:'LICENSED'},deviceIntegrity:{deviceRecognitionVerdict:['MEETS_DEVICE_INTEGRITY']}}});
  }}));
 t.after(()=>mf.dispose());const db=await mf.getD1Database('DB');
 for(const file of (await readdir(new URL('migrations/',root))).filter(n=>/^\d+.*\.sql$/.test(n)&&Number(n.slice(0,4))<=migrationsThrough).sort())for(const sql of unstable_splitSqlQuery(await readFile(new URL('migrations/'+file,root),'utf8')))await db.prepare(sql).run();
 const f={mf,db,providerCalls,setGate:callback=>{gate=callback;},bucket:await mf.getR2Bucket('PRIVATE_MEDIA')};
 f.call=async(path,data={},session=null,{method='POST',pause=null}={})=>{
  const response=await mf.dispatchFetch('https://api.collect.example'+path,{method,headers:{Origin:'https://collect.example','Content-Type':'application/json','CF-Connecting-IP':'192.0.2.1',...(session?{Authorization:'Bearer '+session.access_token}:{}),...(pause?{'X-Test-Pause':pause}:{})},...(method==='GET'?{}:{body:JSON.stringify(data)})});
  const raw=await response.text();let body;try{body=JSON.parse(raw);}catch{body=raw;}return {status:response.status,body};
 };
 f.login=async identity=>{const otp=await f.call('/v1/auth/otp',{...identity,captcha_token:randomUUID()}),message=messages.find(m=>m.request_id===otp.body.challenge_id);assert.equal(otp.status,202,JSON.stringify(otp));
  const verify=await f.call('/v1/auth/verify',{...identity,challenge_id:otp.body.challenge_id,code:message.code,captcha_token:randomUUID()});assert.equal(verify.status,200,JSON.stringify(verify));return verify.body;};
 f.session=await f.login({phone});
 f.consent=async enabled=>f.call('/v1/rpc/record_sms_access_consent',{enabled,...(general?{}:{momo_number_hash:hash(phone)}),build_channel:general?'android_sms_access':'android_native_sms',device_label:'flutter_app',request_id:randomUUID()},f.session);
 assert.equal((await f.consent(true)).status,200);
 f.admit=async({envelope=randomUUID(),raw='Controlled native SMS receipt, untrusted financial evidence.',sender='MTN MoMo',received=new Date().toISOString()}={})=>{
  if(general)return {client_envelope_id:envelope,raw_sender:sender,raw_body:raw,received_at_device:received,completeness:'complete'};
  const payload={client_envelope_id:envelope,raw_sender:sender,raw_body_sha256:hash(raw),received_at_device:received},ordered={action:'sms.ingest',subject_id:f.session.user.id,nonce:randomUUID(),receiver_momo_number_hash:hash(phone),sms_permission_granted:true,sms_access_enabled:true,sms_request:payload},proof={...ordered,request_hash:hash(JSON.stringify(ordered)),integrity_token:randomUUID()};bindingsByToken.set(proof.integrity_token,proof);
  const admission=await f.call('/v1/functions/verify-play-integrity',proof,f.session);assert.equal(admission.status,200,JSON.stringify(admission));return {client_envelope_id:envelope,raw_sender:sender,raw_body:raw,received_at_device:received,receiver_momo_number:phone,native_capability:admission.body.native_capability};
 };
 f.capture=(command,options={})=>f.call('/v1/functions/'+(general?'ingest-client-sms':'ingest-payment-sms'),command,f.session,options);
 return f;
}

test('concurrent identical SMS retries retain one encrypted object and one single-use admission claim',async t=>{
 const f=await fixture(t),command=await f.admit(),results=await Promise.all([f.capture(command),f.capture(command)]);
 for(const result of results)assert.equal(result.status,200,JSON.stringify(result));assert.deepEqual(results[0].body,results[1].body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM native_capability_claims').first()).n,1);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,1);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM payments').first()).n,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
});

test('withdrawn consent during R2 await prevents capture, rolls back claim/receipt, and removes orphan bytes',async t=>{
 const f=await fixture(t),command=await f.admit();f.setGate(async()=>{assert.equal((await f.consent(false)).status,200);});
 const result=await f.capture(command,{pause:'before_put'});assert.ok([403,409].includes(result.status),JSON.stringify(result));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM native_capability_claims').first()).n,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,0);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,0);
});

test('session revocation during R2 await prevents capture without a retained orphan',async t=>{
 const f=await fixture(t),command=await f.admit(),claims=JSON.parse(Buffer.from(f.session.access_token.split('.')[1],'base64url').toString());
 f.setGate(async()=>f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='controlled_midawait_logout' WHERE id=?").bind(Math.floor(Date.now()/1000),claims.session_id).run());
 const result=await f.capture(command,{pause:'before_put'});assert.ok([401,403].includes(result.status),JSON.stringify(result));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,0);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,0);
});

test('SMS lost reply returns the committed receipt without claiming provider confirmation or crediting money',async t=>{
 const f=await fixture(t),command=await f.admit(),result=await f.capture(command,{pause:'lost_reply'});assert.equal(result.status,200,JSON.stringify(result));
 assert.equal(result.body.ok,true);assert.equal(result.body.receipt.stored,true);assert.ok(!('confirmed' in result.body.receipt));assert.ok(!('payment_id' in result.body.receipt));
 assert.deepEqual((await f.capture(command)).body,result.body);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,1);
 const row=await f.db.prepare('SELECT * FROM sms_receipts').first();assert.equal(row.evidence_level,'client_received');assert.equal(row.status,'received');
});

test('changed sender or timestamp cannot reuse a stored SMS envelope despite unchanged body text',async t=>{
 const f=await fixture(t),command=await f.admit();assert.equal((await f.capture(command)).status,200);
 for(const changed of [{raw_sender:'Other sender'},{received_at_device:new Date(Date.parse(command.received_at_device)+1000).toISOString()}])assert.equal((await f.capture({...command,...changed})).status,409);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);
});

test('revocation after SMS commit does not return stale success or delete the committed encrypted evidence',async t=>{
 const f=await fixture(t),command=await f.admit(),claims=JSON.parse(Buffer.from(f.session.access_token.split('.')[1],'base64url').toString());
 f.setGate(async()=>f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='controlled_postcommit_logout' WHERE id=?").bind(Math.floor(Date.now()/1000),claims.session_id).run());
 const result=await f.capture(command,{pause:'lost_reply'});assert.ok([401,403].includes(result.status),JSON.stringify(result));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,1);
});

test('opted-in member captures unknown-source SMS without wallet, group, profile, registry or Play configuration',async t=>{
 const f=await fixture(t,{general:true});
 await f.db.prepare("UPDATE users SET full_name='',phone=NULL,momo_number='',country_code='KE',currency_code='KES' WHERE id=?").bind(f.session.user.id).run();
 assert.equal((await f.consent(true)).status,200,'Capture consent does not attest a Rwanda wallet or require a completed profile');
 const command=await f.admit({raw:'Réception\n  原文  (********007)'}),result=await f.capture({...command,provider_confirmation:true,financial_effects:999,payment_id:randomUUID()});
 assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.receipt.source_provenance,'member_device_unverified');assert.equal(result.body.receipt.receiving_source_known,false);assert.equal(result.body.receipt.financial_effects,0);
 assert.ok(!('payment_id' in result.body.receipt));assert.ok(!('confirmed' in result.body.receipt));
 const row=await f.db.prepare('SELECT * FROM sms_receipts').first();assert.equal(row.owner_user_id,f.session.user.id);assert.notEqual(row.receiver_hash,hash(phone));assert.equal(row.evidence_level,'client_received');
 const encrypted=await(await f.bucket.get(row.object_key)).text();assert.ok(!encrypted.includes(command.raw_body));
 const payload=JSON.parse(new TextDecoder().decode(await decrypt({DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DATA_KEY_ID:'receipt-security-test-v1'},encrypted,`sms:${row.id}:${row.object_sha256}`)));
 assert.equal(payload.raw_body,command.raw_body);assert.equal(payload.receiver_momo_number,null);assert.equal(payload.receiving_source_known,false);assert.ok(!('provider_confirmation' in payload));
 const job=await f.db.prepare('SELECT * FROM momo_processing_jobs').first();assert.equal(job.state,'source_unresolved');assert.equal(job.binding_id,null);assert.equal(job.receiving_account_id,null);
 for(const table of ['collections','momo_receiving_accounts','momo_gateway_bindings','momo_gateway_credentials','native_capabilities','payments','ledger_entries','notification_events'])assert.equal((await f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n,0,table);
 assert.deepEqual(f.providerCalls,[]);
});

test('ordinary raw retention works on schema13 before optional MoMo extraction migrations',async t=>{
 const f=await adminFixture(t,{MOMO_PROCESSING_PAUSED:'true'},{migrationsThrough:13}),member=await f.seedMember(),session=await f.nativeLogin(member.phone),headers={Authorization:'Bearer '+session.access_token};
 const consent=await f.call('/v1/rpc/record_sms_access_consent',{origin:'https://collect.example',headers,data:{enabled:true,build_channel:'android_sms_access',request_id:randomUUID()}});assert.equal(consent.status,200,JSON.stringify(consent));
 const command={client_envelope_id:randomUUID(),raw_sender:'MTN MoMo',raw_body:'SYNTHETIC unknown receiving source, no financial claim',received_at_device:new Date().toISOString(),completeness:'complete'};
 const result=await f.call('/v1/functions/ingest-client-sms',{origin:'https://collect.example',headers,data:command});assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.receipt.stored,true);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM sqlite_schema WHERE name='momo_processing_jobs'").first()).n,0);
 const account=await f.seedAccount(),login=await f.login(account),metadata=await f.call('/api/admin/sms/receipts',{method:'GET',cookie:login.cookie});assert.equal(metadata.status,200,JSON.stringify(metadata));assert.equal(metadata.body.rows.length,1);
 const row=metadata.body.rows[0];assert.equal(row.id,result.body.receipt.raw_sms_id);assert.equal(row.user_id,member.id);assert.equal(row.source_kind,'capture');assert.equal(row.extraction_status,'not_extracted');assert.equal(row.transaction_id,null);assert.equal(row.provider_confirmation,false);assert.equal(row.settlement_status,'not_asserted');assert.equal(row.amount_rwf,null);assert.equal(row.payee_id,null);
 const detail=await f.call('/api/admin/sms/receipts/capture/'+row.id,{method:'GET',cookie:login.cookie});assert.equal(detail.status,200,JSON.stringify(detail));assert.equal(detail.body.can_extract,false);assert.equal(detail.body.resource.id,row.id);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);assert.equal((await(await f.mf.getR2Bucket('PRIVATE_MEDIA')).list({prefix:'sms/'})).objects.length,1);
});

test('general capture concurrent and lost-response retries return one immutable ACK without renewing consent',async t=>{
 const f=await fixture(t,{general:true}),command=await f.admit(),before=(await f.db.prepare('SELECT count(*) AS n FROM native_consents').first()).n;
 const results=await Promise.all([f.capture(command,{pause:'lost_reply'}),f.capture(command)]);
 for(const result of results)assert.equal(result.status,200,JSON.stringify(result));assert.deepEqual(results[0].body,results[1].body);
 assert.deepEqual((await f.capture(command)).body,results[0].body);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,1);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM native_consents').first()).n,before);
 for(const changed of [{raw_body:command.raw_body+'changed'},{raw_sender:'Other sender'},{completeness:'incomplete'}])assert.equal((await f.capture({...command,...changed})).status,409);
});

test('latest group consent keeps capture enabled while later explicit disable from another session denies upload',async t=>{
 const f=await fixture(t,{general:true}),command=await f.admit();
 assert.equal((await f.call('/v1/rpc/record_sms_access_consent',{enabled:true,momo_number_hash:hash(phone),build_channel:'android_group_create_attested',request_id:randomUUID()},f.session)).status,200);
 assert.equal((await f.capture(command)).status,200);
 // Model an already signed-in second installation without requesting another
 // OTP inside the genuine authentication throttle window.
 const parts=f.session.access_token.split('.'),claims=JSON.parse(Buffer.from(parts[1],'base64url')),saved=await f.db.prepare('SELECT * FROM auth_sessions WHERE id=?').bind(claims.session_id).first(),row={...saved,id:randomUUID()};
 await f.db.prepare('INSERT INTO auth_sessions('+Object.keys(row).join(',')+') VALUES('+Object.keys(row).map(()=>'?').join(',')+')').bind(...Object.values(row)).run();
 const payload=Buffer.from(JSON.stringify({...claims,session_id:row.id})).toString('base64url'),unsigned=parts[0]+'.'+payload,second={...f.session,access_token:unsigned+'.'+createHmac('sha256','test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890').update(unsigned).digest('base64url')};
 assert.equal((await f.call('/v1/rpc/record_sms_access_consent',{enabled:false,build_channel:'android_sms_access',request_id:randomUUID()},second)).status,200);
 assert.equal((await f.capture(await f.admit())).status,403);assert.equal((await f.capture(command)).status,403,'Withdrawal also fences replay acknowledgements');
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);
});

test('general capture rechecks consent and current session after encrypted storage awaits, retaining no orphan',async t=>{
 const f=await fixture(t,{general:true}),command=await f.admit();f.setGate(async()=>{assert.equal((await f.consent(false)).status,200);});
 assert.equal((await f.capture(command,{pause:'before_put'})).status,403);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,0);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,0);
 assert.equal((await f.consent(true)).status,200);
 const claims=JSON.parse(Buffer.from(f.session.access_token.split('.')[1],'base64url').toString());f.setGate(async()=>{await f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='controlled_general_capture_logout' WHERE id=?").bind(Math.floor(Date.now()/1000),claims.session_id).run();});
 assert.ok([401,403].includes((await f.capture(command,{pause:'before_put'})).status));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,0);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,0);
});

async function syntheticBudgetRows(f,count,createdAt){
 const original=await f.db.prepare('SELECT * FROM sms_receipts WHERE owner_user_id=? LIMIT 1').bind(f.session.user.id).first(),rows=[];
 for(let i=0;i<count;i++){const row={...original,id:randomUUID(),client_envelope_id:randomUUID(),object_key:'synthetic-budget-only/'+randomUUID(),created_at:createdAt};rows.push(f.db.prepare('INSERT INTO sms_receipts('+Object.keys(row).join(',')+') VALUES('+Object.keys(row).map(()=>'?').join(',')+')').bind(...Object.values(row)));}
 // Bound synthetic setup batches instead of sending a thousand retained rows
 // through one local proxy request. The actual budget race remains one batch
 // per real capture and still admits exactly one last available slot.
 for(let offset=0;offset<rows.length;offset+=100)await f.db.batch(rows.slice(offset,offset+100));
}
test('general capture rate budget is atomic, replay free and independent of provider configuration',async t=>{
 const f=await fixture(t,{general:true}),original=await f.admit();assert.equal((await f.capture(original)).status,200);await syntheticBudgetRows(f,58,new Date().toISOString());
 const results=await Promise.all([f.capture(await f.admit()),f.capture(await f.admit())]);assert.deepEqual(results.map(r=>r.status).sort(),[200,429]);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,60);assert.equal((await f.bucket.list({prefix:'sms/'})).objects.length,2);assert.equal((await f.capture(original)).status,200,'A committed capture can reconcile at the quota');
 // A separate member has one recent capture and999 older retained captures:
 // the day limit must work even when the minute allowance remains available.
 f.session=await f.login({phone:'+250788123457'});assert.equal((await f.consent(true)).status,200);assert.equal((await f.capture(await f.admit())).status,200);
 await syntheticBudgetRows(f,999,new Date(Date.now()-120000).toISOString());
 assert.equal((await f.capture(await f.admit({received:'2000-01-01T00:00:00Z'}))).status,429);assert.deepEqual(f.providerCalls,[]);
});
