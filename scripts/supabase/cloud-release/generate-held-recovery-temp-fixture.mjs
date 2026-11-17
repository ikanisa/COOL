// Synthetic, rollback-only PostgreSQL exercise of the actual draft functions.
// It uses only pg_temp objects and a fixture-specific advisory lock; it does
// not read, write or lock application rows. It cannot prove live RLS or races.
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../../../supabase/migrations/20261117210000_burimunsi_held_recovery.sql',import.meta.url),'utf8');
function extract(name){
 const start=source.indexOf(`CREATE FUNCTION private.${name}(`);
 const end=source.indexOf('$fn$;',source.indexOf('$fn$',start)+4);
 if(start<0||end<0)throw Error(`missing function: ${name}`);
 return source.slice(start,end+5).replaceAll('private.','pg_temp.').replaceAll('app.','pg_temp.')
  .replaceAll('734636924058501::bigint','9223372036854773000::bigint');
}
console.log(String.raw`
BEGIN;
CREATE TEMP TABLE collect_sms_witnesses(object_key text PRIMARY KEY,owner_id text,collection_id text,request_digest text,
 body_sha256 text,inbox_received_at timestamptz,storage_fingerprint text,created_at timestamptz DEFAULT clock_timestamp());
CREATE TEMP TABLE burimunsi_recovered_sms_holds(source_id text PRIMARY KEY,object_key text,collection_id text,account_id uuid,
 owner_id text,body_sha256 text,inbox_received_at timestamptz,request_digest text,created_at timestamptz DEFAULT clock_timestamp());
CREATE TEMP TABLE burimunsi_observation_requests(source_id text PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,
 installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,source_key text,source_key_body_sha256 text);
CREATE TEMP TABLE burimunsi_unresolved_observations(source_id text,collection_id text,object_key text,body_sha256 text);
CREATE TEMP TABLE burimunsi_sms_source_scopes(source_id text,collection_id text);
CREATE TEMP TABLE storage_payload_reservations(object_key text,scope jsonb);
CREATE TEMP TABLE storage_put_intents(object_key text,active_attempt uuid,upload_unresolved boolean);
CREATE TEMP TABLE sms_receipts(id text,object_key text,body_sha256 text);
CREATE TEMP TABLE burimunsi_auto_sms_jobs(source_id text);
CREATE TEMP TABLE burimunsi_native_financial_work(source_id text);
CREATE TEMP TABLE momo_processing_jobs(raw_sms_id text,state text DEFAULT 'pending',lease_token text,lease_until bigint,last_error text);
CREATE TEMP TABLE momo_parse_attempts(raw_sms_id text);
CREATE TEMP TABLE momo_transaction_sources(raw_sms_id text,transaction_id text);
CREATE TEMP TABLE burimunsi_transaction_scopes(transaction_id text,collection_id text);
CREATE TEMP TABLE momo_financial_links(transaction_id text,payment_id text);
CREATE TEMP TABLE payments(id text,collection_id text);
CREATE TEMP TABLE burimunsi_scopes(collection_id text,active_binding_id text,binding_version bigint,receiving_account_id text,enabled boolean);
CREATE TEMP TABLE momo_gateway_bindings(id text,version bigint,receiving_account_id text,owner_user_id text,status text);
CREATE TEMP TABLE momo_receiving_accounts(id text,status text);
CREATE FUNCTION pg_temp.collect_fence_assert_write(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $a$
BEGIN
 IF current_setting('fixture.strict_role',true)='yes' AND
  (current_setting('role',true)<>'collect_runtime' OR current_setting('collect.edge_verified',true)<>'true') THEN
  RAISE EXCEPTION 'fixture fence denied' USING ERRCODE='42501';END IF;
END;$a$;
CREATE FUNCTION pg_temp.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE plpgsql AS $a$
BEGIN
 IF current_setting('fixture.authorized',true) IS DISTINCT FROM 'yes' THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('collectionId',current_setting('fixture.collection',true),'principalUserId',current_setting('fixture.owner',true),
 'accountId','10000000-0000-4000-8000-000000000001','installationId','20000000-0000-4000-8000-000000000001',
 'grantId','30000000-0000-4000-8000-000000000001','grantVersion',1);
END;$a$;
CREATE FUNCTION pg_temp.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS
 $a$SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes')$a$;
`);
for(const name of ['collect_sms_witness_reserve','burimunsi_sms_recovery_hold','collect_sms_held_source_guard',
 'collect_sms_recovery_held','collect_sms_recovery_transaction_matches','collect_sms_recovery_scope_guard',
 'collect_sms_recovery_financial_guard','collect_sms_recovery_work_guard','collect_sms_recovery_raw_work_guard'])console.log(extract(name));
