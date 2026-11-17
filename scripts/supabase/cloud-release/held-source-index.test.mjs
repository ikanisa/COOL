import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {HELD_SOURCE_INDEX_CATALOG_SQL} from './managed-jobs-operator.mjs';

const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
const migration=readFileSync(new URL('../../../supabase/migrations/20261117205959_burimunsi_sms_source_index.sql',import.meta.url),'utf8');
test('exact bounded index migration requires a fence and indexes raw source lookup',{skip:!modulePath},async()=>{
 const {PGlite}=await import(modulePath);
 for(const mode of ['fenced','open']){
  const db=new PGlite();try{
   await db.exec(`CREATE SCHEMA app; CREATE SCHEMA private;
    CREATE TABLE private.collect_fence_control(singleton boolean,mode text);
    INSERT INTO private.collect_fence_control VALUES(true,'${mode}');
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN; END$$;
    CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,parse_attempt_id text,
     PRIMARY KEY(transaction_id,raw_sms_id,parse_attempt_id));
    INSERT INTO app.momo_transaction_sources SELECT 'transaction-'||n,'source-'||n,'attempt-'||n FROM generate_series(1,10000) n;`);
   if(mode==='open'){
    await assert.rejects(()=>db.exec(migration),/sms_source_index_precondition/);
    await db.exec('ROLLBACK');
    assert.equal((await db.query(HELD_SOURCE_INDEX_CATALOG_SQL)).rows[0].ok,false);
   }else{
    await db.exec(migration);assert.equal((await db.query(HELD_SOURCE_INDEX_CATALOG_SQL)).rows[0].ok,true);
    await db.exec('ANALYZE app.momo_transaction_sources');
    const plan=(await db.query("EXPLAIN (FORMAT JSON) SELECT 1 FROM app.momo_transaction_sources WHERE raw_sms_id='source-5000' LIMIT 1")).rows[0]['QUERY PLAN'];
    assert.match(JSON.stringify(plan),/burimunsi_momo_sources_raw_lookup/);
   }
  }finally{await db.close();}
 }
});
