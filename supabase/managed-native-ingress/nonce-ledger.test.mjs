import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';

const specifier=process.env.COLLECT_INGRESS_TEST_PGLITE_MODULE??new URL('../../scripts/supabase/node_modules/@electric-sql/pglite/dist/index.js',import.meta.url).href;
let PGlite;try{({PGlite}=await import(specifier));}catch{}
const sql=await readFile(new URL('./nonce-ledger.sql',import.meta.url),'utf8');
const base=`CREATE ROLE collect_runtime; CREATE ROLE audit_probe; CREATE SCHEMA private;
 GRANT USAGE ON SCHEMA private TO collect_runtime,audit_probe;
 ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT SELECT ON TABLES TO audit_probe;
 ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT EXECUTE ON FUNCTIONS TO audit_probe;
 CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'not_runtime';END IF;END$$;
 CREATE FUNCTION private._collect_fence_require_rc(boolean) RETURNS void LANGUAGE plpgsql AS $$BEGIN
  IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'not_rc';END IF;END$$;
 CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE plpgsql AS $$BEGIN
  IF $1 IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'::uuid OR $2 IS DISTINCT FROM 1::bigint OR $3 IS DISTINCT FROM repeat('c',64)
  THEN RAISE EXCEPTION 'fence_closed';END IF;RETURN '{}'::jsonb;END$$;`;
const context=`SET LOCAL ROLE collect_runtime;
 SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id','11111111-1111-4111-8111-111111111111',true),
 set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',repeat('c',64),true)`;
async function fixture(){assert.ok(PGlite,'Install pinned PGlite or set COLLECT_INGRESS_TEST_PGLITE_MODULE');const db=new PGlite();await db.exec(base);await db.exec(sql);return db;}
async function consume(db,values,{brokenFence=false}={}){
 await db.exec('BEGIN;'+context);
 try{
  if(brokenFence)await db.exec("SELECT set_config('collect.fence_source_sha256','wrong',true)");
  const result=await db.query('SELECT private.collect_native_ingress_consume($1::uuid,$2,$3,$4::bigint) AS claimed',values);
  await db.exec('COMMIT');return result.rows[0].claimed;
 }catch(error){await db.exec('ROLLBACK');throw error;}
}
const values=(issued=Date.now())=>[randomUUID(),'a'.repeat(64),'b'.repeat(64),issued];

test('a committed nonce is accepted once and duplicate use is denied',async()=>{
 const db=await fixture();try{const input=values();assert.equal(await consume(db,input),true);assert.equal(await consume(db,input),false);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_native_ingress_nonce_uses')).rows[0].n,1);
 }finally{await db.close();}
});
test('expired, future and fenced requests do not create a witness',async()=>{
 const db=await fixture();try{
  assert.equal(await consume(db,values(Date.now()-31000)),false);assert.equal(await consume(db,values(Date.now()+3000)),false);
  await assert.rejects(consume(db,values(),{brokenFence:true}));
  assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_native_ingress_nonce_uses')).rows[0].n,0);
 }finally{await db.close();}
});
test('cleanup removes only entries beyond the signature and retention window',async()=>{
 const db=await fixture();try{
  const old=randomUUID(),recent=randomUUID();
  await db.query(`INSERT INTO private.collect_native_ingress_nonce_uses(nonce,profile_sha256,policy_sha256,signed_at,expires_at)
   VALUES($1,repeat('a',64),repeat('b',64),clock_timestamp()-interval '4 minutes',clock_timestamp()-interval '3 minutes 30 seconds'),
   ($2,repeat('a',64),repeat('b',64),clock_timestamp()-interval '1 minute',clock_timestamp()-interval '30 seconds')`,[old,recent]);
  assert.equal(await consume(db,values()),true);
  const found=(await db.query('SELECT nonce::text AS nonce FROM private.collect_native_ingress_nonce_uses')).rows.map(r=>r.nonce);
  assert.equal(found.includes(old),false);assert.equal(found.includes(recent),true);
 }finally{await db.close();}
});
test('default grants do not expose the nonce table or function to another role',async()=>{
 const db=await fixture();try{
  const row=(await db.query(`SELECT has_table_privilege('audit_probe','private.collect_native_ingress_nonce_uses','SELECT') AS table_access,
   has_function_privilege('audit_probe','private.collect_native_ingress_consume(uuid,text,text,bigint)','EXECUTE') AS function_access,
   has_function_privilege('collect_runtime','private.collect_native_ingress_consume(uuid,text,text,bigint)','EXECUTE') AS runtime_access`)).rows[0];
  assert.deepEqual(row,{table_access:false,function_access:false,runtime_access:true});
 }finally{await db.close();}
});
