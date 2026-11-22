// Explicitly synthetic, disposable loopback PostgreSQL only. This exercises the
// real transaction adapter and server settings; it is not production evidence.
import assert from 'node:assert/strict';
import postgres from 'npm:postgres@3.4.7';
import {PostgresDatabase} from '../postgres.js';
import {applicationWorkTuple} from '../application-fence.js';
import {syntheticFixtureWork,finishFixtureWork} from './helpers/fenced-unit.js';
import {SupabaseObjectBucket} from '../adapters.js';
import {joinCollectMutation} from '../postgres-mutation-lock.js';

const target=Deno.env.get('COLLECT_POSTGRES_CONTEXT_TEST_DATABASE_URL');
function migrationFunction(sql:string,name:string) {
 const start=sql.indexOf('CREATE FUNCTION private.'+name+'('), end=sql.indexOf('END;$fn$;',start);
 assert.ok(start>=0&&end>start,name);
 return sql.slice(start,end+'END;$fn$;'.length);
}
Deno.test({name:'real PostgreSQL keeps read and write context transaction-local and fenced',ignore:!target,fn:async()=>{
 const url=new URL(target!);
 assert.equal(url.protocol,'postgres:');
 assert.equal(url.hostname,'127.0.0.1');
 assert.equal(url.port,'55451');
 assert.equal(url.pathname,'/buri_context_test');
 assert.equal(url.username,'collect_context_test');
 assert.equal(url.search,'');
 assert.equal(url.hash,'');
 const sql=postgres(url.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}});
 const work=syntheticFixtureWork(),claims={sub:'synthetic-subject',role:'authenticated'};
 const db=new PostgresDatabase(sql,claims,work);
 try{
  const [identity]=await sql`select current_database() as db,current_user as usr,host(inet_server_addr()) as host,inet_server_port() as port`;
  assert.deepEqual({...identity},{db:'buri_context_test',usr:'collect_context_test',host:'127.0.0.1',port:55451});
  const fence=await Deno.readTextFile(new URL('../../../migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url));
  await sql.unsafe(`CREATE ROLE collect_runtime NOLOGIN;
   CREATE SCHEMA app;
   CREATE SCHEMA private;
   GRANT USAGE,CREATE ON SCHEMA app TO collect_runtime;
   GRANT USAGE ON SCHEMA private TO collect_runtime;
   CREATE TABLE app.synthetic_rollback(id integer);
   CREATE TABLE app.synthetic_admin_grant(active boolean);
   CREATE TABLE app.synthetic_unfenced(id integer);
   CREATE TABLE private.storage_namespace(singleton boolean PRIMARY KEY, origin text, bucket text);
   CREATE TABLE private.storage_put_intents(
     operation_id text PRIMARY KEY, object_key text UNIQUE, fingerprint text, sha256 text,
     size bigint, scope jsonb, http_metadata jsonb, custom_metadata jsonb,
     state text DEFAULT 'pending', attempts integer DEFAULT 0, active_attempt uuid,
     upload_unresolved boolean DEFAULT false, delete_tombstone boolean DEFAULT false,
     created_at timestamptz DEFAULT clock_timestamp()
   );
   INSERT INTO app.synthetic_admin_grant VALUES(true);
   GRANT INSERT,SELECT ON app.synthetic_rollback TO collect_runtime;
   GRANT UPDATE,SELECT ON app.synthetic_admin_grant TO collect_runtime;
   GRANT INSERT,SELECT ON app.synthetic_unfenced TO collect_runtime;
   GRANT INSERT,SELECT ON private.storage_namespace TO collect_runtime;
   GRANT INSERT,SELECT,UPDATE(state) ON private.storage_put_intents TO collect_runtime;
   CREATE FUNCTION app.current_setting(text) RETURNS text LANGUAGE sql AS $$ SELECT 'spoof'::text $$;
   CREATE FUNCTION app.set_config(text,text,boolean) RETURNS text LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'spoof'; END $$;
   ${migrationFunction(fence,'_collect_fence_require_rc')}
   CREATE FUNCTION private.collect_fence_assert_write(i uuid,e bigint,s text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
   BEGIN
     PERFORM private._collect_fence_require_rc(true);
     IF pg_catalog.current_setting('role') <> 'collect_runtime'
       OR pg_catalog.current_setting('collect.fence_admission_id') <> i::text
       OR pg_catalog.current_setting('collect.fence_epoch') <> e::text
       OR pg_catalog.current_setting('collect.fence_source_sha256') <> s
       OR pg_catalog.current_setting('collect.edge_verified') <> 'true'
       OR pg_catalog.current_setting('request.jwt.claims')::jsonb ->> 'sub' <> 'synthetic-subject'
       OR pg_catalog.current_setting('collect.synthetic_deny',true) = 'true'
     THEN RAISE EXCEPTION 'synthetic_fence_denied'; END IF;
     RETURN jsonb_build_object('contractVersion',1,'epoch',e,'mode','open');
   END $$;
   ${migrationFunction(fence,'_collect_fence_statement')}
   CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
     ON app.synthetic_rollback FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
   CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
     ON private.storage_namespace FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
   CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
     ON private.storage_put_intents FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
  `);
  // Shadow functions in app cannot falsify the mode or hijack the settings.
  await sql.unsafe('SET search_path=app,pg_catalog');
  await work.assert();
  const tuple=applicationWorkTuple(work);

  async function readCase(begin:string,options:{isolation:string}|undefined,allowed:boolean){
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
    await assert.rejects(()=>tx.unsafe('CREATE TABLE app.synthetic_forbidden(id integer)'),(e:unknown)=>e instanceof postgres.PostgresError&&e.code==='25006');
   }finally{await tx.unsafe('ROLLBACK');tx.release();}
  }
  await readCase('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY',undefined,true);
  await readCase('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY',{isolation:'read committed'},true);
  await readCase('BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE',{isolation:'read committed'},false);
  await readCase('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY',{isolation:'read committed'},false);
  assert.equal((await sql`select to_regclass('app.synthetic_forbidden') as name`)[0].name,null);

  await assert.rejects(()=>db.transaction(async (tx:postgres.ReservedSql)=>{
   await db.context(tx);
   const [row]=await tx`select current_user as usr,pg_catalog.current_setting('collect.fence_admission_id') as admission,
     pg_catalog.current_setting('collect.fence_epoch') as epoch,pg_catalog.current_setting('collect.fence_source_sha256') as source,
     pg_catalog.current_setting('statement_timeout') as statement_timeout,pg_catalog.current_setting('lock_timeout') as lock_timeout`;
   assert.deepEqual({...row},{usr:'collect_runtime',admission:tuple[0],epoch:String(tuple[1]),source:tuple[2],statement_timeout:'15s',lock_timeout:'5s'});
   await tx`insert into app.synthetic_rollback values(1)`;
   throw Error('synthetic_rollback');
  }),/synthetic_rollback/);
  assert.equal(Number((await sql`select count(*) as n from app.synthetic_rollback`)[0].n),0);
  await assert.rejects(()=>db.transaction(async (tx:postgres.ReservedSql)=>{
   await tx`select pg_catalog.set_config('collect.synthetic_deny','true',true)`;
   await db.context(tx);
   }),(e:unknown)=>typeof e==='object'&&e!==null&&'status' in e&&'code' in e&&e.status===503&&e.code==='application_fence_unavailable');
  const separate=postgres(url.href,{max:1,ssl:false,connect_timeout:2});
  try {
   const bucket=new SupabaseObjectBucket({
    DB:db,SUPABASE_URL:'https://synthetic.supabase.co',SUPABASE_SECRET_KEY:'sb_secret_synthetic',
   });
   const intent={operationId:'synthetic-storage-put',key:'fixture/storage',fingerprint:'a'.repeat(64),
    sha256:'b'.repeat(64),size:1,scope:{ownerId:'synthetic-owner',entityId:'synthetic-id',purpose:'evidence'},
    httpMetadata:{},customMetadata:{}};
   await separate.begin(async writer=>{
    await joinCollectMutation(writer);
    const original=await bucket.journal.beginPut(intent);
    assert.equal(original.operationId,intent.operationId);
    assert.equal(original.state,'pending');
    assert.deepEqual(await bucket.journal.beginPut(intent),original);
    await assert.rejects(bucket.journal.beginPut({...intent,fingerprint:'c'.repeat(64)}),{code:'storage_request_conflict'});
   });
   const project=(...queries:string[])=>db.adminReadBatch(
    db.prepare('SELECT 1'),db.prepare('SELECT active AS allowed FROM app.synthetic_admin_grant FOR SHARE'),
    queries.map(query=>db.prepare(query)));
   await separate.begin(async writer=>{
    await writer`select pg_advisory_xact_lock(734636924058501::bigint)`;
    const [page,mode]=await project('SELECT 42 AS value',`SELECT pg_catalog.current_setting('transaction_isolation') AS isolation,
      nullif(pg_catalog.current_setting('collect.fence_admission_id',true),'') AS admission`);
    assert.equal(page.results[0].value,42);
    assert.deepEqual({...mode.results[0]},{isolation:'repeatable read',admission:null});
   });
   await assert.rejects(()=>project('INSERT INTO app.synthetic_rollback VALUES(2)'),(error:unknown)=>
    error instanceof postgres.PostgresError&&error.code==='55000');
   await project('INSERT INTO app.synthetic_unfenced VALUES(3)');
   assert.equal(Number((await separate`select count(*) as n from app.synthetic_unfenced`)[0].n),0);

   let concurrent: Promise<string|null>|undefined;
   await separate.begin(async writer=>{
    await writer`update app.synthetic_admin_grant set active=false`;
    concurrent=project('SELECT 42 AS value').then(()=>null,(error:unknown)=>
     error instanceof postgres.PostgresError?error.code:null);
    for(let retries=0;retries<75;retries++){
     const [row]=await writer`select exists(select 1 from pg_catalog.pg_locks
       where not granted and pid<>pg_backend_pid()
       and pg_backend_pid()=any(pg_catalog.pg_blocking_pids(pid))) as waiting`;
     if(row.waiting)return;
     await new Promise(resolve=>setTimeout(resolve,10));
    }
    assert.fail('The Admin read must wait for the grant row while revocation is pending.');
   });
   assert.equal(await concurrent,'40001');
   await assert.rejects(()=>project('SELECT NULL AS value'),/admin_account_authority/);
  } finally {await separate.end({timeout:2});}
  const [after]=await sql`select current_user as usr,nullif(pg_catalog.current_setting('collect.edge_verified',true),'') as verified,
    nullif(pg_catalog.current_setting('collect.fence_admission_id',true),'') as admission`;
  assert.deepEqual({...after},{usr:'collect_context_test',verified:null,admission:null});
 }finally{
  await finishFixtureWork();
  await sql.end({timeout:2});
 }
}});
