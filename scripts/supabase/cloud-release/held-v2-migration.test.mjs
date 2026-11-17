// In-memory synthetic SQL only: no network, application rows or Cloud writes.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {HELD_V2_MIGRATION_SHA,HELD_V2_READY_SHA,HELD_V2_READY_IDENTITY_SQL} from '../../../supabase/functions/_shared/domain/burimunsi/held-recovery-v2.js';
import {HELD_RECOVERY_CATALOG_SQL,HELD_RECOVERY_POLICY,HELD_RESUME_CATALOG_SQL,HELD_SOURCE_INDEX_CATALOG_SQL} from './managed-jobs-operator.mjs';
const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
const migration=readFileSync(new URL('../../../supabase/migrations/20261117220639_burimunsi_held_consent_v2.sql',import.meta.url),'utf8');
const load=name=>readFileSync(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8');
const hash=s=>createHash('sha256').update(s).digest('hex');
test('candidate embeds the previously qualified catalog, RLS and trigger queries',()=>{
 const extract=head=>{const a=migration.indexOf(head);assert(a>=0);const start=migration.indexOf('FROM (',a)+6;
  const end=migration.indexOf(') checks;',start);assert(end>start);return migration.slice(start,end);};
 const quoted="'"+HELD_RECOVERY_POLICY.replaceAll("'","''")+"'";
 assert.equal(extract('SELECT checks.triggers_ok,checks.tables_ok INTO'),HELD_RECOVERY_CATALOG_SQL.replaceAll('=$1','='+quoted));
 assert.equal(extract('SELECT checks.ok INTO resume_ok'),HELD_RESUME_CATALOG_SQL);
 assert.equal(extract('SELECT checks.ok INTO index_ok'),HELD_SOURCE_INDEX_CATALOG_SQL);
});
test('candidate migration installs pinned v2 SQL and denies missing migrations and guards',{skip:!modulePath},async()=>{
 assert.equal(hash(migration),HELD_V2_MIGRATION_SHA);
 const {PGlite}=await import(modulePath),db=new PGlite();
 try{
  await db.exec(`CREATE SCHEMA private;CREATE SCHEMA supabase_migrations;CREATE SCHEMA app;
   CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_importer;CREATE ROLE collect_runtime;
   CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,statements text[]);
   CREATE TABLE private.collect_fence_control(singleton boolean,mode text,source_sha256 text,epoch bigint);
   CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,
    grant_id uuid,grant_version bigint,generation bigint,enabled boolean);
   CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE sql AS $$SELECT jsonb_build_object(
    'collectionId','group-a','accountId','10000000-0000-4000-8000-000000000001',
    'installationId','20000000-0000-4000-8000-000000000001',
    'grantId','30000000-0000-4000-8000-000000000001','grantVersion',1)$$;
   INSERT INTO private.collect_fence_control VALUES(true,'fenced',repeat('a',64),1);
   INSERT INTO private.burimunsi_observation_consents VALUES('group-a','10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,1,true);`);
  const prior=load('20261117220000_burimunsi_held_resume_guard.sql');
  await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2::text[])',['20261117220000',[prior]]);
  await db.exec(migration);
  assert.equal((await db.query(HELD_V2_READY_IDENTITY_SQL,[HELD_V2_READY_SHA])).rows[0].ok,true);
  await db.exec(`UPDATE private.collect_fence_control SET mode='open';
   SELECT set_config('collect.fence_source_sha256',repeat('a',64),false),set_config('collect.fence_epoch','1',false),
    set_config('collect.fence_admission_id','40000000-0000-4000-8000-000000000001',false),
    set_config('burimunsi.collection_id','group-a',false);`);
  const call=(source='a'.repeat(64),generation=1)=>db.query('SELECT private.burimunsi_held_v2_ready($1,$2::bigint,$3)',
   [source,generation,HELD_V2_MIGRATION_SHA]);
  await assert.rejects(()=>call('b'.repeat(64)),/sms_held_v2_invalid/);
  await assert.rejects(()=>call('a'.repeat(64),2),/sms_held_v2_consent_changed/);
  await assert.rejects(()=>call(),/sms_held_v2_migration_changed/);
  for(const [version,file] of [['20261117205959','20261117205959_burimunsi_sms_source_index.sql'],
   ['20261117210000','20261117210000_burimunsi_held_recovery.sql'],['20261117220639','20261117220639_burimunsi_held_consent_v2.sql']])
   await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2::text[])',[version,[load(file)]]);
  // Pinned history alone is insufficient: all live guard functions must match.
  await assert.rejects(()=>call(),/sms_held_v2_guard_changed/);
  await db.exec('UPDATE private.burimunsi_observation_consents SET enabled=false,generation=2');
  await db.exec('UPDATE private.burimunsi_observation_consents SET enabled=true,generation=3');
  await assert.rejects(()=>call(),/sms_held_v2_consent_changed/);
 }finally{await db.close();}
});