console.log(String.raw`
CREATE TRIGGER held_source BEFORE INSERT OR UPDATE ON pg_temp.sms_receipts FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_held_source_guard();
CREATE TRIGGER held_jobs BEFORE INSERT OR UPDATE OR DELETE ON pg_temp.burimunsi_auto_sms_jobs FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_work_guard();
CREATE TRIGGER held_work BEFORE INSERT OR UPDATE OR DELETE ON pg_temp.burimunsi_native_financial_work FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_work_guard();
CREATE TRIGGER held_jobs BEFORE INSERT OR UPDATE OR DELETE ON pg_temp.momo_processing_jobs FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_raw_work_guard();
CREATE TRIGGER held_attempts BEFORE INSERT OR UPDATE OR DELETE ON pg_temp.momo_parse_attempts FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_raw_work_guard();
CREATE TRIGGER held_sources BEFORE INSERT OR UPDATE OR DELETE ON pg_temp.momo_transaction_sources FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_raw_work_guard();
CREATE TRIGGER held_scope BEFORE INSERT OR UPDATE ON pg_temp.burimunsi_transaction_scopes FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_scope_guard();
CREATE TRIGGER held_financial BEFORE INSERT OR UPDATE ON pg_temp.momo_financial_links FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_financial_guard();
CREATE TRIGGER held_payment BEFORE UPDATE OF collection_id ON pg_temp.payments FOR EACH ROW EXECUTE FUNCTION pg_temp.collect_sms_recovery_financial_guard();
SELECT set_config('fixture.authorized','yes',true),set_config('fixture.consent','yes',true),
 set_config('fixture.collection','group-a',true),set_config('fixture.owner','owner-a',true),
 set_config('collect.fence_admission_id','40000000-0000-4000-8000-000000000001',true),
 set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',repeat('f',64),true);
DO $test$
DECLARE a text:='00000000-0000-4000-8000-000000000001';b text:='00000000-0000-4000-8000-000000000002';
 c text:='00000000-0000-4000-8000-000000000003';d text:='00000000-0000-4000-8000-000000000004';
 e text:='00000000-0000-4000-8000-000000000006';
 f text:='00000000-0000-4000-8000-000000000007';
 pre text:='00000000-0000-4000-8000-000000000008';
 other text:='00000000-0000-4000-8000-000000000009';
 linked text:='00000000-0000-4000-8000-000000000010';
 t timestamptz:='2026-11-11 12:00:00+00';
BEGIN
 -- An unscoped member receipt is not evidence about any collection.
 PERFORM pg_temp.collect_sms_witness_reserve('storage','sms/'||d,'member-owner',NULL,repeat('d',64),repeat('a',64),NULL,repeat('e',64));
 -- This transaction was fully parsed while unscoped, before the later hold.
 INSERT INTO pg_temp.sms_receipts VALUES(pre,'sms/'||pre,repeat('a',64));
 INSERT INTO pg_temp.momo_transaction_sources(raw_sms_id,transaction_id) VALUES(pre,'parsed-before-hold');
 INSERT INTO pg_temp.burimunsi_observation_requests VALUES(a,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
  '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,
  '40000000-0000-4000-8000-000000000002',repeat('b',64),repeat('c',64),repeat('a',64));
 PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||a,'owner-a','group-a',repeat('b',64),repeat('a',64),t,NULL);
 PERFORM pg_temp.burimunsi_sms_recovery_hold(a,'40000000-0000-4000-8000-000000000002',repeat('b',64),repeat('a',64),t);
 PERFORM pg_temp.burimunsi_sms_recovery_hold(a,'40000000-0000-4000-8000-000000000002',repeat('b',64),repeat('a',64),t);
 -- Later association cannot make the earlier parsed source post in group A.
 BEGIN INSERT INTO pg_temp.burimunsi_transaction_scopes VALUES('parsed-before-hold','group-a');
  RAISE EXCEPTION 'late matching transaction scope accepted';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.burimunsi_transaction_scopes VALUES('parsed-before-hold','group-b');
 INSERT INTO pg_temp.payments VALUES('payment-a','group-a'),('payment-b','group-b');
 BEGIN INSERT INTO pg_temp.momo_financial_links VALUES('parsed-before-hold','payment-a');
  RAISE EXCEPTION 'late matching financial link accepted';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.momo_financial_links VALUES('parsed-before-hold','payment-b');
 BEGIN UPDATE pg_temp.payments SET collection_id='group-a' WHERE id='payment-b';
  RAISE EXCEPTION 'linked payment moved into held collection';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 -- Association/link before source insertion is blocked too, under the same
 -- global lock. Distinct bodies and groups remain eligible.
 INSERT INTO pg_temp.burimunsi_transaction_scopes VALUES('scope-before-source','group-a');
 BEGIN INSERT INTO pg_temp.momo_transaction_sources VALUES(pre,'scope-before-source');
  RAISE EXCEPTION 'held body attached after transaction scope';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.momo_financial_links VALUES('link-before-source','payment-a');
 BEGIN INSERT INTO pg_temp.momo_transaction_sources VALUES(pre,'link-before-source');
  RAISE EXCEPTION 'held body attached after financial link';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.sms_receipts VALUES(other,'sms/'||other,repeat('9',64));
 INSERT INTO pg_temp.momo_transaction_sources VALUES(other,'different-body');
 INSERT INTO pg_temp.burimunsi_transaction_scopes VALUES('different-body','group-a');
 INSERT INTO pg_temp.momo_financial_links VALUES('different-body','payment-a');
 BEGIN PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||linked,'owner-a','group-a',repeat('1',64),repeat('9',64),t,NULL);
  RAISE EXCEPTION 'existing scoped or linked transaction allowed recovery';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.burimunsi_unresolved_observations VALUES(a,'group-a','sms/'||a,repeat('a',64));
 BEGIN PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||b,'owner-a','group-a',repeat('2',64),repeat('a',64),t+interval '1 day',NULL);
  RAISE EXCEPTION 'same-group equal-body recovery accepted';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 -- This source may be captured normally; status must later flag association.
 PERFORM pg_temp.collect_sms_witness_reserve('native','sms/'||b,'owner-a','group-a',repeat('2',64),repeat('a',64),t+interval '1 day',NULL);
 INSERT INTO pg_temp.sms_receipts VALUES(b,'sms/'||b,repeat('a',64));
 BEGIN INSERT INTO pg_temp.sms_receipts VALUES(a,'sms/'||a,repeat('a',64));
  RAISE EXCEPTION 'held source became canonical';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN INSERT INTO pg_temp.sms_receipts VALUES(a,'sms/'||c,repeat('a',64));
  RAISE EXCEPTION 'held id became canonical with another object key';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN INSERT INTO pg_temp.burimunsi_auto_sms_jobs VALUES(a);RAISE EXCEPTION 'held source entered automatic jobs';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN INSERT INTO pg_temp.burimunsi_native_financial_work VALUES(a);RAISE EXCEPTION 'held source entered financial work';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state) VALUES(a,'pending');
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=a AND state='source_unresolved'
  AND lease_token IS NULL AND lease_until IS NULL AND last_error='sms_recovery_financial_hold') THEN
  RAISE EXCEPTION 'held source not parked';END IF;
 UPDATE pg_temp.momo_processing_jobs SET state='pending' WHERE raw_sms_id=a;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=a AND state='source_unresolved') THEN
  RAISE EXCEPTION 'held source was unparked';END IF;
 BEGIN INSERT INTO pg_temp.momo_parse_attempts VALUES(a);RAISE EXCEPTION 'held source entered parse attempts';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN INSERT INTO pg_temp.momo_transaction_sources(raw_sms_id) VALUES(a);RAISE EXCEPTION 'held source entered transaction sources';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN INSERT INTO pg_temp.burimunsi_auto_sms_jobs VALUES(b);RAISE EXCEPTION 'same-group equal body entered job';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state) VALUES(b,'pending');
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=b AND state='source_unresolved') THEN
  RAISE EXCEPTION 'same-group equal body was not parked';END IF;
 PERFORM pg_temp.collect_sms_witness_reserve('native','sms/'||e,'owner-a','group-a',repeat('6',64),repeat('6',64),t,NULL);
 INSERT INTO pg_temp.burimunsi_auto_sms_jobs VALUES(e);
 BEGIN UPDATE pg_temp.burimunsi_auto_sms_jobs SET source_id=a WHERE source_id=e;RAISE EXCEPTION 'held source updated into job';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 -- Cross-group equal bodies are independent and must not disclose existence.
 PERFORM set_config('fixture.collection','group-b',true);PERFORM set_config('fixture.owner','owner-b',true);
 PERFORM pg_temp.collect_sms_witness_reserve('native','sms/'||c,'owner-b','group-b',repeat('3',64),repeat('a',64),t,NULL);
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state) VALUES(c,'pending');
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=c AND state='pending') THEN
  RAISE EXCEPTION 'foreign source was parked';END IF;
 -- Unscoped member evidence is unaffected until verified same-group scope.
 IF pg_temp.collect_sms_recovery_held(d) THEN RAISE EXCEPTION 'unscoped member source was restricted';END IF;
 INSERT INTO pg_temp.sms_receipts VALUES(d,'sms/'||d,repeat('a',64));
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state) VALUES(d,'pending');
 INSERT INTO pg_temp.burimunsi_sms_source_scopes VALUES(d,'group-a');
 IF NOT pg_temp.collect_sms_recovery_held(d) THEN RAISE EXCEPTION 'verified same-group association was not restricted';END IF;
 UPDATE pg_temp.momo_processing_jobs SET state='processing',lease_token='lease' WHERE raw_sms_id=d;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=d AND state='source_unresolved' AND lease_token IS NULL)
  THEN RAISE EXCEPTION 'late-associated pending source was not parked';END IF;
 BEGIN INSERT INTO pg_temp.momo_transaction_sources(raw_sms_id) VALUES(d);RAISE EXCEPTION 'newly scoped equal body entered transaction source';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 PERFORM pg_temp.collect_sms_witness_reserve('storage','sms/'||f,'member-owner',NULL,repeat('7',64),repeat('a',64),NULL,repeat('e',64));
 INSERT INTO pg_temp.sms_receipts VALUES(f,'sms/'||f,repeat('a',64));
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state,lease_token,lease_until) VALUES(f,'processing','lease',123);
 INSERT INTO pg_temp.burimunsi_sms_source_scopes VALUES(f,'group-a');
 UPDATE pg_temp.momo_processing_jobs SET last_error='attempted-update' WHERE raw_sms_id=f;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=f AND state='needs_review'
  AND lease_token IS NULL AND last_error='sms_recovery_financial_hold_unknown') THEN
  RAISE EXCEPTION 'in-flight late association did not require review';END IF;
 BEGIN PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||d,'owner-b','group-a',repeat('3',64),repeat('1',64),t,NULL);
  RAISE EXCEPTION 'wrong collection accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.authorized','no',true);
 BEGIN PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||d,'owner-b','group-b',repeat('3',64),repeat('1',64),t,NULL);
  RAISE EXCEPTION 'unauthorized recovery accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.authorized','yes',true);PERFORM set_config('fixture.consent','no',true);
 BEGIN PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||d,'owner-b','group-b',repeat('3',64),repeat('1',64),t,NULL);
  RAISE EXCEPTION 'disabled consent accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF (SELECT count(*) FROM pg_temp.burimunsi_recovered_sms_holds)<>1 THEN RAISE EXCEPTION 'hold retry not idempotent';END IF;
 RAISE NOTICE 'synthetic scoped recovery and financial guards passed';
END;$test$;
-- The fixture mirrors the relevant private-table ACL and definer call shape.
-- It does not attest the ACLs or RLS policies of any production relation.
ALTER TABLE pg_temp.collect_sms_witnesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE pg_temp.collect_sms_witnesses FORCE ROW LEVEL SECURITY;
CREATE POLICY fixture_witness_frame ON pg_temp.collect_sms_witnesses TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('collect.sms_witness_frame',true)='1')
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('collect.sms_witness_frame',true)='1');
DO $grant$
DECLARE ns text;
BEGIN
 SELECT nspname INTO STRICT ns FROM pg_namespace WHERE oid=pg_my_temp_schema();
 EXECUTE format('GRANT USAGE ON SCHEMA %I TO collect_runtime',ns);
END;$grant$;
REVOKE ALL ON pg_temp.collect_sms_witnesses FROM PUBLIC,collect_runtime;
REVOKE ALL ON FUNCTION pg_temp.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text) FROM PUBLIC,collect_runtime;
REVOKE ALL ON FUNCTION pg_temp.collect_sms_recovery_held(text) FROM PUBLIC,collect_runtime;
GRANT EXECUTE ON FUNCTION pg_temp.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text) TO collect_runtime;
SELECT set_config('fixture.strict_role','yes',true),set_config('fixture.consent','yes',true),
 set_config('fixture.collection','group-b',true),set_config('fixture.owner','owner-b',true),
 set_config('collect.edge_verified','true',true);
SET LOCAL ROLE collect_runtime;
DO $role_test$
BEGIN
 IF current_user<>'collect_runtime' THEN RAISE EXCEPTION 'fixture role not applied';END IF;
 BEGIN PERFORM count(*) FROM pg_temp.collect_sms_witnesses;RAISE EXCEPTION 'runtime directly read witness';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM pg_temp.collect_sms_recovery_held('00000000-0000-4000-8000-000000000001');RAISE EXCEPTION 'runtime called private guard';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM pg_temp.collect_sms_witness_reserve('native','sms/00000000-0000-4000-8000-000000000005',
  'owner-b','group-b',repeat('5',64),repeat('5',64),'2026-11-11 12:00:00+00',NULL);
 RAISE NOTICE 'synthetic runtime role and definer permissions passed';
END;$role_test$;
ROLLBACK;
`);
