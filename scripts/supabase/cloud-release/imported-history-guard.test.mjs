// Socket-only, disposable PG17. Actual pinned function bodies and the guard
// candidate run against synthetic data; no existing database is accepted.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
const {Client}=createRequire(import.meta.url)('pg');
const read=path=>readFile(new URL(`../../../${path}`,import.meta.url),'utf8');
const extract=(source,name)=>{
 let start=source.indexOf(`CREATE FUNCTION private.${name}(`);
 if(start<0)start=source.indexOf(`CREATE OR REPLACE FUNCTION private.${name}(`);
 const end=source.indexOf('$fn$;',source.indexOf('$fn$',start)+4);
 assert(start>=0&&end>=0);return source.slice(start,end+5);
};
let fixture;const clients=[];let checks=0;
try{
 verifyEnvironment(process.env);await verifyBinaryPins();
 fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_history_guard_fixture'});
 assert.equal(fixture.bin,BIN);
 async function connect(user){const c=new Client({host:fixture.socket,port:fixture.port,user,database:'postgres',connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;
  CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_importer;CREATE ROLE collect_runtime;
  GRANT collect_runtime TO postgres;
  CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA app AUTHORIZATION postgres;
  GRANT USAGE ON SCHEMA private,app TO collect_runtime;`);
 const owner=await connect('postgres');
 const identity=(await owner.query("SELECT session_user u,current_user c,inet_server_addr() IS NULL sock,current_setting('cluster_name') n")).rows[0];
 assert.deepEqual(identity,{u:'postgres',c:'postgres',sock:true,n:'collect_history_guard_fixture'});
 await owner.query(`
  CREATE TABLE private.collect_fence_control(singleton boolean,mode text);
  INSERT INTO private.collect_fence_control VALUES(true,'fenced');
  CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE FUNCTION private.burimunsi_auto_jobs_guard() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE FUNCTION private._burimunsi_native_work_authority(uuid) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
  CREATE TABLE private.collect_fence_admissions(kind text);
  CREATE TABLE private.burimunsi_unresolved_observations(source_id text,collection_id text,account_id text,principal_user_id text,
   grant_id text,installation_id text,grant_version bigint,fingerprint text,profile_sha256 text,created_at bigint,
   object_key text,object_sha256 text,profile_version text,profile_tuple_sha256 text);
  CREATE TABLE private.burimunsi_accounts(id text,collection_id text,principal_user_id text,active boolean,removed boolean,role text,capabilities text[],phone text);
  CREATE TABLE private.burimunsi_device_grants(id text,collection_id text,installation_id text,version bigint,active boolean,profile text);
  CREATE TABLE private.burimunsi_device_accounts(grant_id text,collection_id text,account_id text);
  CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id text,installation_id text,grant_id text,grant_version bigint,enabled boolean);
  CREATE TABLE private.burimunsi_scopes(collection_id text,enabled boolean,active_binding_id text,receiving_account_id text);
  CREATE TABLE private.burimunsi_detection_profiles(collection_id text,enabled boolean,expected_receiving_account_id text,profile_version text,profile_json text,revision bigint,evidence_sha256 text);
  CREATE TABLE app.collections(id text,status text);
  CREATE TABLE app.momo_receiving_accounts(id text,status text,provider text,profile_status text,profile_version text,profile_json text,currency text,timezone text);
  CREATE TABLE app.admin_grants(user_id text,permission text);
  CREATE TABLE app.admin_principal_links(user_id text,admin_user_id text);
  CREATE TABLE app.admin_users(id text,role text,status text);
  CREATE TABLE app.admin_account_role_capabilities(role text,permission text);
  CREATE FUNCTION private.burimunsi_pin_root_snapshot(text,text,text,text,text[]) RETURNS text LANGUAGE sql AS $$ SELECT 'proof'::text $$;
  CREATE FUNCTION private.burimunsi_observation_storage_matches(text,jsonb,text) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
  CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text PRIMARY KEY,collection_id text,state text,lease_until bigint,next_attempt_at bigint,
   relation text,transaction_id text,posting_next_attempt_at bigint,posting_facts jsonb,created_at bigint,
   posting_failure_count int NOT NULL DEFAULT 0,posting_last_error text,posting_last_failed_at bigint);
  CREATE TABLE private.burimunsi_native_financial_work(id uuid PRIMARY KEY,source_id text,transaction_id text,collection_id text,state text,next_attempt_at bigint,created_at bigint,lease_expires_at bigint);
  CREATE TABLE app.momo_transactions(id text PRIMARY KEY,event_kind text,has_conflict integer,allocation_state text);
  CREATE TABLE app.momo_financial_links(transaction_id text,payment_id text);
  CREATE TABLE app.ledger_entries(id text PRIMARY KEY,payment_id text,kind text);
  CREATE TABLE private.collect_imported_native_history(source_id text PRIMARY KEY,transaction_id text);
  ALTER TABLE private.collect_imported_native_history ENABLE ROW LEVEL SECURITY;
  ALTER TABLE private.collect_imported_native_history FORCE ROW LEVEL SECURITY;
  CREATE POLICY owner_policy ON private.collect_imported_native_history TO postgres USING (true) WITH CHECK (true);
  CREATE POLICY runtime_read ON private.collect_imported_native_history FOR SELECT TO collect_runtime USING (true);
  REVOKE ALL ON private.collect_imported_native_history FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
  GRANT SELECT ON private.collect_imported_native_history TO collect_runtime;
  GRANT SELECT,INSERT,UPDATE,DELETE ON private.burimunsi_auto_sms_jobs,private.burimunsi_native_financial_work,app.momo_financial_links,app.ledger_entries TO collect_runtime;
  ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ROW LEVEL SECURITY;
  ALTER TABLE private.burimunsi_auto_sms_jobs FORCE ROW LEVEL SECURITY;
  CREATE POLICY job_frame ON private.burimunsi_auto_sms_jobs TO postgres
   USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.native_receipt_frame',true)='1')
   WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.native_receipt_frame',true)='1');
 `);
 const auto=await read('supabase/migrations/20261112200100_burimunsi_native_auto_transactions.sql');
 const work=await read('supabase/migrations/20261113130300_burimunsi_native_financial_work.sql');
 const posting=await read('supabase/migrations/20261113130900_burimunsi_native_sms_posting.sql');
 const retry=await read('supabase/migrations/20261114101000_burimunsi_native_sms_post_retry.sql');
 for(const [source,name] of [[auto,'burimunsi_auto_snapshot'],[auto,'burimunsi_auto_candidates'],[work,'burimunsi_native_work_candidates'],[posting,'burimunsi_native_sms_post_candidates'],[retry,'burimunsi_native_sms_post_retry'],[retry,'burimunsi_native_sms_post_defer']])await owner.query(extract(source,name));
 await owner.query(`REVOKE ALL ON FUNCTION private.burimunsi_auto_snapshot(text),private.burimunsi_auto_candidates(text),private.burimunsi_native_work_candidates(uuid,integer),private.burimunsi_native_sms_post_candidates(integer) FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION private.burimunsi_auto_candidates(text),private.burimunsi_native_work_candidates(uuid,integer),private.burimunsi_native_sms_post_candidates(integer),private.burimunsi_native_sms_post_retry(text,text),private.burimunsi_native_sms_post_defer(text,integer) TO collect_runtime;
  CREATE FUNCTION private.test_plan(text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$ BEGIN RETURN private.burimunsi_auto_snapshot($1);END $$;
  CREATE FUNCTION private.test_finish_alias(text,text) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
   DECLARE n integer;BEGIN UPDATE private.burimunsi_auto_sms_jobs SET transaction_id=$2,state='completed',relation='duplicate' WHERE source_id=$1;GET DIAGNOSTICS n=ROW_COUNT;RETURN n;END $$;
  GRANT EXECUTE ON FUNCTION private.test_plan(text),private.test_finish_alias(text,text) TO collect_runtime;`);
 // Fixtures are seeded by the isolated superuser because the real forced-RLS
 // job policy intentionally denies owner-only import outside a reviewed path.
 await root.query(`INSERT INTO private.burimunsi_accounts VALUES('a','g','p',true,false,'admin',ARRAY['sms.read','gateway.manage'],'phone');
  INSERT INTO private.burimunsi_device_grants VALUES('d','g','i',1,true,'internal_receiver');
  INSERT INTO private.burimunsi_device_accounts VALUES('d','g','a');
  INSERT INTO private.burimunsi_observation_consents VALUES('g','a','i','d',1,true);
  INSERT INTO private.burimunsi_scopes VALUES('g',true,NULL,'w');
  INSERT INTO app.collections VALUES('g','active');
  INSERT INTO app.momo_receiving_accounts VALUES('w','active','provider','approved','v1','{}','RWF','Africa/Kigali');
  INSERT INTO app.admin_users VALUES('admin','admin','active');INSERT INTO app.admin_principal_links VALUES('p','admin');
  INSERT INTO app.admin_grants VALUES('p','sms.read'),('p','sms.reveal');
  INSERT INTO app.admin_account_role_capabilities VALUES('admin','sms.read'),('admin','sms.reveal');
  INSERT INTO private.burimunsi_unresolved_observations
   SELECT source,'g','a','p','d','i',1,'fingerprint',encode(sha256(convert_to('{}','UTF8')),'hex'),created,'object','objecthash','v1',
   encode(sha256(convert_to(jsonb_build_array('w','provider','active','approved','v1','{}','RWF','Africa/Kigali')::text,'UTF8')),'hex')
   FROM (VALUES('auto-old',1::bigint),('auto-new',2::bigint)) v(source,created);
  INSERT INTO private.burimunsi_auto_sms_jobs(source_id,collection_id,state,lease_until,next_attempt_at,relation,transaction_id,posting_next_attempt_at,posting_facts,created_at) VALUES
   ('auto-old','g','processing',0,NULL,NULL,NULL,0,NULL,1),('auto-new','g','processing',0,NULL,NULL,NULL,0,NULL,2),
   ('post-old','g','completed',NULL,NULL,'accepted','tx-old',0,NULL,1),('post-alias','g','completed',NULL,NULL,'accepted','tx-old',0,NULL,1),
   ('resolve-alias','g','processing',0,NULL,NULL,NULL,0,NULL,1),
   ('post-new','g','completed',NULL,NULL,'accepted','tx-new',0,NULL,2);
  INSERT INTO private.burimunsi_native_financial_work VALUES
   ('00000000-0000-4000-8000-000000000001','work-old','tx-old','g','queued',0,1,NULL),
   ('00000000-0000-4000-8000-000000000003','work-alias','tx-old','g','queued',0,1,NULL),
   ('00000000-0000-4000-8000-000000000002','work-new','tx-new','g','queued',0,2,NULL);
  INSERT INTO app.momo_transactions VALUES('tx-old','incoming_receipt',0,'unallocated'),('tx-new','incoming_receipt',0,'unallocated');
  INSERT INTO app.momo_financial_links VALUES('tx-already-linked','payment-historical');
  INSERT INTO app.ledger_entries VALUES('already-imported','payment-historical','contribution');
  INSERT INTO private.collect_imported_native_history VALUES('auto-old',NULL),('post-old','tx-old'),('work-old',NULL),('linked-old','tx-already-linked');
 `);
 const guard=await read('scripts/supabase/cloud-release/imported-history-guard.sql');
 // A changed predecessor must fail atomically rather than patch unknown code.
 await owner.query('BEGIN');
 await owner.query("CREATE OR REPLACE FUNCTION private.burimunsi_native_sms_post_candidates(p_limit integer) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$ SELECT '[]'::jsonb $$");
 await assert.rejects(()=>owner.query(guard),e=>e.code==='55000'&&e.message.startsWith('imported_history_guard_predecessor_changed'));checks++;
 await owner.query('ROLLBACK');
 // The integration sequence imports original financial rows and marker first,
 // then installs this guard before the SAME owner transaction commits.
 await owner.query('BEGIN');
 await owner.query("INSERT INTO app.momo_financial_links VALUES('tx-import-together','payment-import-together')");
 await owner.query("INSERT INTO app.ledger_entries VALUES('ledger-import-together','payment-import-together','contribution')");
 await owner.query("INSERT INTO private.collect_imported_native_history VALUES('source-import-together','tx-import-together')");
 await owner.query(guard);await owner.query('COMMIT');
 assert.equal((await root.query("SELECT count(*)::int n FROM pg_trigger WHERE tgname='collect_imported_native_history_guard' AND tgenabled='A'")).rows[0].n,4);checks++;
 await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
 await owner.query("SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','g',true),set_config('burimunsi.native_receipt_frame','1',true)");
 const old=async(sql,args=[])=>{await assert.rejects(()=>owner.query(sql,args),e=>e.code==='55000'&&e.message==='imported_native_history_blocked');checks++;await owner.query('ROLLBACK TO SAVEPOINT test');};
 await owner.query('SAVEPOINT test');await old("SELECT private.test_plan('auto-old')");
 await old("SELECT private.test_plan('post-alias')");
 let rows=(await owner.query("SELECT source_id FROM private.burimunsi_auto_candidates('g') ORDER BY source_id")).rows;
 assert.deepEqual(rows.map(r=>r.source_id),['auto-new']);checks++;
 rows=(await owner.query('SELECT private.burimunsi_native_sms_post_candidates(1) v')).rows;
 assert.deepEqual(rows[0].v,[{groupId:'g',sourceId:'post-new'}]);checks++;
 rows=(await owner.query("SELECT private.burimunsi_native_work_candidates('00000000-0000-4000-8000-000000000000',1) v")).rows;
 assert.deepEqual(rows[0].v,['00000000-0000-4000-8000-000000000002']);checks++;
 await old("SELECT private.burimunsi_native_sms_post_retry('post-old','posting_failed')");
 await old("SELECT private.burimunsi_native_sms_post_defer('post-old',1000)");
 await old("SELECT private.burimunsi_native_sms_post_retry('post-alias','posting_failed')");
 await old("UPDATE private.burimunsi_native_financial_work SET state='leased' WHERE source_id='work-old'");
 await old("UPDATE private.burimunsi_native_financial_work SET state='leased' WHERE source_id='work-alias'");
 assert.equal((await owner.query("SELECT private.test_finish_alias('resolve-alias','tx-old') v")).rows[0].v,1);checks++;
 // Keep the new alias and hold it from all subsequent planning.
 await owner.query('RELEASE SAVEPOINT test');await owner.query('SAVEPOINT test');
 await old("SELECT private.test_plan('resolve-alias')");
 await old("INSERT INTO app.momo_financial_links VALUES('tx-old','would-post')");
 await old("INSERT INTO app.ledger_entries VALUES('would-reconcile','payment-historical','contribution')");
 await owner.query("INSERT INTO app.ledger_entries VALUES('allowed-reversal','payment-historical','reversal')");checks++;
 assert.equal((await owner.query("SELECT private.burimunsi_native_sms_post_defer('post-new',1000) v")).rows[0].v,true);checks++;
 await owner.query("INSERT INTO app.momo_financial_links VALUES('tx-new','payment-new')");checks++;
 await owner.query('ROLLBACK');
 // If a direct posting writes a contribution before its link, link denial must
 // roll the whole transaction back rather than leave an unlinked credit.
 await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
 await owner.query("INSERT INTO app.ledger_entries VALUES('partial-credit','unlinked-payment','contribution')");
 await assert.rejects(()=>owner.query("INSERT INTO app.momo_financial_links VALUES('tx-old','unlinked-payment')"),e=>e.code==='55000');
 await owner.query('ROLLBACK');
 assert.equal((await root.query("SELECT count(*)::int n FROM app.ledger_entries WHERE id='partial-credit'")).rows[0].n,0);checks++;
 assert.equal((await root.query("SELECT count(*)::int n FROM app.ledger_entries WHERE id='already-imported'")).rows[0].n,1);checks++;
 assert.equal((await root.query("SELECT count(*)::int n FROM app.ledger_entries WHERE id='ledger-import-together'")).rows[0].n,1);checks++;
 console.log(JSON.stringify({status:'PASS',checks,fixture:'owned-socket-only-pg17',actualPinnedFunctions:true,productionDispatched:false}));
}finally{
 await Promise.allSettled(clients.map(c=>c.end()));
 if(fixture){const result=await fixture.close();assert.equal(result.removed,true);}
 await verifyBinaryPins();
}
