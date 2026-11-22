import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';

const root=process.env.COLLECT_RLS_HELPER_SOURCE_ROOT?
 resolve(process.env.COLLECT_RLS_HELPER_SOURCE_ROOT):resolve(import.meta.dirname,'../..');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fixtureSha='b21d88816c445d14cef5032c3cd4abaebc1db2001fcb3435022ab6b496182ca4';

function target(){
 const value=process.env.COLLECT_RLS_HELPER_TEST_DATABASE_URL;
 assert.ok(value,'COLLECT_RLS_HELPER_TEST_DATABASE_URL is mandatory; this suite never silently skips');
 const url=new URL(value);
 assert.ok(['postgres:','postgresql:'].includes(url.protocol),'PostgreSQL is required');
 assert.equal(url.hostname,'127.0.0.1','Only the exclusively owned loopback fixture is allowed');
 const alternate=process.env.COLLECT_CI_SYNTHETIC==='true'&&url.hostname==='127.0.0.1'&&['55441','55443'].includes(url.port);
 assert.ok(url.port==='55439'||alternate,'Only the owned local fixture cluster or explicit synthetic qualification port is permitted');
 assert.equal(url.pathname,'/collect_rls_helper_acl_test');
 assert.equal(decodeURIComponent(url.username),'collect_test');
 assert.equal(url.search,'','Connection overrides are forbidden');
 assert.equal(url.hash,'');
 return {host:'127.0.0.1',port:Number(url.port),database:'collect_rls_helper_acl_test',
  user:'collect_test',password:decodeURIComponent(url.password),ssl:false,
  connectionTimeoutMillis:5000,statement_timeout:15000,query_timeout:20000};
}

async function sources(){
 const directory=join(root,'supabase/migrations');
 const names=(await readdir(directory)).filter(name=>/^(?:\d{14}_)?collect_rls_helper_permissions\.sql$/.test(name));
 assert.equal(names.length,1,'Exactly one reviewed RLS helper permission migration must be present');
 const migrationPath=join(directory,names[0]);
 const fixturePath=join(root,'supabase/tests/fixtures/rls_auto_enable.fixture.sql');
 const migrationBytes=await readFile(migrationPath),fixtureBytes=await readFile(fixturePath);
 assert.equal(sha(fixtureBytes),fixtureSha,'The captured helper body must remain exact');
 return {migrationPath,fixturePath,migrationBytes,fixtureBytes,
  migration:migrationBytes.toString('utf8'),fixture:fixtureBytes.toString('utf8')};
}

async function functionState(db,signature='public.rls_auto_enable()'){
 const result=await db.query(`SELECT (pg_catalog.to_jsonb(p)-'proacl') AS metadata,
    pg_catalog.pg_get_functiondef(p.oid) AS definition,
    (SELECT COALESCE(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
       'grantee',a.grantee::text,'grantor',a.grantor::text,
       'privilege_type',a.privilege_type,'is_grantable',a.is_grantable)
       ORDER BY a.grantee,a.grantor,a.privilege_type,a.is_grantable),'[]'::jsonb)
      FROM pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a) AS acl
   FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure($1)`,[signature]);
 return result.rows[0]??null;
}

async function triggerState(db){
 return (await db.query("SELECT pg_catalog.to_jsonb(e) AS metadata FROM pg_catalog.pg_event_trigger e WHERE evtname='ensure_rls' ORDER BY oid")).rows;
}

