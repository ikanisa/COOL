import assert from 'node:assert/strict';
import {loadReviewedPlatformFixture,ROOT_SQL15_SHA256} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {connection,PostgresDatabase,initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {projectSession} from './helpers/module-domain-auth.js';
import {clientDiagnosticsRoute,diagnosticFingerprint,cleanupClientDiagnostics,clientDiagnosticGroups} from '../domain/client_diagnostics.js';
import {diagnosticRetentionColumns} from '../domain/privacy_retention_catalog.js';
import {oversightHealthSql} from '../domain/admin_oversight.js';

// Native PostgreSQL component qualification: exact SQL13 predecessors + the
// additive SQL15 diagnostics table. SQL14's separate owner/cutover lifecycle
// is not substituted, bypassed or claimed as qualified by this component test.
const database=Deno.env.get('COLLECT_DIAGNOSTICS_TEST_DATABASE_URL');
const unix=()=>Math.floor(Date.now()/1000);

fencedTest({name:'safe diagnostics: native schema, ACL, mutation fencing, replay, quotas and expiry',sanitizeOps:false,sanitizeResources:false,fn:async t=>{
 assert(database,'COLLECT_DIAGNOSTICS_TEST_DATABASE_URL is mandatory; diagnostics acceptance cannot silently skip');
 const target=new URL(database);
 assert.equal(target.protocol,'postgres:');assert.equal(target.hostname,'127.0.0.1');assert.equal(target.username,'collect_test');
 assert.equal(target.pathname,'/collect_diagnostics_test');assert.equal(target.search,'');assert.equal(target.hash,'');
 assert(target.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(target.port));
 const sql=connection(database),originalFetch=globalThis.fetch;
 let providerCalls=0;
 globalThis.fetch=()=>{providerCalls++;return Promise.reject(Error('No provider traffic is allowed in diagnostics qualification'));};
 try{
  const fixture=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url),{includeMfaRetirementMigration:true});
  assert(fixture.clientDiagnostics);assert.equal(fixture.clientDiagnostics.sha256,ROOT_SQL15_SHA256);
  const setup=await sql.reserve();
  try{
   await setup.unsafe('DROP SCHEMA IF EXISTS api,app,private,auth,realtime CASCADE');
   await fixture.apply(text=>setup.unsafe(text),{includeAuth:true});
   await setup.unsafe(fixture.clientDiagnostics.sql);
   await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
  }finally{setup.release();}
  await initializeSqlFixture(sql);
  const auth=crypto.randomUUID(),session=crypto.randomUUID(),principal=crypto.randomUUID(),stamp=new Date().toISOString(),at=unix()-2;
  await sql`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${auth},'diagnostics@example.invalid',now())`;
  await sql`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${session},${auth},'aal1',now()+interval '1 hour')`;
  await sql`INSERT INTO app.users(id,email,public_id,full_name,created_at,updated_at)VALUES(${principal},'diagnostics@example.invalid','920001','Synthetic diagnostics fixture',${stamp},${stamp})`;
  await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${auth},${principal},'synthetic-diagnostics-fixture')`;
  const claims={sub:auth,session_id:session,role:'authenticated',aal:'aal1',iat:at,exp:unix()+3600,amr:[{method:'otp',timestamp:at}]};
  const db=new PostgresDatabase(sql,claims),env:any={DB:db};
  const actor=await projectSession(env,{claims,user:{id:auth,email:'diagnostics@example.invalid',email_confirmed_at:stamp,app_metadata:{provider:'email'}}});
  const report=async(changes:Record<string,unknown>={})=>{
   const value:any={collect_diagnostic:1,code:'frameworkFailure',severity:'error',surface:'member',environment:'production',build_version:'1.2.4+23',source_revision:'a'.repeat(40),report_id:crypto.randomUUID(),occurrences:1,attempt:1,elapsed_ms:1000,...changes};
   value.fingerprint=await diagnosticFingerprint(value);return value;
  };
  const post=(value:unknown)=>new Request('https://synthetic.invalid/v1/diagnostics',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({contract_version:1,reports:[value]})});
  const count=async()=>Number((await sql`SELECT count(*) AS n FROM app.client_diagnostic_reports`)[0].n);

  await t.step('only the runtime role has the exact necessary table privileges, with forced RLS and ALWAYS fencing',async()=>{
   const row=(await sql`SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='app.client_diagnostic_reports'::regclass`)[0];
   assert.equal(row.relrowsecurity,true);assert.equal(row.relforcerowsecurity,true);
   for(const role of ['anon','authenticated'])for(const privilege of ['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']){
    assert.equal((await sql`SELECT has_table_privilege(${role},'app.client_diagnostic_reports',${privilege}) AS allowed`)[0].allowed,false);
   }
   for(const privilege of ['SELECT','INSERT','DELETE'])assert.equal((await sql`SELECT has_table_privilege('collect_runtime','app.client_diagnostic_reports',${privilege}) AS allowed`)[0].allowed,true);
   for(const privilege of ['UPDATE','TRUNCATE'])assert.equal((await sql`SELECT has_table_privilege('collect_runtime','app.client_diagnostic_reports',${privilege}) AS allowed`)[0].allowed,false);
   const trigger=(await sql`SELECT tgenabled,tgtype FROM pg_trigger WHERE tgrelid='app.client_diagnostic_reports'::regclass AND tgname='collect_fence_statement_v1'`)[0];
   assert.equal(trigger.tgenabled,'A');assert.equal(trigger.tgtype,62);
   await assert.rejects(sql.begin(async(tx:any)=>{await tx`SET LOCAL ROLE collect_runtime`;await tx`DELETE FROM app.client_diagnostic_reports WHERE false`;}),/collect_fence_unavailable/);
  });

  let first:any;
  await t.step('actual authenticated handler commits an identity-free report and exact retries once',async()=>{
   first=await report({occurrences:3});
   assert.equal((await clientDiagnosticsRoute(post(first),env,actor))?.status,202);
   assert.equal((await clientDiagnosticsRoute(post(first),env,actor))?.status,202);
   assert.equal(await count(),1);
   const stored=JSON.stringify(await sql`SELECT * FROM app.client_diagnostic_reports`);
   for(const secret of [principal,session,auth,'diagnostics@example.invalid','Synthetic diagnostics fixture'])assert(!stored.includes(secret));
   const grouped=await clientDiagnosticGroups(env);assert.equal(Number(grouped[0].occurrences),3);assert.equal(Number(grouped[0].reports),1);
   await assert.rejects(clientDiagnosticsRoute(post({...first,occurrences:4}),env,actor),(error:any)=>error.code==='diagnostic_capacity_limited');
   assert.equal(await count(),1);
  });

  await t.step('the real quota transaction refuses the seventeenth request without a partial report',async()=>{
   for(let attempt=0;attempt<14;attempt++)assert.equal((await clientDiagnosticsRoute(post(await report()),env,actor))?.status,202);
   assert.equal(await count(),15);
   await assert.rejects(clientDiagnosticsRoute(post(await report()),env,actor),(error:any)=>error.code==='diagnostic_capacity_limited');
   assert.equal(await count(),15);
   const quota=await sql`SELECT count FROM app.admin_rate_limits WHERE key_hash LIKE 'client_diag:v1:user:%'`;
   assert.equal(quota.length,1);assert.equal(Number(quota[0].count),16);
  });

  await t.step('revoking the real managed session rejects a previously cached actor before report write',async()=>{
   await sql`UPDATE app.auth_sessions SET revoked_at=${unix()},revocation_reason='synthetic_test' WHERE id=${session}`;
   await assert.rejects(clientDiagnosticsRoute(post(await report()),env,actor),(error:any)=>error.status===403);
   assert.equal(await count(),15);
  });

  await t.step('bounded cleanup removes only expired diagnostics and quota rows',async()=>{
   const oldHour=(Math.floor(unix()/3600)-48)*3600;
   await sql`UPDATE app.client_diagnostic_reports SET received_hour=${oldHour},expires_at=${oldHour+86400} WHERE report_id=${first.report_id}`;
   await sql`INSERT INTO app.admin_rate_limits(key_hash,bucket,count,expires_at)VALUES('unrelated_auth_quota',0,1,1)`;
   const result=await cleanupClientDiagnostics(env,{limit:1});assert.equal(result.status,'complete');assert.equal(result.removed,1);assert.equal(await count(),14);
   assert.equal(Number((await sql`SELECT count(*) AS n FROM app.admin_rate_limits WHERE key_hash='unrelated_auth_quota'`)[0].n),1);
  });

  await t.step('the native diagnostics schema exactly matches the additive retention column inventory',async()=>{
   const columns=await sql`SELECT attname FROM pg_attribute WHERE attrelid='app.client_diagnostic_reports'::regclass AND attnum>0 AND NOT attisdropped ORDER BY attnum`;
   assert.deepEqual(columns.map((row:{attname:string})=>row.attname),diagnosticRetentionColumns.client_diagnostic_reports);
  });

  await t.step('operational queue-health queries execute against the real current tables',async()=>{
   const health=await db.batch(oversightHealthSql.slice(0,6).map(query=>db.prepare(query)));
   assert.equal(health.length,6);
   for(const value of health)assert.equal(value.results.length,1);
   assert.equal(health[1].results[0].pending,0);assert.equal(health[1].results[0].expired_lease,0);
   assert.equal(health[2].results[0].uncertain,0);assert.equal(health[3].results[0].pending,0);
  });
  assert.equal(providerCalls,0);
 }finally{
  globalThis.fetch=originalFetch;
  await finishSqlFixtureWork();await sql.end();
 }
}});
