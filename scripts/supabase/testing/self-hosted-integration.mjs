// Owned native PG17 qualification. No hosted project, provider or existing
// application database is reset. The original16 template is never mutated.
import {readFile,writeFile,readdir,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';import {randomUUID,randomBytes,createHash} from 'node:crypto';import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {CURRENT_MIGRATION_COUNT,reviewedCurrentMigrations} from './self-hosted-current-schema.mjs';
import {canonicalProfile,validateDeploymentProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
const require=createRequire(import.meta.url),{Client}=require('pg');
const ROOT=resolve(import.meta.dirname,'../../..'),sha=value=>createHash('sha256').update(value).digest('hex');
const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const need=(ok,message)=>{if(!ok)throw Error(message);};
async function snapshot(){
 const inputs=[];
 for(const role of ['supabase/functions','supabase/migrations','deploy/collect-sms/src','deploy/self-hosted/migrations.lock.json','scripts/supabase/testing/self-hosted-integration.mjs']){
  const walk=async name=>{
   const path=join(ROOT,name);let entries;try{entries=await readdir(path,{withFileTypes:true});}catch(error){if(error.code!=='ENOTDIR')throw error;const bytes=await readFile(path);inputs.push({path:name,sha256:sha(bytes)});return;}
   for(const item of entries.sort((a,b)=>a.name.localeCompare(b.name)))if(!['node_modules','.temp','tests'].includes(item.name))await walk(name+'/'+item.name);
  };await walk(role);
 }
 inputs.sort((a,b)=>a.path.localeCompare(b.path));return {inputs,sha256:sha(JSON.stringify(inputs))};
}
export async function qualify({clusterFile,templateFile,output,runtimeDescriptor}){
 need(process.env.COLLECT_CI_SYNTHETIC==='true','Explicit synthetic qualification required');
 const cluster=JSON.parse(await readFile(clusterFile,'utf8')),template=JSON.parse(await readFile(templateFile,'utf8'));
 const adminTarget=new URL(cluster.url),ownerTarget=new URL(template.url);
 need(adminTarget.protocol==='postgres:'&&adminTarget.hostname==='127.0.0.1'&&['55439','55445','55446'].includes(adminTarget.port)&&adminTarget.username==='collect_test'&&adminTarget.pathname==='/postgres'&&adminTarget.password&&!adminTarget.search&&!adminTarget.hash,'Owned dedicated bootstrap required');
 need(ownerTarget.hostname===adminTarget.hostname&&ownerTarget.port===adminTarget.port&&ownerTarget.username==='postgres'&&/^collect_selfhost_integration_[a-f0-9]{24}_test$/.test(template.database)&&template.controller_initialized===false,'Clean original16 template required');
 const source=await snapshot(),lock=JSON.parse(await readFile(join(ROOT,'deploy/self-hosted/migrations.lock.json'),'utf8'));
 await reviewedCurrentMigrations();need(lock.migrations.length===CURRENT_MIGRATION_COUNT&&lock.original_count===16,'Exact reviewed current chain required');
 for(const item of lock.migrations)need(sha(await readFile(join(ROOT,'supabase/migrations',item.name)))===item.sha256,'Migration byte identity changed');
 const example=JSON.parse(await readFile(join(ROOT,'deploy/self-hosted/profile.example.json'),'utf8'));
 const profile=validateDeploymentProfile({...example,environment:'qualification',id:'collect-integration-qualification'}),raw=canonicalProfile(profile),profileSha=sha(raw);
 const database='collect_selfhost_integration_'+randomBytes(12).toString('hex')+'_test';
 const admin=new Client({connectionString:cluster.url,statement_timeout:60000}),cases=[];let owner,roleProbe;
 try{
  await admin.connect();const identity=(await admin.query("SELECT current_user,session_user,host(inet_server_addr()) AS host,current_setting('server_version_num')::int/10000 AS major")).rows[0];
  need(identity.current_user==='collect_test'&&identity.session_user==='collect_test'&&identity.host==='127.0.0.1'&&identity.major===17,'Actual owned PG17 required');
  await admin.query('CREATE DATABASE "'+database+'" TEMPLATE "'+template.database+'" OWNER postgres');
  ownerTarget.pathname='/'+database;owner=new Client({connectionString:ownerTarget.href,statement_timeout:60000});await owner.connect();
  // The immutable historical fixture predates these real GoTrue columns.
  // Add them only to this new synthetic database, never to a migration or host.
  await owner.query('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false');
  for(const item of lock.migrations.slice(16))await owner.query(await readFile(join(ROOT,'supabase/migrations',item.name),'utf8'));
  cases.push({name:'all_reviewed_current_migrations_install_under_normal_owner',status:'pass'});
  const ownerFlags=(await owner.query("SELECT rolcanlogin,rolsuper,rolbypassrls,rolinherit,rolcreatedb,rolreplication FROM pg_roles WHERE rolname=current_user")).rows[0];
  assert.equal(ownerFlags.rolcanlogin,true);for(const key of Object.keys(ownerFlags).filter(k=>k!=='rolcanlogin'))assert.equal(ownerFlags[key],false);
  const operation=randomUUID();
  await assert.rejects(owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[operation,raw,'0'.repeat(64)]),error=>error.code==='42501');
  const invalid=JSON.stringify({...profile,id:null});await assert.rejects(owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[randomUUID(),invalid,sha(invalid)]),error=>error.code==='22023');
  await assert.rejects(owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[randomUUID(),JSON.stringify(profile),sha(JSON.stringify(profile))]),error=>error.code==='22023');
  cases.push({name:'wrong_hash_null_profile_and_noncanonical_binding_refused',status:'pass'});
  await owner.query('BEGIN');await owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[operation,raw,profileSha]);await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[operation,source.sha256,baseline]);await owner.query('COMMIT');
  assert.equal((await owner.query('SELECT private.collect_bind_deployment($1,$2,$3) AS bound',[operation,raw,profileSha])).rows[0].bound,true);
  await assert.rejects(owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[randomUUID(),raw,profileSha]),error=>error.code==='55000');
  await assert.rejects(owner.query('UPDATE private.collect_deployment_identity SET profile_raw=profile_raw'),error=>error.code==='42501');
  cases.push({name:'same_operation_readback_and_immutable_deployment',status:'pass'});
  const probeUrl=new URL(adminTarget);probeUrl.pathname='/'+database;roleProbe=new Client({connectionString:probeUrl.href});await roleProbe.connect();
  for(const role of ['anon','authenticated','service_role']){
   await roleProbe.query('BEGIN');try{await roleProbe.query('SET LOCAL ROLE '+role);assert.equal((await roleProbe.query('SELECT current_user AS role')).rows[0].role,role);await assert.rejects(roleProbe.query('SELECT private.collect_assert_deployment($1)',[profileSha]),error=>error.code==='42501');}finally{await roleProbe.query('ROLLBACK');}
  }
  await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');assert.equal((await owner.query('SELECT private.collect_assert_deployment($1) AS ok',[profileSha])).rows[0].ok,true);await assert.rejects(owner.query('SELECT * FROM private.collect_deployment_identity'),error=>error.code==='42501');await owner.query('ROLLBACK');
  cases.push({name:'public_roles_denied_and_runtime_read_only_assertion_allowed',status:'pass'});
  await roleProbe.query('BEGIN');await roleProbe.query('SET LOCAL ROLE collect_sms_runtime');assert.equal((await roleProbe.query('SELECT collect_sms.assert_deployment_profile($1) AS ok',[profileSha])).rows[0].ok,true);await assert.rejects(roleProbe.query('SELECT * FROM private.collect_deployment_identity'),error=>error.code==='42501');await roleProbe.query('ROLLBACK');
  cases.push({name:'gateway_profile_wrapper_does_not_grant_private_access',status:'pass'});
  const status=(await owner.query('SELECT private.collect_fence_owner_status_v3() AS value')).rows[0].value;
  assert.equal(status.mode,'open');assert.equal(status.sourceSha256,source.sha256);assert.equal(status.resourceLimits.workingAdmissionLimit,100000);assert.equal(status.resourceLimits.retainedAdmissionLimit,null);
  cases.push({name:'new_capacity_contract_retains_original_controller_semantics',status:'pass'});
  // Only the disposable cluster's fixture setup creates runtime logins; these
  // remain NOSUPERUSER/NOBYPASSRLS/NOINHERIT with one SET-able parent each.
  const credentialsFile=join(resolve(clusterFile,'..'),'collect-native-runtime-credentials.private.json');let credentials;
  try{credentials=JSON.parse(await readFile(credentialsFile,'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;credentials={collect_edge:randomBytes(32).toString('hex'),collect_sms_edge:randomBytes(32).toString('hex')};
   for(const [role,password]of Object.entries(credentials)){need(/^[a-f0-9]{64}$/.test(password),'Synthetic credential shape');await admin.query("CREATE ROLE "+role+" LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '"+password+"'");await admin.query('GRANT '+(role==='collect_edge'?'collect_runtime':'collect_sms_runtime')+' TO '+role+' WITH INHERIT FALSE, SET TRUE, ADMIN FALSE');}
   await writeFile(credentialsFile,JSON.stringify(credentials)+'\n',{mode:0o600,flag:'wx'});
  }
  for(const role of Object.keys(credentials)){
   const url=new URL(ownerTarget);url.username=role;url.password=credentials[role];const runtime=new Client({connectionString:url.href});await runtime.connect();
   try{const flags=(await runtime.query('SELECT rolcanlogin,rolsuper,rolbypassrls,rolinherit,rolcreatedb,rolcreaterole,rolreplication FROM pg_roles WHERE rolname=current_user')).rows[0];assert.equal(flags.rolcanlogin,true);for(const key of Object.keys(flags).filter(k=>k!=='rolcanlogin'))assert.equal(flags[key],false);await runtime.query('BEGIN');await runtime.query('SET LOCAL ROLE '+(role==='collect_edge'?'collect_runtime':'collect_sms_runtime'));assert.equal((await runtime.query('SELECT '+(role==='collect_edge'?'private.collect_assert_deployment':'collect_sms.assert_deployment_profile')+'($1) AS ok',[profileSha])).rows[0].ok,true);await runtime.query('ROLLBACK');}finally{await runtime.end();}
  }
  cases.push({name:'actual_restricted_runtime_logins_authenticate_and_bind',status:'pass'});
  const runtimeUrl=new URL(ownerTarget);runtimeUrl.username='collect_edge';runtimeUrl.password=credentials.collect_edge;
  await writeFile(runtimeDescriptor,JSON.stringify({format:'collect.selfhost.integration-runtime.v1',database,owner_url:ownerTarget.href,runtime_url:runtimeUrl.href,profile,profile_sha256:profileSha,source_sha256:source.sha256,synthetic:true,provider_calls:0})+'\n',{flag:'wx',mode:0o600});
  need((await snapshot()).sha256===source.sha256,'Source changed during native qualification');
  const result={format:'collect.selfhost.integration-result.v1',status:'pass',server_major:17,migration_count:CURRENT_MIGRATION_COUNT,original16_byte_identical:true,synthetic_auth_interface:true,source_sha256:source.sha256,profile_sha256:profileSha,inputs:source.inputs,migrations:lock.migrations,cases,normal_owner:true,normal_runtime:true,external_provider_calls:0,synthetic:true,production_acceptance:false};
  await writeFile(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});return {status:'pass',cases:cases.length,migrations:CURRENT_MIGRATION_COUNT,external_provider_calls:0,production_acceptance:false};
 }finally{await roleProbe?.end();await owner?.end();await admin.end();}
}
if(process.argv[1]&&resolve(process.argv[1])===new URL(import.meta.url).pathname){
 const args=process.argv.slice(2);need(args.length===4,'cluster template result runtime-descriptor required');
 try{console.log(JSON.stringify(await qualify({clusterFile:resolve(args[0]),templateFile:resolve(args[1]),output:resolve(args[2]),runtimeDescriptor:resolve(args[3])})));}
 catch(error){console.error(JSON.stringify({status:'failed',code:error.code??error.name,message:error instanceof assert.AssertionError?'assertion_failed':String(error.message).slice(0,160),private_values_disclosed:false}));process.exitCode=1;}
}