// The fixture database and shared roles are provisioned by the one PG owner.
// This suite creates no roles, grants no memberships, and resets no database or
// schema. All fixture DDL and per-database schema grants roll back together.
test('RLS helper ACL hygiene on actual PostgreSQL preserves event-trigger behavior',{timeout:60000},async t=>{
 const config=target(),source=await sources();
 const {Client}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
 const db=new Client(config);let began=false;
 await db.connect();
 try{
  const identity=(await db.query(`SELECT current_database() AS database,current_user AS actor,
    (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) AS superuser`)).rows[0];
  assert.deepEqual(identity,{database:'collect_rls_helper_acl_test',actor:'collect_test',superuser:true});
  const roles=(await db.query("SELECT rolname,oid::text AS oid,rolsuper FROM pg_catalog.pg_roles WHERE rolname=ANY($1::text[]) ORDER BY rolname",[['postgres','anon','authenticated','service_role']])).rows;
  assert.deepEqual(roles.map(role=>role.rolname),['anon','authenticated','postgres','service_role'],'Existing fixture roles are required; this suite never creates shared roles');
  assert.equal(roles.find(role=>role.rolname==='postgres').rolsuper,false,'Preserve the existing NOSUPERUSER postgres role');
  await db.query('BEGIN');began=true;
  assert.equal(await functionState(db),null,'Use a fresh exclusively owned fixture database');
  assert.deepEqual(await triggerState(db),[],'The owned fixture must not contain an existing trigger');
  assert.equal((await db.query("SELECT pg_catalog.to_regclass('public.collect_rls_helper_acl_after') AS existing")).rows[0].existing,null);

  await t.test('absent zero-argument helper is a no-op, including an unrelated overload',async()=>{
   await db.query('SAVEPOINT absent_helper');
   try{
    await db.query(source.migration);assert.equal(await functionState(db),null);
    await db.query("CREATE FUNCTION public.rls_auto_enable(integer) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$");
    const before=await functionState(db,'public.rls_auto_enable(integer)');
    await db.query(source.migration);
    assert.equal(await functionState(db),null);
    assert.deepEqual(await functionState(db,'public.rls_auto_enable(integer)'),before);
   }finally{await db.query('ROLLBACK TO SAVEPOINT absent_helper');await db.query('RELEASE SAVEPOINT absent_helper');}
  });

  async function rejectedShape(name,setup){
   await t.test(name,async()=>{
    await db.query('SAVEPOINT rejected_shape');
    try{
     await setup();const before=await functionState(db);
     assert.ok(before);
     await db.query('SAVEPOINT migration_refusal');
     await assert.rejects(db.query(source.migration),error=>error.code==='55000'&&error.message==='Unexpected public.rls_auto_enable() shape; permissions were not changed');
     await db.query('ROLLBACK TO SAVEPOINT migration_refusal');await db.query('RELEASE SAVEPOINT migration_refusal');
     assert.deepEqual(await functionState(db),before,'Refusal must preserve function metadata, implementation and ACL');
    }finally{await db.query('ROLLBACK TO SAVEPOINT rejected_shape');await db.query('RELEASE SAVEPOINT rejected_shape');}
   });
  }
  await rejectedShape('an existing wrong return type fails closed',async()=>{
   await db.query("CREATE FUNCTION public.rls_auto_enable() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$ BEGIN RETURN; END $$; ALTER FUNCTION public.rls_auto_enable() OWNER TO postgres");
  });
  await rejectedShape('an unexpected owner fails closed',async()=>{await db.query(source.fixture);});
  await rejectedShape('an unexpected search path fails closed',async()=>{
   await db.query(source.fixture);await db.query('ALTER FUNCTION public.rls_auto_enable() OWNER TO postgres; ALTER FUNCTION public.rls_auto_enable() SET search_path=public');
  });
  await rejectedShape('security-invoker drift fails closed',async()=>{
   await db.query(source.fixture);await db.query('ALTER FUNCTION public.rls_auto_enable() OWNER TO postgres; ALTER FUNCTION public.rls_auto_enable() SECURITY INVOKER');
  });

  await db.query(source.fixture);
  await db.query(`ALTER FUNCTION public.rls_auto_enable() OWNER TO postgres;
    GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO PUBLIC,anon,authenticated,service_role;
    GRANT USAGE,CREATE ON SCHEMA public TO postgres;
    CREATE EVENT TRIGGER ensure_rls ON ddl_command_end EXECUTE FUNCTION public.rls_auto_enable()`);
  // Unlike Supabase's privileged extension environment, the local trigger stays
  // owned by the existing collect_test superuser. The function retains the real
  // postgres NOSUPERUSER owner. This difference is explicit, not an emulation
  // of Supautils or a reason to change shared cluster privileges.
  const beforeFunction=await functionState(db),beforeTrigger=await triggerState(db);
  assert.equal(String(beforeFunction.metadata.proowner),roles.find(role=>role.rolname==='postgres').oid);
  assert.equal(String(beforeTrigger[0].metadata.evtowner),(await db.query("SELECT oid::text AS oid FROM pg_catalog.pg_roles WHERE rolname='collect_test'")).rows[0].oid);
  assert.equal(beforeTrigger[0].metadata.evtenabled,'O');
  const removedGrantees=new Set(['0',...roles.filter(role=>['anon','authenticated'].includes(role.rolname)).map(role=>role.oid)]);

  await t.test('only PUBLIC, anon and authenticated execute grants change',async()=>{
   await db.query(source.migration);
   const afterFunction=await functionState(db);
   assert.deepEqual(afterFunction.metadata,beforeFunction.metadata,'OID, body, owner and all function configuration must stay exact');
   assert.equal(afterFunction.definition,beforeFunction.definition);
   assert.deepEqual(afterFunction.acl,beforeFunction.acl.filter(entry=>!removedGrantees.has(entry.grantee)));
   assert.deepEqual(await triggerState(db),beforeTrigger,'The existing trigger OID, owner, binding, tags and enabled state must stay exact');
   const access=(await db.query(`SELECT pg_catalog.has_function_privilege('anon','public.rls_auto_enable()','EXECUTE') AS anon,
    pg_catalog.has_function_privilege('authenticated','public.rls_auto_enable()','EXECUTE') AS authenticated,
    pg_catalog.has_function_privilege('service_role','public.rls_auto_enable()','EXECUTE') AS service_role,
    pg_catalog.has_function_privilege('postgres','public.rls_auto_enable()','EXECUTE') AS postgres`)).rows[0];
   assert.deepEqual(access,{anon:false,authenticated:false,service_role:true,postgres:true});
   const stable=await functionState(db);await db.query(source.migration);
   assert.deepEqual(await functionState(db),stable,'Reapplication is idempotent');
  });

  await t.test('the unchanged copied helper actually enables RLS after revocation',async()=>{
   await db.query('SET LOCAL ROLE postgres');
   try{await db.query('CREATE TABLE public.collect_rls_helper_acl_after(id bigint PRIMARY KEY)');}
   finally{await db.query('RESET ROLE');}
   const table=(await db.query(`SELECT c.relrowsecurity,pg_catalog.pg_get_userbyid(c.relowner) AS owner
     FROM pg_catalog.pg_class c WHERE c.oid='public.collect_rls_helper_acl_after'::pg_catalog.regclass`)).rows[0];
   assert.deepEqual(table,{relrowsecurity:true,owner:'postgres'},'CREATE success alone is insufficient: the copied helper catches errors');
   assert.deepEqual(await triggerState(db),beforeTrigger);
   assert.deepEqual((await functionState(db)).metadata,beforeFunction.metadata);
  });
 }finally{
  try{if(began)await db.query('ROLLBACK');}
  finally{await db.end();}
 }
 assert.equal(sha(await readFile(source.migrationPath)),sha(source.migrationBytes),'Migration source changed during qualification');
 assert.equal(sha(await readFile(source.fixturePath)),sha(source.fixtureBytes),'Captured fixture source changed during qualification');
});
