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
import {ProtectedStorageProtocol,canonical} from '../../../supabase/functions/_shared/storage/protocol.js';
import {decrypt} from '../../../supabase/functions/_shared/domain/encryption.js';
import {digest} from '../../../supabase/functions/_shared/domain/core.js';

const root=resolve(import.meta.dirname!,'../../..'),sha=(v:Uint8Array|string)=>createHash('sha256').update(v).digest('hex');
async function inputs(){const base=await snapshotSelfHostedHistorySources(root);const path=root+'/scripts/supabase/testing/self-hosted-roster-storage-runtime.ts',raw=await readFile(path);const proposal=await readFile(Deno.env.get('COLLECT_ROSTER_PROPOSAL_SQL')!);assert.equal(sha(proposal),'3a7dea86da8d71b237f3d6e82b0d72de4315b80b6496f29a853af290f9419a41');return {base,producer_sha256:sha(raw),proposal_sha256:sha(proposal)};}
assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
const descriptor=JSON.parse(await readFile(Deno.env.get('COLLECT_ROSTER_STORAGE_FIXTURE')!,'utf8'));
const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'backend'});assert.equal(target.port,'55445');
const output=Deno.env.get('COLLECT_ROSTER_STORAGE_OUTPUT')!;assert.equal(resolve(output),output);
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
 const requestId=randomUUID(),objects=new Map<string,Uint8Array>();let writes=0;
 const transport={async uploadImmutable(key:string,bytes:Uint8Array){assert(!objects.has(key));objects.set(key,new Uint8Array(bytes));writes++;return {status:200};},
  async probe(key:string){const bytes=objects.get(key);return bytes?{headStatus:200,getStatus:200,bytes:new Uint8Array(bytes),etag:'synthetic-etag',bucketVerified:true}:{headStatus:404,getStatus:404,absent:true,bucketVerified:true};}};
 const body={contract_version:1,request_id:requestId,source_type:'text',content:'member_name,momo_name,momo_number\nAlice Example,Alice Example,0788123456'};
 const run=async(request=body)=>work(async env=>{
  Object.assign(env,{APP_ENVIRONMENT:'test',SUPABASE_URL:'https://synthetic-storage.invalid',SUPABASE_SECRET_KEY:'synthetic-private-key',DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32))});
  const bucket=new SupabaseObjectBucket(env);bucket.transport=transport as any;bucket.protocol=new ProtectedStorageProtocol({transport:transport as any,journal:bucket.journal});
  const scoped=(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true});scoped.PRIVATE_MEDIA=bucket;
  return functionRpc('prepare-roster-import',request,scoped,actor);
 });
 let outcome:any=null;try{outcome=await run();}catch(error:any){outcome={error:{code:error.code??null,message:error.message??null}};}
 const rows=await owner`SELECT id,user_id,session_id,request_id,request_sha256,state,source_object_key,source_sha256,object_sha256 FROM app.roster_imports WHERE request_id=${requestId}`;
 const metadata=rows.length?(await owner`SELECT custom_metadata FROM private.storage_objects WHERE object_key=${rows[0].source_object_key}`)[0]?.custom_metadata:null;
 const result={outcome,state:rows[0]?.state??null,metadata_keys:metadata?Object.keys(metadata).sort():[],writes,remote_objects:objects.size};
 assert.equal(result.state,'reserved');assert.equal(writes,1);assert.equal(objects.size,1);assert.equal(metadata?.source_sha256,rows[0].source_sha256);assert.equal(metadata?.object_sha256,rows[0].object_sha256);assert.equal(metadata?.sha256,undefined);
 assert.equal(result.outcome.error?.code,'42501');assert.match(result.outcome.error?.message??'',/storage_not_ready_for_application_commit/);
 cases.push('current_storage_metadata_mismatch_blocks_retained_commit');
 // Independently check actual retained ciphertext, AEAD plaintext, scope and
 // both immutable journal fingerprints. A provider double cannot make a
 // metadata-only assertion stand in for the cryptographic checks.
 const object=objects.get(rows[0].source_object_key)!;
 const reserved=(await owner`SELECT source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body FROM private.storage_payload_reservations WHERE object_key=${rows[0].source_object_key}`)[0];
 const intent=(await owner`SELECT fingerprint,sha256,size,scope,http_metadata,custom_metadata,state FROM private.storage_put_intents WHERE object_key=${rows[0].source_object_key}`)[0];
 const objectMeta=(await owner`SELECT fingerprint,sha256,size,scope,http_metadata,custom_metadata FROM private.storage_objects WHERE object_key=${rows[0].source_object_key}`)[0];
 assert.equal(reserved.sealed_body,new TextDecoder().decode(object));assert.equal(await digest(object),rows[0].object_sha256);assert.equal(intent.sha256,rows[0].object_sha256);
 assert.equal(Number(intent.size),object.length);assert.deepEqual(intent.scope,{ownerId:a.uid,entityId:rows[0].id,purpose:'roster_source'});assert.deepEqual(intent.scope,reserved.scope);
 assert.deepEqual(intent.scope,objectMeta.scope);assert.deepEqual(intent.custom_metadata,objectMeta.custom_metadata);assert.equal(intent.fingerprint,objectMeta.fingerprint);assert.equal(intent.sha256,objectMeta.sha256);
 assert.equal(reserved.aad,'roster-source:'+rows[0].id);assert.equal(reserved.key_id,'synthetic-key');assert.equal(reserved.plaintext_sha256,rows[0].source_sha256);
 const plaintext=await decrypt({DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32))},new TextDecoder().decode(object),reserved.aad);
 assert.equal(new TextDecoder().decode(plaintext),body.content);assert.equal(await digest(plaintext),rows[0].source_sha256);
 const custom={...intent.custom_metadata};delete custom.source_fingerprint;
 const boundDescriptor={scope:intent.scope,aad:reserved.aad,keyId:reserved.key_id,plaintextSha256:rows[0].source_sha256,requestDigest:rows[0].request_sha256,httpMetadata:intent.http_metadata,customMetadata:custom};
 assert.equal(await digest(canonical(boundDescriptor)),reserved.source_fingerprint);assert.equal(intent.custom_metadata.source_fingerprint,reserved.source_fingerprint);
 cases.push('plaintext_aead_ciphertext_scope_and_journal_fingerprints_verified');
 const modified=new Uint8Array(object);modified[modified.length-1]^=1;objects.set(rows[0].source_object_key,modified);
 let corrupt:any;try{await run();}catch(error:any){corrupt=error;}
 assert.equal(corrupt?.code,'storage_content_conflict');assert.equal(writes,1);objects.set(rows[0].source_object_key,object);
 let changed:any;try{await run({...body,content:body.content+'x'});}catch(error:any){changed=error;}
 assert.equal(changed?.code,'roster_request_conflict');assert.equal(writes,1);
 cases.push('changed_ciphertext_and_request_bytes_fail_without_second_upload');
 // The proposed SQL is applied only to this synthetic fixture after retaining
 // the old-source failure. It leaves the journal and original migration bytes
 // untouched and can be rejected independently of the application code.
 await owner.unsafe(new TextDecoder().decode(await readFile(Deno.env.get('COLLECT_ROSTER_PROPOSAL_SQL')!)));
 for(const [badOwner,badEntity,badHash,badPurpose] of [[randomUUID(),rows[0].id,rows[0].source_sha256,'roster_source'],[a.uid,randomUUID(),rows[0].source_sha256,'roster_source'],[a.uid,rows[0].id,'e'.repeat(64),'roster_source'],[a.uid,rows[0].id,rows[0].source_sha256,'payment_evidence']]){
  await assert.rejects(owner`SELECT private.assert_storage_ready(${rows[0].source_object_key},${badOwner},${badEntity},${badHash},${badPurpose})`,(error:any)=>error.code==='42501'&&error.message==='storage_not_ready_for_application_commit');
 }
 cases.push('proposed_gate_refuses_wrong_owner_entity_plaintext_and_purpose');
 const initial=(await run()).value;assert.equal(initial.import_id,rows[0].id);assert.equal(initial.can_submit,false);assert.equal(writes,1);
 assert.equal((await owner`SELECT state FROM app.roster_imports WHERE id=${rows[0].id}`)[0].state,'preview_ready');
 const reviewRequest={p_import_id:initial.import_id,p_parent_revision_id:initial.revision_id,p_request_id:randomUUID(),p_rows:initial.normalized_rows,p_reason:'Synthetic checked roster'};
 const rpc=async(name:string,request:any)=>work(async env=>{Object.assign(env,{DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32))});return rosterRpc(name,request,(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true}),actor);});
 const reviewed=(await rpc('admin_review_roster_import',reviewRequest)).value;assert.equal(reviewed.can_submit,true);
 const commitRequest={p_import_id:initial.import_id,p_revision_id:reviewed.revision_id,p_reviewed_rows_sha256:reviewed.reviewed_rows_sha256,p_request_id:randomUUID(),p_human_affirmed:true,p_mode:'create',p_collection_id:null,p_title:'Synthetic roster group',p_reason:'Synthetic reviewed roster'};
 const committed=(await rpc('admin_commit_roster_import',commitRequest)).value;const replay=(await rpc('admin_commit_roster_import',commitRequest)).value;
 assert.equal(committed.replayed,false);assert.equal(replay.replayed,true);assert.equal(committed.collection_id,replay.collection_id);assert.equal(writes,1);
 const final=(await rpc('admin_get_roster_import',{p_import_id:initial.import_id})).value;assert.equal(final.state,'committed');assert.equal(final.preview.can_submit,false);
 assert.equal((await owner`SELECT count(*)::int AS n FROM app.roster_members WHERE source_import_id=${initial.import_id}`)[0].n,1);
 cases.push('proposed_gate_replays_old_journal_and_completes_review_commit_once');
 assert.equal(JSON.stringify(await inputs()),JSON.stringify(source),'SOURCE_CHANGED_DURING_SQL');
 const packet={format:'collect.selfhost.roster-storage.synthetic.v1',source,source_sha256:sha(JSON.stringify(source)),cases,result,synthetic_email_proof:true,normal_runtime_role:true,provider_calls:0,production_acceptance:false};
 await writeFile(output,JSON.stringify(packet,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify({status:'PASS',cases,source_sha256:packet.source_sha256,packet_sha256:sha(await readFile(output)),provider_calls:0,production_acceptance:false}));
}finally{globalThis.fetch=originalFetch;await owner.end();await business.end({timeout:5});await control.end({timeout:5});}
