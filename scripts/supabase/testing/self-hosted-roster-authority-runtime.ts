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
import {rosterRpc} from '../../../supabase/functions/_shared/domain/roster.js';
import {digest} from '../../../supabase/functions/_shared/domain/core.js';

const root=resolve(import.meta.dirname!,'../../..'),sha=(v:Uint8Array|string)=>createHash('sha256').update(v).digest('hex');
async function inputs(){const base=await snapshotSelfHostedHistorySources(root);const path=root+'/scripts/supabase/testing/self-hosted-roster-authority-runtime.ts',raw=await readFile(path);return {base,producer_sha256:sha(raw)};}
assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
const descriptor=JSON.parse(await readFile(Deno.env.get('COLLECT_ROSTER_AUTHORITY_FIXTURE')!,'utf8'));
const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'backend'});assert.equal(target.port,'55445');
const output=Deno.env.get('COLLECT_ROSTER_AUTHORITY_OUTPUT')!;assert.equal(resolve(output),output);
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
 const importId=randomUUID(),requestId=randomUUID();
 await work(async env=>{
  const scoped=(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true});
  await scoped.DB.batch([scoped.DB.prepare('INSERT INTO roster_imports(id,user_id,session_id,request_id,request_sha256,source_sha256,object_sha256,source_object_key,source_size,source_kind,source_receipt_json,source_ciphertext,state,created_seconds,expires_seconds) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)').bind(importId,a.uid,a.sid,requestId,'a'.repeat(64),'b'.repeat(64),'c'.repeat(64),'synthetic/roster/'+importId,5,'text','{}','{}','reserved',at,at+3600)]);
 });cases.push('fresh_email_authorized_reservation_commits_under_normal_runtime');
 const status=await work(async env=>rosterRpc('admin_get_roster_import',{p_import_id:importId},(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true}),actor));
 assert.equal(status.handled,true);assert.equal(status.value.state,'reserved');assert.equal(status.value.import_id,importId);cases.push('same_session_gets_exact_reserved_status');
 const before=(await owner`SELECT count(*)::int AS n FROM app.roster_commit_guards`)[0].n;assert.equal(before,0);const reservationBefore=(await owner`SELECT to_jsonb(r) AS value FROM app.roster_imports r WHERE id=${importId}`)[0].value;
 await owner`UPDATE app.auth_sessions SET revoked_at=${at+1},revocation_reason='synthetic-revocation' WHERE id=${a.sid}`;
 let rejected=false;
 try{await work(async env=>rosterRpc('admin_get_roster_import',{p_import_id:importId},(accountDatabase as any)(env,account,'roster.import',{mfa:true,fresh:true}),actor));}catch(error:any){assert.equal(error.status,403);assert.ok(['admin_access_changed','recent_email_sign_in_required','roster_import_unavailable'].includes(error.code));rejected=true;}
 assert.equal(rejected,true);assert.equal((await owner`SELECT count(*)::int AS n FROM app.roster_commit_guards`)[0].n,0);assert.deepEqual((await owner`SELECT to_jsonb(r) AS value FROM app.roster_imports r WHERE id=${importId}`)[0].value,reservationBefore);cases.push('revoked_session_denied_without_mutating_reservation_or_guard');
 assert.equal(JSON.stringify(await inputs()),JSON.stringify(source),'SOURCE_CHANGED_DURING_SQL');
 const packet={format:'collect.selfhost.roster-authority.synthetic.v1',source,source_sha256:sha(JSON.stringify(source)),cases,synthetic_email_proof:true,normal_runtime_role:true,provider_calls:0,production_acceptance:false};
 await writeFile(output,JSON.stringify(packet,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify({status:'PASS',cases,source_sha256:packet.source_sha256,packet_sha256:sha(await readFile(output)),provider_calls:0,production_acceptance:false}));
}finally{globalThis.fetch=originalFetch;await owner.end();await business.end({timeout:5});await control.end({timeout:5});}
