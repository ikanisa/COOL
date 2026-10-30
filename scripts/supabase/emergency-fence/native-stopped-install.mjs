// Genuine owner-session installation guards, on a second NEW retained local DB.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createHash,randomUUID} from 'node:crypto';
import {ROOT_SQL14_SHA256,MIGRATION_FOURTEEN_ROLE} from '../testing/curated-platform-fixture.mjs';
import {privateRetentionCatalogIdentity} from '../../../supabase/functions/_shared/private-retention.js';
const raw=process.env.COLLECT_STOPPED_ADMISSION_INSTALL_TEST_DATABASE_URL;
delete process.env.COLLECT_STOPPED_ADMISSION_INSTALL_TEST_DATABASE_URL;
let stage='preflight',checks=0;const check=x=>{assert(x);checks++;};
async function main(){
 const target=new URL(raw);
 check(process.env.COLLECT_CI_SYNTHETIC==='true'&&target.protocol==='postgres:'&&target.hostname==='127.0.0.1'&&target.username==='postgres'&&target.password&&target.port&&!target.search&&!target.hash&&/^\/collect_fence_stopped_install_[a-f0-9]{24}_test$/.test(target.pathname));
 const sql=await readFile(new URL('../../../'+MIGRATION_FOURTEEN_ROLE,import.meta.url),'utf8');
 check(createHash('sha256').update(sql).digest('hex')===ROOT_SQL14_SHA256);
 const require=createRequire(import.meta.url),{Client}=require(process.env.COLLECT_PG_MODULE??'pg');
 const options={connectionString:raw,ssl:false,connectionTimeoutMillis:5000,statement_timeout:10000};
 const owner=new Client(options),runtime=new Client(options),lease=new Client(options);const clients=[owner,runtime,lease];let lost=false,held=false;
 for(const c of clients)c.on('error',()=>{lost=true;});
 const source='a'.repeat(64),baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',orphan=randomUUID(),fence=randomUUID();
 const admission=async()=>(await owner.query('SELECT to_jsonb(a) value FROM private.collect_fence_admissions a WHERE admission_id=$1',[orphan])).rows[0].value;
 async function status(){check(!lost);return(await owner.query('SELECT private.collect_fence_owner_status() value')).rows[0].value;}
 async function refused(state){await assert.rejects(()=>owner.query(sql),e=>e.code===state);checks++;await owner.query('ROLLBACK');check((await owner.query("SELECT to_regclass('private.collect_fence_stopped_admissions') IS NULL missing")).rows[0].missing);}
 try{
  stage='identity';for(const c of clients)await c.connect();
  const identity=(await owner.query("SELECT current_database() db,current_user owner,session_user session,host(inet_server_addr()) host,current_setting('server_version_num') version,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user")).rows[0];
  check(identity.db===target.pathname.slice(1)&&identity.owner==='postgres'&&identity.session==='postgres'&&identity.host==='127.0.0.1'&&/^17\d{4}$/.test(identity.version)&&!identity.rolsuper&&!identity.rolbypassrls);
  check((await owner.query('SELECT count(*)::int n FROM private.collect_fence_control')).rows[0].n===0);
  check((await owner.query("SELECT to_regclass('private.collect_fence_stopped_admissions') IS NULL missing")).rows[0].missing);
  await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),source,baseline]);
  // Explicit local managed-Auth model. Use the real initial email proof API;
  // an owner SQL login alone cannot inspect personal retention inventory.
  const actor={user:randomUUID(),auth:randomUUID(),session:randomUUID(),admin:randomUUID(),public:randomUUID(),challenge:randomUUID(),cookie:createHash('sha256').update(randomUUID()).digest('hex'),origin:'https://stopped-install.example.test'};
  const at=Number((await owner.query('SELECT app.unixepoch() at')).rows[0].at),stamp=new Date().toISOString(),email='info@ikanisa.com';
  const claims={role:'authenticated',sub:actor.auth,session_id:actor.session,aal:'aal1',amr:[{method:'otp',timestamp:at}]};
  await owner.query('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
  await owner.query('INSERT INTO auth.users(id,email,email_confirmed_at)VALUES($1,$2,now())',[actor.auth,email]);
  await owner.query('INSERT INTO auth.sessions(id,user_id,aal)VALUES($1,$2,$3)',[actor.session,actor.auth,'aal1']);
  await owner.query('INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES($1,$2,to_timestamp($3))',[actor.session,'otp',at]);
  await owner.query('INSERT INTO app.users(id,email,public_id,full_name,created_at,updated_at)VALUES($1,$2,$3,$4,$5,$5)',[actor.user,email,'940001','Synthetic stopped-install Owner',stamp]);
  await owner.query('INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES($1,$2,$3)',[actor.auth,actor.user,'owned-local-managed-email-model']);
  await owner.query('INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES($1,$2,$3,$4,$4,$5)',[actor.session,actor.user,'admin',at,at+1800]);
  await owner.query("INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)VALUES($1,$2,'owner','active','!managed-supabase!','Synthetic stopped-install Owner',$3,$3)",[actor.admin,email,at]);
  await owner.query('INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES($1,$2,$3,$4)',[actor.admin,actor.user,'owned-local-managed-email-model',stamp]);
  check((await owner.query('SELECT EXISTS(SELECT 1 FROM app.admin_grants WHERE user_id=$1 AND permission=$2) allowed',[actor.user,'privacy.review'])).rows[0].allowed);
  await owner.query('INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)VALUES($1,$2,$3,1,$4,$5,$6,$7)',[actor.cookie,actor.public,actor.admin,actor.session,actor.origin,at,at+1800]);
  await owner.query("INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES($1,$2,$3,'{}')",[actor.cookie,actor.auth,actor.session]);
  await owner.query("INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)VALUES($1,$2,'email',$3,'admin',0,$4-1,$4+299,1,$4,'accepted')",[actor.challenge,createHash('sha256').update('email:'+email).digest('hex'),email,at]);
  await owner.query('BEGIN');await owner.query("SELECT set_config('request.jwt.claims',$1,true),set_config('collect.edge_verified','true',true)",[JSON.stringify(claims)]);
  await owner.query('SELECT private.admin_email_record_initial($1,$2,$3,$4,$5)',[actor.admin,actor.cookie,actor.origin,actor.public,actor.challenge]);await owner.query('COMMIT');
  await runtime.query('BEGIN');await runtime.query('SET LOCAL ROLE collect_runtime');await runtime.query("SELECT set_config('collect.edge_verified','true',true)");await runtime.query('SELECT private.collect_fence_register($1,$2,$3)',[orphan,source,'jobs']);await runtime.query('COMMIT');
  const before=await admission();check(before.state==='active'&&before.external_dispatches===0&&before.uncertain_dispatches===0);
  stage='open_refusal';await refused('55000');check((await status()).mode==='open');
  stage='uncommitted_quiesce_refusal';await owner.query('BEGIN');await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[fence,1,source]);await refused('55000');check((await status()).mode==='open');
  stage='held_real_work';await lease.query('BEGIN');held=true;await lease.query('SET LOCAL ROLE collect_runtime');await lease.query("SELECT set_config('collect.edge_verified','true',true)");await lease.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3)',[orphan,1,source]);
  await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[fence,1,source]);await refused('55P03');check((await status()).mode==='quiescing');
  await lease.query('ROLLBACK');held=false;
  stage='committed_quiesce_install';await owner.query(sql);
  const installed=(await owner.query('SELECT private.collect_fence_owner_status_v3() value')).rows[0].value;
  check(installed.contractVersion===3&&installed.mode==='quiescing'&&installed.epoch===1&&installed.rawActiveAdmissions===1&&installed.effectiveActiveAdmissions===1&&installed.stoppedLocalAdmissions===0&&installed.retainedUnquantifiedUnknownObligations===0&&installed.localLeaseDrainComplete===false&&installed.applicationFenceComplete===false);
  assert.deepEqual(await admission(),before);checks++;
  const conservative=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) value',[fence,1,source])).rows[0].value;
  check(conservative.mode==='quiescing'&&conservative.activeAdmissions===1&&conservative.applicationFenceComplete===false);
  check((await owner.query('SELECT count(*)::int n FROM private.collect_fence_stopped_admissions')).rows[0].n===0);
  stage='actual_current_retention_catalog';const reads=[];
  // Selector-only test adapter; all descriptors come from the real SQL14 DB.
  // It supports exactly the catalog's two parameterized inventory reads.
  const env={DB:{prepare(text){let values=[];const statement={bind(...args){values=args;return statement;},async all(){
   reads.push(text);let query=text;
   if(values.length){assert.equal(values.length,1);assert.match(text,/^SELECT private\.retention_(managed|member_realtime)_inventory\(\?\) AS inventory$/);query=text.replace('(?)','($1)');}
   return{results:(await owner.query(query,values)).rows};
  },async first(key){const row=(await statement.all()).results[0];return key?row?.[key]:row;}};return statement;},async batch(statements){const results=[];for(const statement of statements)results.push(await statement.all());return results;}}};
  await assert.rejects(()=>privateRetentionCatalogIdentity(env),e=>e.code==='42501'&&e.message==='session_changed');checks++;
  await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
  await owner.query("SELECT set_config('request.jwt.claims',$1,true),set_config('collect.edge_verified','true',true)",[JSON.stringify(claims)]);
  await owner.query('SELECT private.set_admin_email_context($1,$2,$3,$4)',[actor.admin,actor.cookie,actor.origin,actor.public]);
  const retention=await privateRetentionCatalogIdentity(env);await owner.query('ROLLBACK');
  // Twenty-two tables plus the existing private.object_metadata view.
  check(retention.schema_profile==='stopped_admission14'&&retention.private_schema.length===23&&retention.classes.includes('private:collect_fence_stopped_admissions'));
  check(retention.private_schema.some(row=>row.name==='collect_fence_stopped_admissions'&&row.columns.includes('original_role_oid:oid:true')));
  check(!reads.some(text=>/FROM private\.collect_fence_/.test(text)));
  check((await owner.query("SELECT has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE') allowed")).rows[0].allowed===false);
  check(!lost);
  console.log(JSON.stringify({status:'PASS',fixture:'new_unique_loopback_existing_orphan_install',checks,open_install_refused:true,uncommitted_quiesce_refused:true,actual_work_lease_blocked_install:true,committed_quiesce_install_passed:true,raw_admission_unchanged:true,proofs_created:0,provider_calls:0,hosted_acceptance:false,sb29Satisfied:false}));
 }finally{if(held)await lease.query('ROLLBACK').catch(()=>{});await owner.query('ROLLBACK').catch(()=>{});await runtime.query('ROLLBACK').catch(()=>{});await Promise.allSettled(clients.map(c=>c.end()));}
}
main().catch(error=>{console.error(JSON.stringify({format:'collect.stopped-install.native-failure.v1',stage,checks,sqlState:typeof error?.code==='string'&&/^[0-9A-Z]{5}$/.test(error.code)?error.code:null}));process.exitCode=1;});
