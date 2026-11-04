// Dedicated current-chain native qualification only. The caller provisions a
// private original16 descriptor on its synthetic loopback cluster. Neither the
// Auth /user fixture nor the MoMo AI fixture contacts a real provider.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import postgres from 'npm:postgres@3.4.7';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {projectSession} from '../../../supabase/functions/_shared/domain/auth.js';
import {verifyMomoOutboxOnPostgres} from '../../../supabase/functions/_shared/tests/momo-outbox-fencing-postgres.mjs';
import {verifyMomoAdminOnCurrentPostgres} from '../../../supabase/functions/_shared/tests/momo-admin-current-chain.mjs';

assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');assert.equal(Deno.args.length,0);
const descriptorPath=Deno.env.get('COLLECT_MOMO_FIXTURE_DESCRIPTOR');assert(descriptorPath);
const descriptor=JSON.parse(await readFile(descriptorPath,'utf8'));
const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'backend'});
const owner=postgres(target.href,{max:1,prepare:false,ssl:false,onnotice:()=>{},types:{bigint:{to:20,from:[20],serialize:String,parse:Number}}});
const business=connection(target.href),control=fenceConnection(target.href),originalFetch=globalThis.fetch;
let externalCalls=0,admission:any=null,receipt:any=null;
globalThis.fetch=()=>{externalCalls++;return Promise.reject(Error('Current-chain MoMo fixture forbids external network calls'));};
try{
 const currentSchema=await installCurrentFixtureAdditions(owner);
 const [identity]=await owner`SELECT current_user AS owner,session_user AS session,current_database() AS database,host(inet_server_addr()) AS host,
  inet_server_port() AS port,current_setting('server_version_num')::int AS version,(SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) AS privileged`;
 assert.equal(identity.owner,'postgres');assert.equal(identity.session,'postgres');assert.equal(identity.database,target.pathname.slice(1));
 assert.equal(identity.host,'127.0.0.1');assert.equal(identity.port,Number(target.port));assert.equal(identity.version,170010);assert.equal(identity.privileged,false);
 const member=crypto.randomUUID(),auth=crypto.randomUUID(),sid=crypto.randomUUID(),stamp=new Date().toISOString(),at=Math.floor(Date.now()/1000)-2;
 await owner`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${auth},'outbox-synthetic@example.invalid',now())`;
 await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES(${sid},${auth},'aal1',now()+interval '1 hour')`;
 await owner`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES(${member},'outbox-synthetic@example.invalid','799998','Synthetic outbox member','app',${stamp},${stamp})`;
 await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${auth},${member},'synthetic-outbox-no-provider')`;
 const claims={sub:auth,session_id:sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
 const projection=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:descriptor.source_sha256,kind:'http_collect'});
 try{
  const env:any={DB:new (PostgresDatabase as any)(business,claims,projection),AUTH_MEMBER_REGISTRATION_ENABLED:'false'};
  const actor=await projectSession(env,{claims,user:{id:auth,email:'outbox-synthetic@example.invalid',email_confirmed_at:stamp,app_metadata:{provider:'email'}}});
  assert.equal(actor.userId,member);assert.equal(actor.sessionId,sid);
 }finally{const closed=await projection.finish();assert.equal(closed.applicationWorkFinished,true);assert.equal(closed.providerSettlement,false);}
 admission=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:descriptor.source_sha256,kind:'jobs'});
 const db=new (PostgresDatabase as any)(business,{},admission);
 const runtime=await db.prepare("SELECT current_user AS role,session_user AS session,current_setting('collect.edge_verified') AS verified").first();
 assert.equal(runtime.role,'collect_runtime');assert.equal(runtime.session,'postgres');assert.equal(runtime.verified,'true');
 const outbox=await verifyMomoOutboxOnPostgres({sql:owner,db,member,sid});
 const closed=await admission.finish();admission=null;
 assert.equal(closed.applicationWorkFinished,true);assert.equal(closed.providerSettlement,false);
 const admin=await verifyMomoAdminOnCurrentPostgres({sql:owner,business,control,sourceSha256:descriptor.source_sha256,member,sid});
 assert.equal(externalCalls,0);assert.equal(outbox.actual_provider_calls,0);assert.equal(admin.actual_provider_calls,0);
 assert.equal(admin.unexpected_network_calls,0);assert.equal(outbox.production_acceptance,false);assert.equal(admin.production_acceptance,false);
 receipt={format:'collect.selfhost.momo.native.v1',status:'PASS',current_schema:currentSchema,normal_owner:true,normal_runtime:true,
  outbox_checks:outbox.checks,admin_checks:admin.checks,synthetic_provider_calls:outbox.synthetic_provider_calls,
  synthetic_auth_get_user_calls:admin.synthetic_auth_get_user_calls,admin_completed_admissions:admin.completed_admissions,provider_calls:0,external_network_calls:externalCalls,
  hosted_acceptance:false,production_acceptance:false};
}finally{
 if(admission)await admission.finish().catch(()=>{});
 globalThis.fetch=originalFetch;
 await Promise.all([business.end(),control.end(),owner.end()]);
}
console.log(JSON.stringify(receipt));
