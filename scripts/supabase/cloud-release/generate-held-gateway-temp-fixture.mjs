// Rollback-only synthetic gateway transaction using the actual gateway scope
// association trigger and draft held-recovery guards. All objects are pg_temp.
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const generated=execFileSync(process.execPath,[fileURLToPath(new URL('./generate-held-recovery-temp-fixture.mjs',import.meta.url))],{encoding:'utf8'});
const marker=generated.indexOf('DO $test$');if(marker<0)throw Error('fixture_setup_missing');
const sql=readFileSync(new URL('../../../supabase/migrations/20261110030800_burimunsi_sms_source_scope.sql',import.meta.url),'utf8');
const start=sql.indexOf('CREATE FUNCTION private.burimunsi_scope_new_capture()');
const end=sql.indexOf('$fn$;',sql.indexOf('$fn$',start)+4);
if(start<0||end<0)throw Error('gateway_scope_trigger_missing');
const gateway=sql.slice(start,end+5).replaceAll('private.','pg_temp.').replaceAll('app.','pg_temp.')
 .replaceAll('734636924058501::bigint','9223372036854773000::bigint');
console.log(generated.slice(0,marker));
console.log(String.raw`
ALTER TABLE pg_temp.sms_receipts ADD COLUMN owner_user_id text,ADD COLUMN object_sha256 text,ADD COLUMN receiver_hash text;
ALTER TABLE pg_temp.momo_receiving_accounts ADD COLUMN receiver_hash text;
ALTER TABLE pg_temp.burimunsi_sms_source_scopes ADD COLUMN receiving_account_id text,ADD COLUMN owner_user_id text,
 ADD COLUMN source_body_sha256 text,ADD COLUMN object_sha256 text,ADD COLUMN binding_id text,ADD COLUMN binding_version bigint,
 ADD COLUMN credential_id text,ADD COLUMN installation_id uuid,ADD COLUMN custodian_account_id uuid,ADD COLUMN grant_id uuid,
 ADD COLUMN grant_version bigint,ADD COLUMN provenance text,ADD COLUMN proof_id text,ADD COLUMN proof_sha256 text;
CREATE TEMP TABLE momo_gateway_credentials(id text,binding_id text,installation_id text,revoked_at text);
CREATE TEMP TABLE momo_gateway_captures(raw_sms_id text,credential_id text);
CREATE TEMP TABLE burimunsi_accounts(id uuid,collection_id text,principal_user_id text,phone text,role text,
 capabilities text[],active boolean,removed boolean);
CREATE TEMP TABLE burimunsi_device_grants(id uuid,version bigint,custodian_account_id uuid,collection_id text,
 installation_id uuid,profile text,active boolean);
CREATE TEMP TABLE burimunsi_device_accounts(grant_id uuid,account_id uuid,collection_id text);
CREATE FUNCTION pg_temp.burimunsi_operator_is_current(text,text,text,text,text[]) RETURNS boolean LANGUAGE sql AS $$SELECT true$$;
`);
console.log(gateway);
console.log(String.raw`
CREATE TRIGGER gateway_scope AFTER INSERT ON pg_temp.momo_gateway_captures FOR EACH ROW EXECUTE FUNCTION pg_temp.burimunsi_scope_new_capture();
INSERT INTO pg_temp.burimunsi_scopes VALUES('group-a','binding-a',1,'receiver-a',true);
INSERT INTO pg_temp.momo_gateway_bindings VALUES('binding-a',1,'receiver-a','owner-a','active');
INSERT INTO pg_temp.momo_receiving_accounts VALUES('receiver-a','active',repeat('9',64));
INSERT INTO pg_temp.momo_gateway_credentials VALUES('credential-a','binding-a','20000000-0000-4000-8000-000000000001',NULL);
INSERT INTO pg_temp.burimunsi_accounts VALUES('10000000-0000-4000-8000-000000000001','group-a','owner-a','synthetic-phone',
 'admin',ARRAY['sms.read','gateway.manage'],true,false);
INSERT INTO pg_temp.burimunsi_device_grants VALUES('30000000-0000-4000-8000-000000000001',1,
 '10000000-0000-4000-8000-000000000001','group-a','20000000-0000-4000-8000-000000000001','internal_receiver',true);
INSERT INTO pg_temp.burimunsi_device_accounts VALUES('30000000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000001','group-a');
DO $gateway_test$
DECLARE held text:='00000000-0000-4000-8000-000000000001';collision text:='00000000-0000-4000-8000-000000000002';
 ordinary text:='00000000-0000-4000-8000-000000000003';t timestamptz:='2026-11-11 12:00:00+00';
BEGIN
 INSERT INTO pg_temp.burimunsi_observation_requests VALUES(held,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
  '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,
  '40000000-0000-4000-8000-000000000002',repeat('b',64),repeat('c',64),repeat('a',64));
 PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||held,'owner-a','group-a',repeat('b',64),repeat('a',64),t,NULL);
 PERFORM pg_temp.burimunsi_sms_recovery_hold(held,'40000000-0000-4000-8000-000000000002',repeat('b',64),repeat('a',64),t);
 -- A gateway writes witness, canonical receipt, capture and job atomically.
 PERFORM pg_temp.collect_sms_witness_reserve('storage','sms/'||collision,'owner-a','group-a',repeat('2',64),repeat('a',64),t,repeat('e',64));
 INSERT INTO pg_temp.sms_receipts(id,object_key,body_sha256,owner_user_id,object_sha256,receiver_hash)
  VALUES(collision,'sms/'||collision,repeat('a',64),'owner-a',repeat('8',64),repeat('9',64));
 INSERT INTO pg_temp.momo_gateway_captures VALUES(collision,'credential-a');
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state) VALUES(collision,'pending');
 IF NOT EXISTS(SELECT 1 FROM pg_temp.burimunsi_sms_source_scopes WHERE source_id=collision AND collection_id='group-a' AND provenance='gateway_capture')
  OR NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=collision AND state='source_unresolved') THEN
  RAISE EXCEPTION 'gateway collision not retained, associated and parked';END IF;
 UPDATE pg_temp.momo_processing_jobs SET state='pending' WHERE raw_sms_id=collision;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=collision AND state='source_unresolved') THEN
  RAISE EXCEPTION 'gateway hold was bypassed';END IF;
 PERFORM pg_temp.collect_sms_witness_reserve('storage','sms/'||ordinary,'owner-a','group-a',repeat('3',64),repeat('3',64),t,repeat('e',64));
 INSERT INTO pg_temp.sms_receipts(id,object_key,body_sha256,owner_user_id,object_sha256,receiver_hash)
  VALUES(ordinary,'sms/'||ordinary,repeat('3',64),'owner-a',repeat('7',64),repeat('9',64));
 INSERT INTO pg_temp.momo_gateway_captures VALUES(ordinary,'credential-a');
 INSERT INTO pg_temp.momo_processing_jobs(raw_sms_id,state) VALUES(ordinary,'pending');
 IF NOT EXISTS(SELECT 1 FROM pg_temp.burimunsi_sms_source_scopes WHERE source_id=ordinary AND collection_id='group-a')
  OR NOT EXISTS(SELECT 1 FROM pg_temp.momo_processing_jobs WHERE raw_sms_id=ordinary AND state='pending') THEN
  RAISE EXCEPTION 'unrelated gateway source was affected';END IF;
 RAISE NOTICE 'synthetic gateway association and parked job passed';
END;$gateway_test$;
ROLLBACK;
`);
