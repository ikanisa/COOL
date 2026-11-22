// Local-only native subset. Requires the reviewed fresh eleven-migration fixture.
// No DB creation/reset/drop/retry; failed fixtures and observations are retained.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {randomUUID,createHash} from 'node:crypto';
const FAILURE_STAGES=new Set(["preflight", "connect", "fixture_identity", "initial_owner_control", "initial_disabled_publish", "actor_member_setup", "actor_admin_setup", "actor_admin_mfa_projection", "actor_admin_email_proof", "collection_memberships", "first_activation", "no_partition_publish", "partition_setup", "opaque_payload", "topic_authorization", "client_mutation_denial", "policy_drift", "retention_fresh_mfa", "retention_recent_email", "retained_session_attribution", "active_membership_revocation", "member_inventory_denial", "ledger_unchanged", "cleanup"]);
const FAILURE_CODES=new Set(["REALTIME_NEW_LOCAL_FIXTURE_REQUIRED", "REALTIME_LOCAL_DRIVER_UNAVAILABLE", "REALTIME_LOCAL_CONNECTION_UNAVAILABLE", "REALTIME_LOCAL_CONNECTION_LOST", "REALTIME_LOCAL_CLEANUP_UNCONFIRMED", "REALTIME_ASSERTION_FAILED", "REALTIME_SUBSET_UNCONFIRMED", "SQLSTATE_23503", "SQLSTATE_23505", "SQLSTATE_23502", "SQLSTATE_23514", "SQLSTATE_42501", "SQLSTATE_55000", "SQLSTATE_57014", "SQLSTATE_55P03", "SQLSTATE_40001", "SQLSTATE_40P01", "SQLSTATE_08000", "SQLSTATE_08001", "SQLSTATE_08003", "SQLSTATE_08004", "SQLSTATE_08006", "SQLSTATE_08007", "SQLSTATE_08P01", "SQLSTATE_53300", "SQLSTATE_53400", "SQLSTATE_57P01", "SQLSTATE_57P02", "SQLSTATE_57P03", "SQLSTATE_42P01", "SQLSTATE_42703", "SQLSTATE_42883", "SQLSTATE_42601", "SQLSTATE_P0001"]);
const SQLSTATES=new Set(["23503", "23505", "23502", "23514", "42501", "55000", "57014", "55P03", "40001", "40P01", "08000", "08001", "08003", "08004", "08006", "08007", "08P01", "53300", "53400", "57P01", "57P02", "57P03", "42P01", "42703", "42883", "42601", "P0001"]);
const FIXTURE='new_unique_loopback_realtime_interface_only';
let stage='preflight',checks=0,workId,workOpen=false,connectionFailed=false;
let owner,runtime,lease,reader,url,failure=null,completed=false;
const clients=[];const source='a'.repeat(64);
function fail(code){const error=new Error('Local Realtime subset unconfirmed');error.nativeCode=code;throw error;}
function healthy(){if(connectionFailed)fail('REALTIME_LOCAL_CONNECTION_LOST');}
function failureDocument(error,at=stage){
 let code='REALTIME_SUBSET_UNCONFIRMED';
 if(FAILURE_CODES.has(error?.nativeCode))code=error.nativeCode;
 else if(SQLSTATES.has(error?.code))code='SQLSTATE_'+error.code;
 else if(error?.code==='ERR_ASSERTION')code='REALTIME_ASSERTION_FAILED';
 else if(['MODULE_NOT_FOUND','ERR_MODULE_NOT_FOUND'].includes(error?.code))code='REALTIME_LOCAL_DRIVER_UNAVAILABLE';
 else if(['ECONNREFUSED','ECONNRESET','ETIMEDOUT','EPIPE'].includes(error?.code))code='REALTIME_LOCAL_CONNECTION_UNAVAILABLE';
 return {status:'UNCONFIRMED',fixture:FIXTURE,stage:FAILURE_STAGES.has(at)?at:'preflight',code};
}
const yes=v=>{healthy();assert(v);checks++;};
async function deny(fn){healthy();await assert.rejects(fn);healthy();checks++;}
async function rt(text,values=[]){await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');try{await runtime.query('SET LOCAL ROLE collect_runtime');await runtime.query("SELECT set_config('collect.edge_verified','true',true)");const r=await runtime.query(text,values);await runtime.query('COMMIT');return r.rows[0]?.result;}catch(e){await runtime.query('ROLLBACK').catch(()=>{});throw e;}}
async function pub(){
 workId=randomUUID();const registration=await rt('SELECT private.collect_fence_register($1,$2,$3) AS result',[workId,source,'jobs']);yes(registration.state==='active');
 await lease.query('BEGIN ISOLATION LEVEL READ COMMITTED');workOpen=true;await lease.query('SET LOCAL ROLE collect_runtime');await lease.query("SELECT set_config('collect.edge_verified','true',true)");await lease.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3)',[workId,1,source]);
 let result;try{await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');await runtime.query('SET LOCAL ROLE collect_runtime');await runtime.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[workId,source]);result=(await runtime.query('SELECT private.collect_member_realtime_publish() AS result')).rows[0].result;await runtime.query('COMMIT');}
 catch(e){await runtime.query('ROLLBACK').catch(()=>{});throw e;}
 finally{await lease.query('ROLLBACK');workOpen=false;}
 await rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS result',[workId,1,source,'settled',result.attempted>0?'completed_with_unknown_obligation':'completed',result.attempted>0?1:0,result.attempted>0?1:0]);return result;
}
let seq=0;
async function actor(surface='member',accountRole='admin'){
 stage=surface==='admin'?'actor_admin_setup':'actor_member_setup';
 const a={user:randomUUID(),auth:randomUUID(),sid:randomUUID(),factor:randomUUID(),surface};const now=Math.floor(Date.now()/1000),stamp=new Date().toISOString();
 // Only the separate positive inventory fixture uses the canonical Owner.
 // Preserve the existing random-email Admin and its per-person privacy grant.
 const ownerIdentity=surface==='admin'&&accountRole==='owner';
 const managedEmail=ownerIdentity?'info@ikanisa.com':'realtime-'+a.auth+'@example.test';
 const principalEmail=ownerIdentity?managedEmail:'realtime-'+a.user+'@example.test';
 await owner.query('INSERT INTO auth.users(id,email)VALUES($1,$2)',[a.auth,managedEmail]);
 await owner.query('INSERT INTO auth.sessions(id,user_id,aal,factor_id)VALUES($1,$2,$3,$4)',[a.sid,a.auth,surface==='admin'?'aal2':'aal1',surface==='admin'?a.factor:null]);
 await owner.query('INSERT INTO app.users(id,email,public_id,full_name,created_at,updated_at)VALUES($1,$2,$3,$4,$5,$5)',[a.user,principalEmail,String(730000+ ++seq),'Synthetic Realtime',stamp]);
 await owner.query('INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES($1,$2,$3)',[a.auth,a.user,'synthetic-realtime-local-only']);
 a.claims={role:'authenticated',sub:a.auth,session_id:a.sid,aal:surface==='admin'?'aal2':'aal1',exp:now+900,amr:[{method:surface==='admin'?'totp':'otp',timestamp:now}]};
 // The app factor requires its enrollment session; the elevated session then
 // requires that projected factor. Match the real managed-MFA projection order
 // without deferring either FK or conflating managed and app principal IDs.
 await owner.query('INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at,assurance_level,mfa_at,mfa_factor_id)VALUES($1,$2,$3,$4,$4,$5,1,NULL,NULL)',[a.sid,a.user,surface,now,now+1800]);
 if(surface==='admin'){
  stage='actor_admin_mfa_projection';
  await owner.query('INSERT INTO auth.mfa_factors(id,user_id,status)VALUES($1,$2,$3)',[a.factor,a.auth,'verified']);
  await owner.query("INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,created_at,updated_at)VALUES($1,'totp',to_timestamp($2),to_timestamp($2))",[a.sid,now]);
  await owner.query(`INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)VALUES($1,$2,'Supabase Auth','{"managed_by":"supabase"}','verified',$3,$4,$3,0)`,[a.factor,a.user,now,a.sid]);
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{
   await owner.query("SELECT set_config('request.jwt.claims',$1,true)",[JSON.stringify(a.claims)]);
   const proof=(await owner.query('SELECT private.record_mfa_projection($1::uuid) AS verified_at',[a.factor])).rows[0];
   await owner.query('UPDATE app.auth_sessions SET assurance_level=2,mfa_at=$1,mfa_factor_id=$2 WHERE id=$3 AND user_id=$4 AND revoked_at IS NULL',[proof.verified_at,a.factor,a.sid,a.user]);
   await owner.query('COMMIT');
  }catch(error){await owner.query('ROLLBACK').catch(()=>{});throw error;}
  await owner.query('INSERT INTO app.admin_grants(user_id,permission,granted_at)VALUES($1,$2,$3)',[a.user,'privacy.review',stamp]);
  stage='actor_admin_email_proof';
  a.admin=randomUUID();a.cookieHash=createHash('sha256').update('synthetic-realtime-cookie:'+a.sid).digest('hex');a.publicId=randomUUID();a.origin='https://realtime-admin.example';
  const email=managedEmail,challenge=randomUUID();
  // This explicit loopback fixture models managed confirmation/OTP AMR. It
  // never calls a provider or inserts an application proof row directly.
  await owner.query('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
  await owner.query('UPDATE auth.users SET email_confirmed_at=now() WHERE id=$1',[a.auth]);
  await owner.query("INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)VALUES($1,$2,$3,'active','!managed-supabase!','Synthetic Realtime',$4,$4)",[a.admin,email,accountRole,now]);
  await owner.query('INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES($1,$2,$3,$4)',[a.admin,a.user,'synthetic-realtime-local-only',stamp]);
  await owner.query('INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)SELECT $1,$2,$3,1,id,$4,auth_at,expires_at FROM app.auth_sessions WHERE id=$5',[a.cookieHash,a.publicId,a.admin,a.origin,a.sid]);
  await owner.query("INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES($1,$2,$3,'{}')",[a.cookieHash,a.auth,a.sid]);
  await owner.query("INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES($1,'otp',to_timestamp($2))",[a.sid,now]);
  a.claims.amr.push({method:'otp',timestamp:now});
  await owner.query("INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)VALUES($1,$2,'email',$3,'admin',0,$4-1,$4+299,1,$4,'accepted')",[challenge,createHash('sha256').update('email:'+email).digest('hex'),email,now]);
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{
   await owner.query("SELECT set_config('request.jwt.claims',$1,true),set_config('collect.edge_verified','true',true)",[JSON.stringify(a.claims)]);
   await owner.query('SELECT private.admin_email_record_initial($1,$2,$3,$4,$5)',[a.admin,a.cookieHash,a.origin,a.publicId,challenge]);
   const status=(await owner.query('SELECT private.admin_email_status($1,$2,$3,$4) AS result',[a.admin,a.cookieHash,a.origin,a.publicId])).rows[0].result;
   assert(status.proof_id&&status.email_verified_at===now);
   await owner.query('COMMIT');
  }catch(error){await owner.query('ROLLBACK').catch(()=>{});throw error;}
  if(ownerIdentity){
   // All four identity namespaces must name the same exact canonical Owner;
   // native auth/app/admin IDs remain distinct and explicitly linked.
   const identity=(await owner.query(`SELECT managed.email AS managed_email,principal.email AS principal_email,
    admin_actor.email AS admin_email,admin_actor.role AS admin_role,
    challenge.identity_type,challenge.identity_value,challenge.identity_hash,challenge.surface
    FROM auth.users managed JOIN private.auth_principal_links p ON p.auth_user_id=managed.id
    JOIN app.users principal ON principal.id=p.user_id
    JOIN app.admin_principal_links l ON l.user_id=principal.id
    JOIN app.admin_users admin_actor ON admin_actor.id=l.admin_user_id
    JOIN private.supabase_otp_challenges challenge ON challenge.id=$4
    WHERE managed.id=$1 AND principal.id=$2 AND admin_actor.id=$3`,[a.auth,a.user,a.admin,challenge])).rows;
   yes(identity.length===1&&a.auth!==a.user&&a.admin!==a.user&&a.admin!==a.auth
    &&identity[0].managed_email==='info@ikanisa.com'&&identity[0].principal_email==='info@ikanisa.com'
    &&identity[0].admin_email==='info@ikanisa.com'&&identity[0].admin_role==='owner'
    &&identity[0].identity_type==='email'&&identity[0].identity_value==='info@ikanisa.com'
    &&identity[0].identity_hash===createHash('sha256').update('email:info@ikanisa.com').digest('hex')&&identity[0].surface==='admin');
  }
 }
 a.topic='collect:member:'+a.auth+':'+a.sid;return a;
}

async function audit(actorId,entityId){return(await owner.query("INSERT INTO app.audit_log(actor_user_id,action,entity_type,entity_id,details_json,created_at)VALUES($1,'synthetic.realtime','collection',$2,'{}',$3) RETURNING id",[actorId,entityId,new Date().toISOString()])).rows[0].id;}
async function canRead(a,topic=a.topic,claims=a.claims){await reader.query('BEGIN');try{await reader.query('SET LOCAL ROLE authenticated');await reader.query("SELECT set_config('request.jwt.claims',$1,true),set_config('realtime.topic',$2,true)",[JSON.stringify(claims),topic]);const r=await reader.query('SELECT count(*)::integer AS count FROM realtime.messages');await reader.query('ROLLBACK');return r.rows[0].count;}catch(e){await reader.query('ROLLBACK').catch(()=>{});throw e;}}
async function inventory(a,subject){await runtime.query('BEGIN');try{await runtime.query('SET LOCAL ROLE collect_runtime');await runtime.query("SELECT set_config('request.jwt.claims',$1,true),set_config('collect.edge_verified','true',true)",[JSON.stringify(a.claims)]);if(a.admin)await runtime.query('SELECT private.set_admin_email_context($1,$2,$3,$4)',[a.admin,a.cookieHash,a.origin,a.publicId]);const value=(await runtime.query('SELECT private.retention_member_realtime_inventory($1) AS result',[subject])).rows[0].result;await runtime.query('ROLLBACK');return value;}catch(e){await runtime.query('ROLLBACK').catch(()=>{});throw e;}}
async function appHashes(){const names=(await owner.query("SELECT tablename FROM pg_tables WHERE schemaname='app' ORDER BY tablename")).rows;const out=[];for(const{tablename}of names){assert(/^[a-z0-9_]+$/.test(tablename));const q=await owner.query(`SELECT count(*)::text AS count,encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text COLLATE "C"),'[]'::jsonb)::text,'UTF8')),'hex') AS sha FROM app."${tablename}" t`);out.push({table:tablename,...q.rows[0]});}return out;}
try{
 const raw=process.env.COLLECT_MEMBER_REALTIME_SQL_TEST_DATABASE_URL;delete process.env.COLLECT_MEMBER_REALTIME_SQL_TEST_DATABASE_URL;
 try{url=new URL(raw);}catch{fail('REALTIME_NEW_LOCAL_FIXTURE_REQUIRED');}
 if(!['postgres:','postgresql:'].includes(url.protocol)||!['127.0.0.1','[::1]'].includes(url.hostname)||!url.port||!url.username||!url.password||url.search||url.hash||!/^\/collect_member_realtime_[a-f0-9]{24}_test$/.test(url.pathname))fail('REALTIME_NEW_LOCAL_FIXTURE_REQUIRED');
 const require=createRequire(import.meta.url),{Client}=require(process.env.COLLECT_PG_MODULE??'pg');
 const client=()=>{
  const c=new Client({connectionString:raw,connectionTimeoutMillis:5000,statement_timeout:15000,query_timeout:20000});
  // Install before connect so an idle driver error never escapes as a raw stack.
  c.on('error',()=>{connectionFailed=true;});const query=c.query.bind(c);
  c.query=async(...args)=>{healthy();return query(...args);};clients.push(c);return c;
 };
 owner=client();runtime=client();lease=client();reader=client();
 stage='connect';for(const c of clients)await c.connect();
 stage='fixture_identity';
 const identity=(await owner.query("SELECT current_database() AS db,host(inet_server_addr()) AS host,current_setting('server_version_num') AS version")).rows[0];yes(identity.db===url.pathname.slice(1)&&['127.0.0.1','::1'].includes(identity.host)&&/^17/.test(identity.version));
 yes((await owner.query('SELECT count(*)::int AS n FROM app.users')).rows[0].n===0);
 stage='initial_owner_control';
 const initial=(await owner.query('SELECT private.collect_fence_owner_status() AS result')).rows[0].result;yes(initial.sourceSha256===source&&initial.mode==='open'&&initial.epoch===1&&initial.activeAdmissions===0);
 stage='initial_disabled_publish';yes((await pub()).status==='disabled');
 const first=await actor(),second=await actor(),foreign=await actor(),admin=await actor('admin'),inventoryOwner=await actor('admin','owner');yes(first.auth!==first.user);
 stage='collection_memberships';
 const group=randomUUID();await owner.query("INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)VALUES($1,$2,$3,'Synthetic realtime','ikimina',$4,$4)",[group,'rt-'+group,first.user,new Date().toISOString()]);
 for(const a of[first,second])await owner.query("INSERT INTO app.memberships(id,collection_id,user_id,role,active,joined_at)VALUES($1,$2,$3,'member',1,$4)",[randomUUID(),group,a.user,new Date().toISOString()]);
 stage='first_activation';
 await audit(first.user,group); // historical entry MUST be skipped by first activation.
 const policy=(await owner.query('SELECT private._collect_member_realtime_metadata_sha() AS sha')).rows[0].sha;
 await owner.query('SELECT private.collect_member_realtime_configure(true,$1,$2,$3)',[source,policy,'b'.repeat(64)]);
 yes((await pub()).attempted===0);
 stage='no_partition_publish';
 await audit(null,group);const before=await appHashes();const missing=await pub();yes(missing.attempted===2&&missing.delivery_confirmed===false);yes((await owner.query('SELECT count(*)::int AS n FROM realtime.messages')).rows[0].n===0);assert.deepEqual(await appHashes(),before);checks++;
 // Native-interface stand-in for provider-created partition. LOCAL DB ONLY.
 stage='partition_setup';
 await owner.query('CREATE TABLE realtime.messages_local_default PARTITION OF realtime.messages DEFAULT');
 stage='opaque_payload';
 await audit(null,group);const sent=await pub();yes(sent.status==='attempted_unconfirmed'&&sent.attempted===2&&sent.delivery_confirmed===false);
 const messages=(await owner.query('SELECT topic,event,payload,private FROM realtime.messages ORDER BY topic')).rows;yes(messages.length===2);yes(new Set(messages.map(m=>m.payload.id)).size===2);
 for(const m of messages){assert.deepEqual(Object.keys(m.payload).sort(),['id','v']);yes(m.payload.v===1&&/^[a-f0-9-]{36}$/.test(m.payload.id)&&m.event==='invalidate'&&m.private===true);yes([first.topic,second.topic].includes(m.topic)&&m.topic!==foreign.topic);}
 await owner.query("INSERT INTO realtime.messages(topic,extension,payload,event,private,id)VALUES($1,'presence','{}','presence',true,$2)",[first.topic,randomUUID()]);
 stage='topic_authorization';
 yes(await canRead(first)===1);yes(await canRead(second)===1);yes(await canRead(foreign)===0);yes(await canRead(first,second.topic)===0);yes(await canRead(admin)===0);yes(await canRead(inventoryOwner)===0);
 for(const claims of[{...first.claims,exp:0},{...first.claims,exp:String(first.claims.exp)},{...first.claims,exp:undefined},{...first.claims,session_id:second.sid},{...first.claims,sub:second.auth}])yes(await canRead(first,first.topic,claims)===0);
 stage='client_mutation_denial';
 await reader.query('BEGIN');await reader.query('SET LOCAL ROLE authenticated');await deny(()=>reader.query('SELECT private.collect_member_realtime_join($1)',[first.topic]));await reader.query('ROLLBACK');
 for(const command of["INSERT INTO realtime.messages(topic,extension,payload,event,private,id)VALUES('x','broadcast','{}','invalidate',true,gen_random_uuid())","UPDATE realtime.messages SET event='other'","DELETE FROM realtime.messages"]){await reader.query('BEGIN');await reader.query('SET LOCAL ROLE authenticated');await reader.query("SELECT set_config('request.jwt.claims',$1,true),set_config('realtime.topic',$2,true)",[JSON.stringify(first.claims),first.topic]);if(command.startsWith('INSERT')||command.startsWith('DELETE'))await deny(()=>reader.query(command));else yes((await reader.query(command)).rowCount===0);await reader.query('ROLLBACK');}
 await reader.query('BEGIN');await reader.query('SET LOCAL ROLE authenticated');await reader.query("SELECT set_config('request.jwt.claims',$1,true)",[JSON.stringify(first.claims)]);await reader.query('SELECT realtime.send($1::jsonb,$2,$3,true)',[{v:1,id:randomUUID()},'invalidate',first.topic]);await reader.query('COMMIT');yes((await owner.query('SELECT count(*)::int AS n FROM realtime.messages')).rows[0].n===3);
 // Broad-policy drift cannot OR-bypass restrictive guard; exact metadata mismatch
 // also stops the publisher. Local managed-shape policy mutation is test-only.
 stage='policy_drift';
 await owner.query('CREATE POLICY synthetic_broad_select ON realtime.messages FOR SELECT TO authenticated USING(true)');yes(await canRead(first)===0);await deny(()=>pub());await owner.query('DROP POLICY synthetic_broad_select ON realtime.messages');
 // If failure leaves a genuine active/unresolved test admission, retain it; a
 // new publication can proceed under another opaque admission without cleanup.
 stage='retention_recent_email';
 // A per-person grant cannot exceed the unchanged production role catalog.
 const privacyRoles=(await owner.query("SELECT role FROM app.admin_account_role_capabilities WHERE permission='privacy.review' ORDER BY role")).rows.map(row=>row.role);
 assert.deepEqual(privacyRoles,['owner']);checks++;
 yes((await owner.query("SELECT EXISTS(SELECT 1 FROM app.admin_grants WHERE user_id=$1 AND permission='privacy.review') AS granted",[admin.user])).rows[0].granted===true);
 healthy();await assert.rejects(()=>inventory(admin,first.user),error=>error?.code==='42501'&&error?.message==='permission_denied');healthy();checks++;
 const prior=await inventory(inventoryOwner,first.user);yes(prior.class.status==='observed'&&prior.class.count===2);yes(prior.class.rows.every(r=>Object.keys(r).sort().join(',')==='identity_sha256,key_sha256,lifecycle,row_sha256'));
 stage='retained_session_attribution';
 await owner.query('DELETE FROM auth.sessions WHERE id=$1',[first.sid]);yes(await canRead(first)===0);const retained=await inventory(inventoryOwner,first.user);assert.deepEqual(retained.class.rows,prior.class.rows);checks++;
 await audit(null,group);const afterDelete=await pub();yes(afterDelete.attempted===1);yes((await owner.query('SELECT count(*)::int AS n FROM realtime.messages WHERE topic=$1',[first.topic])).rows[0].n===2);
 stage='active_membership_revocation';
 await owner.query('UPDATE app.memberships SET active=0 WHERE collection_id=$1 AND user_id=$2',[group,second.user]);await audit(null,group);yes((await pub()).attempted===0);
 stage='member_inventory_denial';
 await deny(()=>inventory(first,first.user));
 stage='ledger_unchanged';
 const ledger=(await owner.query('SELECT(SELECT count(*)::int FROM app.ledger_entries) AS ledger,(SELECT count(*)::int FROM app.payments) AS payments')).rows[0];yes(ledger.ledger===0&&ledger.payments===0);
 healthy();completed=true;
}catch(error){failure=failureDocument(error);
}finally{
 stage='cleanup';
 const cleanupFailed=()=>{failure??=failureDocument({nativeCode:'REALTIME_LOCAL_CLEANUP_UNCONFIRMED'});};
 if(workOpen)await lease.query('ROLLBACK').catch(cleanupFailed);
 for(const c of clients)await c.query('ROLLBACK').catch(cleanupFailed);
 const closed=await Promise.allSettled(clients.map(async c=>c.end()));
 if(closed.some(value=>value.status==='rejected'))cleanupFailed();
 if(connectionFailed)failure??=failureDocument({nativeCode:'REALTIME_LOCAL_CONNECTION_LOST'});
}
// Emit one bounded document only after cleanup observation. Never print error
// messages, assertions, queries, parameters, paths, credentials or raw driver data.
if(failure){console.log(JSON.stringify(failure));process.exitCode=1;}
else if(completed){
 console.log(JSON.stringify({status:'PASS',checks,fixture:'new_unique_loopback_realtime_interface_only',subset:true,full_matrix_qualified:false,provider_calls:0,managed_project_writes:0,hosted_delivery_accepted:false,whole_system_acceptance:false,sb22Satisfied:false}));
}else{console.log(JSON.stringify(failureDocument(null)));process.exitCode=1;}
