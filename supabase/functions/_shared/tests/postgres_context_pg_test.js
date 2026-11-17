// Explicitly synthetic, disposable loopback PostgreSQL only. This exercises the
// real transaction adapter and server settings; it is not production evidence.
import assert from 'node:assert/strict';
import postgres from 'npm:postgres@3.4.7';
import {PostgresDatabase} from '../postgres.js';
import {applicationWorkTuple} from '../application-fence.js';
import {syntheticFixtureWork,finishFixtureWork} from './helpers/fenced-unit.js';

const url=new URL(Deno.env.get('COLLECT_POSTGRES_CONTEXT_TEST_DATABASE_URL')??'');
assert.equal(url.protocol,'postgres:');
assert.equal(url.hostname,'127.0.0.1');
assert.equal(url.port,'55451');
assert.equal(url.pathname,'/buri_context_test');
assert.equal(url.username,'collect_context_test');
assert.equal(url.search,'');
assert.equal(url.hash,'');

Deno.test('real PostgreSQL keeps read and write context transaction-local and fenced',async()=>{
 const sql=postgres(url.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}});
 const work=syntheticFixtureWork(),claims={sub:'synthetic-subject',role:'authenticated'};
 const db=new PostgresDatabase(sql,claims,work);
 try{
  const [identity]=await sql`select current_database() as db,current_user as usr,host(inet_server_addr()) as host,inet_server_port() as port`;
  assert.deepEqual({...identity},{db:'buri_context_test',usr:'collect_context_test',host:'127.0.0.1',port:55451});
  await sql.unsafe(`CREATE ROLE collect_runtime NOLOGIN;
   CREATE SCHEMA app;
   CREATE SCHEMA private;
   GRANT USAGE,CREATE ON SCHEMA app TO collect_runtime;
   GRANT USAGE ON SCHEMA private TO collect_runtime;
   CREATE TABLE app.synthetic_rollback(id integer);
   GRANT INSERT,SELECT ON app.synthetic_rollback TO collect_runtime;
   CREATE FUNCTION app.current_setting(text) RETURNS text LANGUAGE sql AS $$ SELECT 'spoof'::text $$;
   CREATE FUNCTION app.set_config(text,text,boolean) RETURNS text LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'spoof'; END $$;
   CREATE FUNCTION private.collect_fence_assert_write(i uuid,e bigint,s text) RETURNS jsonb LANGUAGE plpgsql AS $$
   BEGIN
     IF current_user <> 'collect_runtime'
       OR pg_catalog.current_setting('collect.fence_admission_id') <> i::text
       OR pg_catalog.current_setting('collect.fence_epoch') <> e::text
       OR pg_catalog.current_setting('collect.fence_source_sha256') <> s
       OR pg_catalog.current_setting('collect.edge_verified') <> 'true'
       OR pg_catalog.current_setting('request.jwt.claims')::jsonb ->> 'sub' <> 'synthetic-subject'
       OR pg_catalog.current_setting('collect.synthetic_deny',true) = 'true'
     THEN RAISE EXCEPTION 'synthetic_fence_denied'; END IF;
     RETURN jsonb_build_object('contractVersion',1,'epoch',e,'mode','open');
   END $$;
  `);
  // Shadow functions in app cannot falsify the mode or hijack the settings.
  await sql.unsafe('SET search_path=app,pg_catalog');
  await work.assert();
  const tuple=applicationWorkTuple(work);

  async function readCase(begin,options,allowed){
   const tx=await sql.reserve();
   try{
    await tx.unsafe(begin);
    if(!allowed){
     await assert.rejects(()=>db.readContext(tx,options));
     const [row]=await tx`select current_user as usr`;
     assert.equal(row.usr,'collect_context_test');
     return;
    }
    await db.readContext(tx,options);
    const [row]=await tx`select current_user as usr,pg_catalog.current_setting('transaction_read_only') as readonly,
      pg_catalog.current_setting('transaction_isolation') as isolation,pg_catalog.current_setting('statement_timeout') as statement_timeout,
      pg_catalog.current_setting('lock_timeout') as lock_timeout,pg_catalog.current_setting('request.jwt.claims') as claims,
      pg_catalog.current_setting('collect.edge_verified') as verified`;
    assert.equal(row.usr,'collect_runtime');
    assert.equal(row.readonly,'on');
    assert.equal(row.isolation,options?.isolation??'repeatable read');
    assert.equal(row.statement_timeout,'15s');
    assert.equal(row.lock_timeout,'5s');
    assert.deepEqual(JSON.parse(row.claims),claims);
    assert.equal(row.verified,'true');
    await assert.rejects(()=>tx.unsafe('CREATE TABLE app.synthetic_forbidden(id integer)'),e=>e.code==='25006');
   }finally{await tx.unsafe('ROLLBACK');tx.release();}
  }
  await readCase('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY',undefined,true);
  await readCase('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY',{isolation:'read committed'},true);
  await readCase('BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE',{isolation:'read committed'},false);
  await readCase('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY',{isolation:'read committed'},false);
  assert.equal((await sql`select to_regclass('app.synthetic_forbidden') as name`)[0].name,null);

  await assert.rejects(()=>db.transaction(async tx=>{
   await db.context(tx);
   const [row]=await tx`select current_user as usr,pg_catalog.current_setting('collect.fence_admission_id') as admission,
     pg_catalog.current_setting('collect.fence_epoch') as epoch,pg_catalog.current_setting('collect.fence_source_sha256') as source,
     pg_catalog.current_setting('statement_timeout') as statement_timeout,pg_catalog.current_setting('lock_timeout') as lock_timeout`;
   assert.deepEqual({...row},{usr:'collect_runtime',admission:tuple[0],epoch:String(tuple[1]),source:tuple[2],statement_timeout:'15s',lock_timeout:'5s'});
   await tx`insert into app.synthetic_rollback values(1)`;
   throw Error('synthetic_rollback');
  }),/synthetic_rollback/);
  assert.equal(Number((await sql`select count(*) as n from app.synthetic_rollback`)[0].n),0);
  await assert.rejects(()=>db.transaction(async tx=>{
   await tx`select pg_catalog.set_config('collect.synthetic_deny','true',true)`;
   await db.context(tx);
  }),e=>e.status===503&&e.code==='application_fence_unavailable');
  const [after]=await sql`select current_user as usr,nullif(pg_catalog.current_setting('collect.edge_verified',true),'') as verified,
    nullif(pg_catalog.current_setting('collect.fence_admission_id',true),'') as admission`;
  assert.deepEqual({...after},{usr:'collect_context_test',verified:null,admission:null});
 }finally{
  await finishFixtureWork();
  await sql.end({timeout:2});
 }
});
