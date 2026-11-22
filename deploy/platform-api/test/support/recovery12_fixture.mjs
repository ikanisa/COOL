// Controlled current12 source: normal cookie/password/TOTP and member phone OTP
// flows, actual D1/R2, synthetic identities/policy/data only. No provider sends.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {readFile} from 'node:fs/promises';
import {fixture} from './notification_operator_integration_fixture.mjs';
import {claims} from './auth_fixture.mjs';
import {retentionSchema,retentionClasses,retentionSnapshot} from '../../src/privacy_retention_catalog.js';
import {installSql,restoreSql} from '../../../../scripts/cloudflare/platform_backup.mjs';
import {quarantineSchemaProfiles,assistedSmsRecoveryTables} from '../../../../scripts/cloudflare/recovery_quarantine.mjs';
import {encrypt} from '../../src/encryption.js';
export const sourceId='f'.repeat(64),database='a6a0d284-c445-4fe3-8e64-af5fd42491ae';
export const sha=raw=>createHash('sha256').update(raw).digest('hex');
export const controls=['privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers'];
export const dataKeys={DATA_KEY_ID:'admin-test-v1',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64')};
export const identityBindings={AUTH_IDENTITY_KEY_ID:'recovery-current-v2',AUTH_IDENTITY_HASH_KEY:Buffer.alloc(32,151).toString('base64'),AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({'recovery-old-v1':Buffer.alloc(32,152).toString('base64')})};
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r.body));return r.body.result??r.body;};
export async function captureD1(db){
 await retentionSchema({DB:db});
 const schema=(await db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' AND name NOT IN('_cf_KV','_cf_METADATA') ORDER BY type,name").all()).results,copy=new DatabaseSync(':memory:');
 try{
  copy.exec('BEGIN;PRAGMA defer_foreign_keys=ON');for(const row of schema.filter(r=>r.type==='table'))installSql(copy,row.sql);
  for(const {name}of schema.filter(r=>r.type==='table'))for(const row of (await db.prepare('SELECT * FROM "'+name+'"').all()).results)copy.prepare('INSERT INTO "'+name+'"('+Object.keys(row).map(c=>'"'+c+'"').join(',')+') VALUES('+Object.keys(row).map(()=>'?').join(',')+')').run(...Object.values(row));
  copy.exec('DELETE FROM sqlite_sequence');for(const row of (await db.prepare('SELECT * FROM sqlite_sequence').all()).results)copy.prepare('INSERT INTO sqlite_sequence(name,seq) VALUES(?,?)').run(row.name,row.seq);
  for(const row of schema.filter(r=>r.type!=='table'))installSql(copy,row.sql);copy.exec('COMMIT');assert.equal(copy.prepare('PRAGMA foreign_key_check').all().length,0);assert.equal(copy.prepare('PRAGMA integrity_check').get().integrity_check,'ok');return restoreSql(copy);
 }finally{copy.close();}
}
export async function current12Fixture(t){
 const f=await fixture(t,{BUILD_SOURCE_ID:sourceId,...identityBindings},{migrationsThrough:12}),bucket=await f.mf.getR2Bucket('PRIVATE_MEDIA');
 const account=await f.seedAccount(),operator=await f.stepUp(await f.login(account)),phone=await f.nativeLogin(),recipient=claims(phone.access_token).sub;
 const post=(path,data,extra={})=>f.call('/api/admin/'+path,{cookie:operator.cookie,data,headers:{'X-Collect-Admin':'1',...extra}});
 const member=(session,name,data)=>f.call('/v1/rpc/'+name,{origin:'https://collect.example',data,headers:{Authorization:'Bearer '+session.access_token}});
 const command=(action,body)=>post('notification-operator',{action,...body});
 const access=ok(await post('notification-operator/access',{request_id:randomUUID(),expected_read:false,expected_manage:false,expected_decision_revision:0,enabled:true,owner_confirmation:true}));assert.equal(access.decision_revision,1);
 async function group(user,title){const id=randomUUID(),at=new Date().toISOString();await f.db.batch([
  f.db.prepare('INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,?,\'ikimina\',?,?)').bind(id,'synthetic-'+id,user,title,at,at),
  f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)").bind(randomUUID(),id,user,at),
 ]);return id;}
 const smsGroup=await group(recipient,'Synthetic recovery receipt group');
 ok(await post('notification-operator/policies/'+smsGroup,{request_id:randomUUID(),expected_revision:0,enabled:true,owner_confirmation:true}));
 // Record a first no-op and a later real opt-in. Both decisions must survive.
 const disabled=ok(await member(phone,'set_assisted_sms_consent_v1',{p_collection_id:smsGroup,p_expected_revision:0,p_expected_decision_revision:0,p_opt_in:false,p_request_id:randomUUID()}));assert.equal(disabled.decision_revision,1);assert.equal(disabled.consent_revision,0);
 const consent=ok(await member(phone,'set_assisted_sms_consent_v1',{p_collection_id:smsGroup,p_expected_revision:0,p_expected_decision_revision:1,p_opt_in:true,p_request_id:randomUUID()}));assert.equal(consent.decision_revision,2);assert.equal(consent.consent_revision,1);
 async function payment(user,collection,amount=1250,{reversed=false}={}){
  const id=randomUUID(),evidence=randomUUID(),entry=randomUUID(),at=new Date().toISOString(),body=new TextEncoder().encode('SYNTHETIC RECOVERY EVIDENCE '+evidence),bodySha=sha(body),objectKey='synthetic-evidence/'+evidence;
  await bucket.put(objectKey,await encrypt(dataKeys,body,`evidence:${evidence}:${bodySha}`));
  await f.db.batch([
   f.db.prepare("INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,amount_minor,observed_at,created_at) VALUES(?,?,?,?,?,?,'text/plain','operator_recorded',?,?,?)").bind(evidence,collection,user,objectKey,bodySha,body.length,amount,at,at),
   f.db.prepare('INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES(?,?,?,?,?,?,?)').bind(id,collection,user,evidence,amount,reversed?'reversed':'reconciled',at),
   f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)").bind(entry,id,collection,user,amount,evidence,account.userId,randomUUID(),at),
   ...(reversed?[f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'reversal',?,?,?,?,?)").bind(randomUUID(),id,collection,user,-amount,entry,evidence,account.userId,randomUUID(),at)]:[]),
  ]);return {id,evidence,entry,objectKey,plaintext_sha256:bodySha};
 }
 const payments=[await payment(recipient,smsGroup),await payment(recipient,smsGroup)];
 const materialized=ok(await post('notification-operator/materialize',{request_id:randomUUID(),collection_id:smsGroup,limit:2}));assert.equal(materialized.materialized_count,2);
 const jobs=[];
 for(const queued of materialized.materialized_jobs){
  const claim=ok(await command('claim',{job_id:queued.job_id,request_id:randomUUID(),worker_id:'synthetic-local-recovery',expected_fence:0}));
  const fields={job_id:claim.job_id,claim_token:claim.claim_token,fence_version:claim.fence_version},content=ok(await command('get_claimed',fields)),confirmationId=randomUUID();
  ok(await command('confirm',{...fields,request_id:randomUUID(),confirmation_id:confirmationId,body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:content.destination_revision,user_confirmation:true}));
  const startBody={...fields,request_id:randomUUID(),confirmation_id:confirmationId};
  if(jobs.length===0){const started=ok(await command('record_send_start',startBody));assert.equal(started.may_send,true);ok(await command('record_outcome',{request_id:randomUUID(),attempt_id:started.attempt_id,observation:'uncertain',evidence_reference_sha256:sha('SYNTHETIC NO TRANSPORT INVOCATION')}));}
  jobs.push({fields,startBody,content});
 }
 // Different subject: genuine91-task retention state with real persistent
 // barrier/claims/outcomes/effect, without pretending active SMS work is drained.
 const subjectSession=await f.nativeLogin('+250789123456'),subject=claims(subjectSession.access_token).sub,subjectGroup=await group(subject,'Synthetic retention recovery group');
 await payment(subject,subjectGroup,1000,{reversed:true});const upload=randomUUID(),objectKey='synthetic-upload/'+upload,uploadBody='SYNTHETIC RETENTION OBJECT';await bucket.put(objectKey,uploadBody);
 await f.db.prepare("INSERT INTO upload_objects(id,user_id,object_key,sha256,size_bytes,content_type,purpose,created_at) VALUES(?,?,?,?,?,'text/plain','synthetic',?)").bind(upload,subject,objectKey,sha(uploadBody),Buffer.byteLength(uploadBody),new Date().toISOString()).run();
 const intake=ok(await member(subjectSession,'request_account_deletion_v1',{p_request_id:randomUUID(),p_reason:null}));
 let policySha=null;const names={inspect:'admin_inspect_account_retention_scope_v1',plan:'admin_plan_account_retention_v1',claim:'admin_claim_account_retention_task_v1',execute:'admin_execute_account_retention_task_v1',status:'admin_get_account_retention_status_v1'};
 const retention=(action,input,extra={})=>post('privacy/'+names[action],Object.fromEntries(Object.entries(input).map(([k,v])=>['p_'+k,v])),{...(policySha?{'X-Test-Privacy-Pin':policySha}:{}),...extra});
 await retentionSnapshot({DB:f.db,PRIVATE_MEDIA:bucket},subject);
 const schema=await retentionSchema({DB:f.db}),scope=ok(await retention('inspect',{request_id:intake.request_id,expected_review_revision:0,expected_source_id:sourceId}));
 const past=new Date(Date.now()-60000).toISOString(),future=new Date(Date.now()+3600000).toISOString(),policy={contract_version:1,policy_id:randomUUID(),version:'synthetic-current12-test-only',environment:'test',synthetic_test_only:true,approval_evidence_sha256:sha('SYNTHETIC TEST APPROVAL ONLY'),approved_by:account.userId,approved_at:past,expires_at:future,source_id:sourceId,schema_sha256:schema.sha256,scope:{request_id:intake.request_id,subject_id:subject,snapshot_sha256:scope.snapshot_sha256},rules:Object.fromEntries(retentionClasses.map(name=>[name,{action:name==='access'?'quarantine':name==='r2:upload_objects'?'erase':'retain',basis_reference:'SYNTHETIC TEST ONLY',deadline:name==='r2:upload_objects'?past:future}])),writer_fence:{source_id:sourceId,evidence_sha256:sha('SYNTHETIC NO EXTERNAL WRITERS'),generic_upload_catalog_only:true,unknown_in_flight:false},external_inventory:{status:'synthetic_empty',evidence_sha256:sha('SYNTHETIC COPY FIXTURE')}};
 const rawPolicy=JSON.stringify(policy);policySha=sha(rawPolicy);await f.db.prepare("INSERT INTO runtime_config(key,value_json,updated_at) VALUES('privacy:retention:approved:v1',?,?)").bind(rawPolicy,new Date().toISOString()).run();
 const planned=ok(await retention('plan',{operation_id:randomUUID(),request_id:intake.request_id,expected_review_revision:0,expected_source_id:sourceId,policy_sha256:policySha}));assert.equal(planned.tasks.length,91);
 async function claimTask(name){const task=planned.tasks.find(x=>x.class_name===name);return ok(await retention('claim',{operation_id:randomUUID(),plan_id:planned.plan_id,task_id:task.task_id,expected_task_revision:0,lease_seconds:120}));}
 const accessClaim=await claimTask('access');ok(await retention('execute',{operation_id:randomUUID(),claim_id:accessClaim.claim_id,fence:accessClaim.fence}));
 const objectClaim=await claimTask('r2:upload_objects'),failed=await retention('execute',{operation_id:randomUUID(),claim_id:objectClaim.claim_id,fence:objectClaim.fence},{'X-Test-Privacy-Delete-Fail':'true'});assert.equal(failed.status,503);
 await f.db.prepare('INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) VALUES(?,?,?,1)').bind(randomUUID(),planned.plan_id,'support_requests').run();
 // A confirmed pre-start claim remains usable before global recovery; the
 // quarantine must deny its continuation without touching immutable SMS rows.
 ok(await command('get_claimed',jobs[1].fields));
 const sql=await captureD1(f.db),counts={};for(const name of [...controls,...assistedSmsRecoveryTables])counts[name]=(await f.db.prepare('SELECT count(*) AS n FROM '+name).first()).n;
 assert.ok(Object.values(counts).every(x=>x>0));assert.equal(counts.privacy_retention_tasks,91);
 const capturedAt=new Date().toISOString(),recoveryAt=new Date(Math.ceil(Date.now()/1000)*1000).toISOString(),values={'database.sql':sql,'wrangler.json':JSON.stringify({name:'collect-platform-api',d1_databases:[{binding:'DB',database_name:'collect-platform',database_id:database}],vars:{BUILD_SOURCE_ID:sourceId,DATA_KEY_ID:dataKeys.DATA_KEY_ID,TURNSTILE_SITE_KEY:'0xSYNTHETIC_ISOLATED_TEST_WIDGET_ONLY',AUTH_IDENTITY_KEY_ID:identityBindings.AUTH_IDENTITY_KEY_ID},synthetic_fixture_provenance:{kind:'GENERATED synthetic current12 local Miniflare fixture',actual_provider_source_database_id:null,modeled_database_id:database,never_primary_capture:true}}),'worker-secrets.json':JSON.stringify({AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',DATA_ENCRYPTION_KEY:dataKeys.DATA_ENCRYPTION_KEY,TURNSTILE_SECRET:'SYNTHETIC_TURNSTILE_SECRET_NEVER_A_REAL_PROVIDER_KEY',AUTH_IDENTITY_HASH_KEY:identityBindings.AUTH_IDENTITY_HASH_KEY,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:identityBindings.AUTH_IDENTITY_PREVIOUS_KEYS_JSON})};
 for(const [name,pin]of Object.entries(quarantineSchemaProfiles.candidate12.digests)){const raw=await readFile(new URL('../../'+name,import.meta.url));assert.equal(sha(raw),pin);values[name]=raw;}
 return {f,bucket,account,operator,phone,recipient,subject,smsGroup,subjectGroup,consent,access,jobs,payments,objectClaim,policySha,planned,counts,sql,capturedAt,recoveryAt,command,retention,member,
  snapshot:subjectId=>retentionSnapshot({DB:f.db,PRIVATE_MEDIA:bucket},subjectId),
  payload:{format:'collect.platform.backup.v1',database_id:database,source_id:sourceId,captured_at:capturedAt,files:Object.fromEntries(Object.entries(values).map(([name,value])=>{const raw=Buffer.from(value);return[name,{sha256:sha(raw),bytes:raw.length,base64:raw.toString('base64')}];}))}};
}
