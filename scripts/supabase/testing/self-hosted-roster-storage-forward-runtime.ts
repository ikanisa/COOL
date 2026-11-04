// Local synthetic same-session roster authority probe; not a recovery receipt.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import postgres from 'npm:postgres@3.4.7';
import {snapshotSelfHostedHistorySources} from './self-hosted-member-history.mjs';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {accountDatabase} from '../../../supabase/functions/_shared/domain/admin_accounts.js';
import {loadAdminEmailAccount} from '../../../supabase/functions/_shared/domain/admin_email_auth.js';
import {bindAdminEmailActor} from '../../../supabase/functions/_shared/domain/admin_email_policy.js';
import {rosterRpc,functionRpc} from '../../../supabase/functions/_shared/domain/roster.js';
import {SupabaseObjectBucket} from '../../../supabase/functions/_shared/adapters.js';
import {ProtectedStorageProtocol} from '../../../supabase/functions/_shared/storage/protocol.js';
import {decrypt,encrypt} from '../../../supabase/functions/_shared/domain/encryption.js';
import {digest} from '../../../supabase/functions/_shared/domain/core.js';

const root=resolve(import.meta.dirname!,'../../..'),sha=(v:Uint8Array|string)=>createHash('sha256').update(v).digest('hex');
async function inputs(){const base=await snapshotSelfHostedHistorySources(root);const path=root+'/scripts/supabase/testing/self-hosted-roster-storage-forward-runtime.ts',raw=await readFile(path);return {base,producer_sha256:sha(raw)};}
assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
const descriptor=JSON.parse(await readFile(Deno.env.get('COLLECT_ROSTER_FORWARD_FIXTURE')!,'utf8'));
const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'backend'});assert.equal(target.port,'55445');
const output=Deno.env.get('COLLECT_ROSTER_FORWARD_OUTPUT')!;assert.equal(resolve(output),output);
const source=await inputs(),owner=postgres(target.href,{max:1,prepare:false,ssl:false,types:{bigint:{to:20,from:[20],serialize:String,parse:Number}}}),business=connection(target.href),control=fenceConnection(target.href);
const originalFetch=globalThis.fetch;globalThis.fetch=()=>{throw Error('EXTERNAL_FETCH_FORBIDDEN');};
const cases:string[]=[];
try{
 const schema=await installCurrentFixtureAdditions(owner);assert.equal(schema.migration_count,25);
 const sourceId=descriptor.source_sha256,at=Math.floor(Date.now()/1000)-2,stamp=new Date().toISOString();
 const a={uid:randomUUID(),auth:randomUUID(),sid:randomUUID(),aid:randomUUID(),public:randomUUID()},origin='https://roster-test.example.invalid',cookieHash=await digest('synthetic-roster-authority-cookie');
 await owner`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${a.auth},'info@ikanisa.com',now())`;
 await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES(${a.sid},${a.auth},'aal1',now()+interval '1 hour')`;
 await owner`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) VALUES(${a.sid},'otp',to_timestamp(${at}))`;
 await owner`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES(${a.uid},'info@ikanisa.com','799999','Synthetic roster reviewer','operator',${stamp},${stamp})`;
 await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${a.auth},${a.uid},'synthetic-roster-reviewer')`;
 await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(${a.sid},${a.uid},'admin',${at},${at},${at+3600})`;
 await owner`INSERT INTO app.admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(${a.aid},'info@ikanisa.com','owner','active','!managed-supabase!',${at},${at})`;
 await owner`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(${a.aid},${a.uid},'synthetic-roster',${stamp})`;
 await owner`INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at) VALUES(${a.uid},'roster.import','synthetic-roster',${stamp}) ON CONFLICT DO NOTHING`;
 await owner`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at) SELECT ${cookieHash},${a.public},id,auth_version,${a.sid},${origin},${at},${at+3600} FROM app.admin_users WHERE id=${a.aid}`;
 await owner`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES(${cookieHash},${a.auth},${a.sid},'{}')`;
 const challenge=randomUUID(),identityHash=await digest('email:info@ikanisa.com');
 await owner`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status) VALUES(${challenge},${identityHash},'email','info@ikanisa.com','admin',0,${at-1},${at+299},1,${at},'accepted')`;
 const account:any=(await owner`SELECT u.*,c.token_hash,c.public_id,c.origin,c.auth_session_id,c.issued_assurance_level,c.issued_mfa_at,c.issued_mfa_factor_id,l.user_id AS principal_id,b.auth_user_id::text AS auth_user_id FROM app.admin_users u JOIN app.admin_principal_links l ON l.admin_user_id=u.id JOIN app.admin_sessions c ON c.user_id=u.id JOIN private.bff_sessions b ON b.token_hash=c.token_hash WHERE u.id=${a.aid}`)[0];
 account.permissions=['roster.import'];
 const claims={sub:a.auth,session_id:a.sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
 async function work<T>(fn:(env:any)=>Promise<T>){const admitted=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:sourceId,kind:'http_admin'});const db=new (PostgresDatabase as any)(business,claims,admitted);const env={DB:db,COLLECT_FENCE_WORK:admitted,BUILD_SOURCE_ID:sourceId};try{const native=await db.prepare("SELECT current_user AS role,session_user AS session,current_setting('collect.edge_verified') AS verified").first();assert.equal(native.role,'collect_runtime');assert.equal(native.session,'postgres');assert.equal(native.verified,'true');return await fn(env);}finally{const closed=await admitted.finish();assert.equal(closed.applicationWorkFinished,true);assert.equal(closed.providerSettlement,false);}}
 await work(async env=>{await env.DB.prepare('SELECT private.admin_email_record_initial(?,?,?,?,?) AS result').bind(account.id,account.token_hash,account.origin,account.public_id,challenge).first();await loadAdminEmailAccount(env,account);});
 const actor=bindAdminEmailActor({surface:'admin',userId:a.uid,sessionId:a.sid,permissions:new Set(['roster.import'])},account);
 const objects=new Map<string,Uint8Array>();let puts=0;
 const transport={async uploadImmutable(key:string,bytes:Uint8Array){assert(!objects.has(key));objects.set(key,new Uint8Array(bytes));puts++;return {status:200};},
  async probe(key:string){const bytes=objects.get(key);return bytes?{headStatus:200,getStatus:200,bytes:new Uint8Array(bytes),etag:'synthetic-etag',bucketVerified:true}:{headStatus:404,getStatus:404,absent:true,bucketVerified:true};}};
 const sample=()=>({contract_version:1,request_id:randomUUID(),source_type:'text',content:'member_name,momo_name,momo_number\nAlice Example,Alice Example,0788123456'});
 let markLookup:()=>void=()=>{},continueLookup:Promise<void>=Promise.resolve();
 // Controlled predecessor reproduces the old adapter's exact metadata and
 // journal operations. It is used only to seed legacy in-flight state.
 async function call(body:any,mode='current'){return work(async env=>{
  Object.assign(env,{APP_ENVIRONMENT:'test',SUPABASE_URL:'https://synthetic-storage.invalid',SUPABASE_SECRET_KEY:'synthetic-private-key',DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32))});
  const bucket=new SupabaseObjectBucket(env);bucket.transport=transport as any;bucket.protocol=new ProtectedStorageProtocol({transport:transport as any,journal:bucket.journal});
  if(mode==='race-current'){
   const lookup=bucket.journal.getPayloadBinding.bind(bucket.journal);
   bucket.journal.getPayloadBinding=async(key:string)=>{const prior=await lookup(key);assert.equal(prior,null);markLookup();await continueLookup;return prior;};
  }
  if(mode!=='current'&&mode!=='race-current')bucket.put=async(key:string,value:string,options:any)=>{
   const prior=await bucket.journal.getPayloadBinding(key),custom={...options.customMetadata};
   if(mode==='new-reservation-only')custom.sha256=custom.source_sha256;
   const plain=custom.sha256??custom.source_sha256,descriptor={scope:options.scope,aad:options.aad,keyId:prior?.keyId??env.DATA_KEY_ID,plaintextSha256:plain,requestDigest:options.sourceDigest,httpMetadata:options.httpMetadata??{},customMetadata:custom};
   const reservation=await bucket.journal.reservePayload(key,descriptor,value);
   if(mode.endsWith('reservation-only'))throw Error('synthetic_interruption_after_reservation');
   if(reservation.sealedBody===null){const intent=await bucket.journal.getPutByKey(key);return bucket.protocol.confirmCommitted(intent);}
   const plaintext=await decrypt(env,reservation.sealedBody,options.aad);assert.equal(await digest(plaintext),plain);
   return bucket.protocol.put(key,reservation.sealedBody,{scope:options.scope,httpMetadata:options.httpMetadata??{},customMetadata:{...custom,source_fingerprint:reservation.sourceFingerprint}});
  };
  const scoped=(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true});scoped.PRIVATE_MEDIA=bucket;
  return functionRpc('prepare-roster-import',body,scoped,actor);
 });}
 const first=sample(),initial=(await call(first)).value;
 assert.equal(initial.can_submit,false);assert.equal(puts,1);
 const firstRows=await owner`SELECT r.id,r.state,o.custom_metadata FROM app.roster_imports r JOIN private.storage_objects o ON o.object_key=r.source_object_key WHERE r.request_id=${first.request_id}`;
 assert.equal(firstRows[0].state,'preview_ready');assert.equal(firstRows[0].custom_metadata.sha256,firstRows[0].custom_metadata.source_sha256);
 const reviewRequest={p_import_id:initial.import_id,p_parent_revision_id:initial.revision_id,p_request_id:randomUUID(),p_rows:initial.normalized_rows,p_reason:'Synthetic checked roster'};
 const rpc=async(name:string,request:any)=>work(async env=>{Object.assign(env,{DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32))});return rosterRpc(name,request,(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true}),actor);});
 const reviewed=(await rpc('admin_review_roster_import',reviewRequest)).value;
 const commitRequest={p_import_id:initial.import_id,p_revision_id:reviewed.revision_id,p_reviewed_rows_sha256:reviewed.reviewed_rows_sha256,p_request_id:randomUUID(),p_human_affirmed:true,p_mode:'create',p_collection_id:null,p_title:'Synthetic roster group',p_reason:'Synthetic reviewed roster'};
 const committed=(await rpc('admin_commit_roster_import',commitRequest)).value,replay=(await rpc('admin_commit_roster_import',commitRequest)).value;
 assert.equal(committed.replayed,false);assert.equal(replay.replayed,true);assert.equal(committed.collection_id,replay.collection_id);
 assert.equal((await rpc('admin_get_roster_import',{p_import_id:initial.import_id})).value.preview.can_submit,false);assert.equal(puts,1);
 cases.push('new_digest_upload_review_commit_and_idempotent_replay');
 const interrupted=sample();await assert.rejects(()=>call(interrupted,'new-reservation-only'),/synthetic_interruption_after_reservation/);
 const pending=(await owner`SELECT r.source_object_key,p.source_fingerprint FROM app.roster_imports r JOIN private.storage_payload_reservations p ON p.object_key=r.source_object_key WHERE r.request_id=${interrupted.request_id}`)[0];
 assert.equal((await owner`SELECT count(*)::int AS n FROM private.storage_put_intents WHERE object_key=${pending.source_object_key}`)[0].n,0);
 const resumed=(await call(interrupted)).value;assert.equal(resumed.can_submit,false);assert.equal(puts,2);
 assert.equal((await owner`SELECT source_fingerprint FROM private.storage_payload_reservations WHERE object_key=${pending.source_object_key}`)[0].source_fingerprint,pending.source_fingerprint);
 cases.push('new_reservation_without_intent_retries_same_descriptor');
 const old=sample();let failure:any;try{await call(old,'legacy');}catch(error:any){failure=error;}
 assert.equal(failure?.code,'42501');assert.equal(failure?.message,'storage_not_ready_for_application_commit');assert.equal(puts,3);
 const oldRow=(await owner`SELECT r.source_object_key,r.state,o.custom_metadata FROM app.roster_imports r JOIN private.storage_objects o ON o.object_key=r.source_object_key WHERE r.request_id=${old.request_id}`)[0];
 assert.equal(oldRow.state,'reserved');assert.equal(Object.hasOwn(oldRow.custom_metadata,'sha256'),false);
 const snap=async()=>({reservation:(await owner`SELECT to_jsonb(p) AS v FROM private.storage_payload_reservations p WHERE object_key=${oldRow.source_object_key}`)[0].v,
  intent:(await owner`SELECT to_jsonb(i) AS v FROM private.storage_put_intents i WHERE object_key=${oldRow.source_object_key}`)[0].v,
  object:(await owner`SELECT to_jsonb(o) AS v FROM private.storage_objects o WHERE object_key=${oldRow.source_object_key}`)[0].v,
  import:(await owner`SELECT to_jsonb(r) AS v FROM app.roster_imports r WHERE request_id=${old.request_id}`)[0].v});
 const oldBefore=await snap(),oldBytes=new Uint8Array(objects.get(oldRow.source_object_key)!);failure=null;try{await call(old);}catch(error:any){failure=error;}
 assert.equal(failure?.code,'42501');assert.equal(failure?.message,'storage_not_ready_for_application_commit');assert.equal(puts,3);
 assert.deepEqual(await snap(),oldBefore);assert.deepEqual(objects.get(oldRow.source_object_key),oldBytes);
 cases.push('legacy_journal_retry_unchanged_and_fail_closed');
 const oldPending=sample();await assert.rejects(()=>call(oldPending,'legacy-reservation-only'),/synthetic_interruption_after_reservation/);
 const legacyPending=(await owner`SELECT r.source_object_key,p.source_fingerprint FROM app.roster_imports r JOIN private.storage_payload_reservations p ON p.object_key=r.source_object_key WHERE r.request_id=${oldPending.request_id}`)[0];
 assert.equal((await owner`SELECT count(*)::int AS n FROM private.storage_put_intents WHERE object_key=${legacyPending.source_object_key}`)[0].n,0);
 failure=null;try{await call(oldPending);}catch(error:any){failure=error;}
 assert.equal(failure?.code,'42501');assert.equal(failure?.message,'storage_not_ready_for_application_commit');assert.equal(puts,4);
 const legacyMeta=(await owner`SELECT custom_metadata FROM private.storage_objects WHERE object_key=${legacyPending.source_object_key}`)[0].custom_metadata;
 assert.equal(Object.hasOwn(legacyMeta,'sha256'),false);assert.equal((await owner`SELECT source_fingerprint FROM private.storage_payload_reservations WHERE object_key=${legacyPending.source_object_key}`)[0].source_fingerprint,legacyPending.source_fingerprint);
 cases.push('legacy_reservation_without_intent_keeps_original_descriptor');
 // Pause the new adapter after its real no-reservation lookup, then let the
 // predecessor reserve and store first. No time-based scheduling assumption.
 const raced=sample();let release!:()=>void;
 const observed=new Promise<void>(resolve=>{markLookup=resolve;});continueLookup=new Promise<void>(resolve=>{release=resolve;});
 const contender=call(raced,'race-current').then(value=>({value,error:null}),(error:any)=>({value:null,error}));
 await observed;let oldRaceFailure:any;try{await call(raced,'legacy');}catch(error:any){oldRaceFailure=error;}
 assert.equal(oldRaceFailure?.code,'42501');assert.equal(puts,5);
 const raceRow=(await owner`SELECT r.source_object_key,r.state,p.source_fingerprint FROM app.roster_imports r JOIN private.storage_payload_reservations p ON p.object_key=r.source_object_key WHERE r.request_id=${raced.request_id}`)[0];
 const raceSnap=async()=>({reservation:(await owner`SELECT to_jsonb(p) AS v FROM private.storage_payload_reservations p WHERE object_key=${raceRow.source_object_key}`)[0].v,
  intent:(await owner`SELECT to_jsonb(i) AS v FROM private.storage_put_intents i WHERE object_key=${raceRow.source_object_key}`)[0].v,
  object:(await owner`SELECT to_jsonb(o) AS v FROM private.storage_objects o WHERE object_key=${raceRow.source_object_key}`)[0].v,
  import:(await owner`SELECT to_jsonb(r) AS v FROM app.roster_imports r WHERE request_id=${raced.request_id}`)[0].v});
 const raceBefore=await raceSnap(),raceBytes=new Uint8Array(objects.get(raceRow.source_object_key)!);release();
 const racedResult=await contender;assert.equal(racedResult.error?.code,'storage_source_conflict');assert.equal(puts,5);
 assert.deepEqual(await raceSnap(),raceBefore);assert.deepEqual(objects.get(raceRow.source_object_key),raceBytes);
 let retryError:any;try{await call(raced);}catch(error:any){retryError=error;}
 assert.equal(retryError?.code,'42501');assert.equal(retryError?.message,'storage_not_ready_for_application_commit');
 assert.deepEqual(await raceSnap(),raceBefore);assert.equal(puts,5);
 cases.push('mixed_version_race_conflicts_then_preserves_old_retry');
 // Existing non-roster metadata and key-rotation replay retain the original
 // descriptor and ciphertext rather than selecting the new active key.
 const otherKey='synthetic/non-roster/'+randomUUID(),otherId=randomUUID(),plainText='synthetic-payment-evidence';
 const plainBytes=new TextEncoder().encode(plainText),plainHash=await digest(plainBytes),aad='payment-evidence:'+otherId,requestDigest=await digest('synthetic-request');
 const options={scope:{ownerId:a.uid,entityId:otherId,purpose:'payment_evidence'},aad,sourceDigest:requestDigest,httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:plainHash,key_id:'synthetic-key'}};
 const otherCall=async(rotated:boolean)=>work(async env=>{
  Object.assign(env,{APP_ENVIRONMENT:'test',SUPABASE_URL:'https://synthetic-storage.invalid',SUPABASE_SECRET_KEY:'synthetic-private-key',DATA_KEY_ID:rotated?'next-key':'synthetic-key',DATA_ENCRYPTION_KEY:btoa((rotated?'m':'n').repeat(32)),...(rotated?{DATA_DECRYPTION_KEYS_JSON:JSON.stringify({'synthetic-key':btoa('n'.repeat(32))})}:{})});
  const bucket=new SupabaseObjectBucket(env);bucket.transport=transport as any;bucket.protocol=new ProtectedStorageProtocol({transport:transport as any,journal:bucket.journal});
  const cipher=await encrypt(env,plainBytes,aad);return bucket.put(otherKey,cipher,{...options,customMetadata:{...options.customMetadata,key_id:env.DATA_KEY_ID}});
 });
 const oldOther=await otherCall(false);assert.equal(oldOther.stored,true);assert.equal(puts,6);
 const otherSnap=async()=>({reservation:(await owner`SELECT to_jsonb(p) AS v FROM private.storage_payload_reservations p WHERE object_key=${otherKey}`)[0].v,
  intent:(await owner`SELECT to_jsonb(i) AS v FROM private.storage_put_intents i WHERE object_key=${otherKey}`)[0].v,
  object:(await owner`SELECT to_jsonb(o) AS v FROM private.storage_objects o WHERE object_key=${otherKey}`)[0].v});
 const otherBefore=await otherSnap(),otherBytes=new Uint8Array(objects.get(otherKey)!);const otherReplay=await otherCall(true);
 assert.equal(otherReplay.operationId,oldOther.operationId);assert.equal(puts,6);assert.deepEqual(await otherSnap(),otherBefore);assert.deepEqual(objects.get(otherKey),otherBytes);
 cases.push('non_roster_key_rotation_replays_original_ciphertext_and_identity');
 assert.equal(JSON.stringify(await inputs()),JSON.stringify(source),'SOURCE_CHANGED_DURING_SQL');
 const packet={format:'collect.selfhost.roster-storage-forward.synthetic.v1',source,source_sha256:sha(JSON.stringify(source)),cases,synthetic_email_proof:true,normal_runtime_role:true,provider_calls:0,production_acceptance:false};
 await writeFile(output,JSON.stringify(packet,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify({status:'PASS',cases,source_sha256:packet.source_sha256,packet_sha256:sha(await readFile(output)),provider_calls:0,production_acceptance:false}));
}finally{globalThis.fetch=originalFetch;await owner.end();await business.end({timeout:5});await control.end({timeout:5});}
