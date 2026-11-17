// Synthetic SQL only: exercise the actual acknowledgement function together
// with the original own-source and request lookup functions under a real
// READ ONLY transaction. Objects are pg_temp and no application rows are read.
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const base=execFileSync(process.execPath,[fileURLToPath(new URL('./generate-held-recovery-temp-fixture.mjs',import.meta.url))],{encoding:'utf8'});
const marker=base.indexOf('DO $test$');if(marker<0)throw Error('fixture_setup_missing');
const migration=readFileSync(new URL('../../../supabase/migrations/20261117210000_burimunsi_held_recovery.sql',import.meta.url),'utf8');
const original=readFileSync(new URL('../../../supabase/migrations/20261111121000_burimunsi_private_observations.sql',import.meta.url),'utf8');
function extract(sql,name){
 const start=sql.indexOf(`CREATE FUNCTION private.${name}(`),open=sql.indexOf('$fn$',start),end=sql.indexOf('$fn$;',open+4);
 if(start<0||open<0||end<0)throw Error('fixture_function_missing: '+name);
 return sql.slice(start,end+5).replaceAll('private.','pg_temp.').replaceAll('app.','pg_temp.');
}
console.log(base.slice(0,marker));
console.log(String.raw`
ALTER TABLE pg_temp.burimunsi_observation_requests ADD COLUMN source_key_content_sha256 text,ADD COLUMN initial_consent_generation bigint;
ALTER TABLE pg_temp.burimunsi_unresolved_observations ADD COLUMN account_id uuid,ADD COLUMN principal_user_id text,
 ADD COLUMN installation_id uuid,ADD COLUMN grant_id uuid,ADD COLUMN grant_version bigint,ADD COLUMN request_id uuid,
 ADD COLUMN fingerprint text,ADD COLUMN object_sha256 text,ADD COLUMN size_bytes bigint,ADD COLUMN created_at bigint;
ALTER TABLE pg_temp.storage_put_intents ADD COLUMN operation_id text,ADD COLUMN fingerprint text,ADD COLUMN sha256 text,
 ADD COLUMN size bigint,ADD COLUMN scope jsonb,ADD COLUMN http_metadata jsonb,ADD COLUMN custom_metadata jsonb,
 ADD COLUMN state text,ADD COLUMN delete_tombstone boolean;
ALTER TABLE pg_temp.storage_payload_reservations ADD COLUMN source_fingerprint text,ADD COLUMN aad text,ADD COLUMN key_id text,
 ADD COLUMN plaintext_sha256 text,ADD COLUMN sealed_body text,ADD COLUMN cleared_at timestamptz;
CREATE TEMP TABLE storage_objects(object_key text,operation_id text,fingerprint text,sha256 text,size bigint,
 scope jsonb,http_metadata jsonb,custom_metadata jsonb);
CREATE TEMP TABLE storage_namespace(singleton boolean,origin text,bucket text);
CREATE TEMP TABLE storage_delete_intents(object_key text);
CREATE TEMP TABLE privacy_retention_barriers(subject_id text);
CREATE OR REPLACE FUNCTION pg_temp.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE plpgsql AS $a$
BEGIN
 IF current_setting('fixture.authorized',true) IS DISTINCT FROM 'yes' THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('collectionId',current_setting('fixture.collection',true),'principalUserId',current_setting('fixture.owner',true),
 'accountId',coalesce(nullif(current_setting('fixture.account',true),''),'10000000-0000-4000-8000-000000000001'),
 'sessionId','50000000-0000-4000-8000-000000000001',
 'installationId',coalesce(nullif(current_setting('fixture.installation',true),''),'20000000-0000-4000-8000-000000000001'),
 'grantId','30000000-0000-4000-8000-000000000001','grantVersion',coalesce(nullif(current_setting('fixture.grant_version',true),''),'1')::bigint);
END;$a$;
CREATE OR REPLACE FUNCTION pg_temp.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS
 $a$SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes',
 'generation',coalesce(nullif(current_setting('fixture.consent_generation',true),''),'1')::bigint)$a$;
`);
for(const [sql,name] of [[original,'burimunsi_observation_own'],[original,'burimunsi_observation_lookup'],
 [migration,'burimunsi_sms_recovery_ack_snapshot']])console.log(extract(sql,name));
console.log(String.raw`
DO $seed$
DECLARE req uuid:='40000000-0000-4000-8000-000000000002';hash text;source text;expected_scope jsonb;custom jsonb;t timestamptz:='2026-11-11 12:00:00+00';
BEGIN
 hash:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||'owner-a'||E'\n'||req::text,'UTF8')),'hex');
 source:=substr(hash,1,8)||'-'||substr(hash,9,4)||'-5'||substr(hash,14,3)||'-8'||substr(hash,18,3)||'-'||substr(hash,21,12);
 INSERT INTO pg_temp.burimunsi_observation_requests(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,
  grant_version,request_id,fingerprint,source_key,source_key_body_sha256,source_key_content_sha256,initial_consent_generation)
 VALUES(source,'group-a','10000000-0000-4000-8000-000000000001','owner-a','20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',1,req,repeat('b',64),repeat('d',64),repeat('a',64),repeat('f',64),1);
 PERFORM pg_temp.collect_sms_witness_reserve('recovery','sms/'||source,'owner-a','group-a',repeat('b',64),repeat('a',64),t,NULL);
 PERFORM pg_temp.burimunsi_sms_recovery_hold(source,req,repeat('b',64),repeat('a',64),t);
 PERFORM pg_temp.collect_sms_witness_reserve('storage','sms/'||source,'owner-a','group-a',repeat('b',64),repeat('a',64),t,repeat('e',64));
 INSERT INTO pg_temp.burimunsi_unresolved_observations(source_id,collection_id,object_key,body_sha256,account_id,principal_user_id,
  installation_id,grant_id,grant_version,request_id,fingerprint,object_sha256,size_bytes,created_at)
 VALUES(source,'group-a','sms/'||source,repeat('a',64),'10000000-0000-4000-8000-000000000001','owner-a',
  '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,req,repeat('b',64),repeat('c',64),10,1);
 expected_scope:=jsonb_build_object('ownerId','owner-a','purpose','sms_receipt','entityId',source);
 custom:=jsonb_build_object('sha256',repeat('c',64),'key_id','synthetic-key','source_fingerprint',repeat('e',64));
 INSERT INTO pg_temp.storage_put_intents(object_key,active_attempt,upload_unresolved,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state,delete_tombstone)
 VALUES('sms/'||source,NULL,false,repeat('1',64),repeat('2',64),repeat('3',64),20,expected_scope,'{"contentType":"application/octet-stream"}',custom,'committed',false);
 INSERT INTO pg_temp.storage_objects SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata FROM pg_temp.storage_put_intents;
 INSERT INTO pg_temp.storage_payload_reservations(object_key,scope,source_fingerprint,aad,key_id,plaintext_sha256,sealed_body,cleared_at)
 VALUES('sms/'||source,expected_scope,repeat('e',64),'sms:'||source||':'||repeat('c',64),'synthetic-key',repeat('c',64),NULL,clock_timestamp());
 INSERT INTO pg_temp.storage_namespace VALUES(true,'https://example.invalid','collect-evidence');
 BEGIN PERFORM pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t);
  RAISE EXCEPTION 'read-write acknowledgement accepted';EXCEPTION WHEN SQLSTATE '25006' THEN NULL;END;
END;$seed$;
COMMIT;
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT set_config('fixture.authorized','yes',true),set_config('fixture.consent','yes',true),
 set_config('fixture.collection','group-a',true),set_config('fixture.owner','owner-a',true),
 set_config('collect.fence_admission_id','40000000-0000-4000-8000-000000000001',true),
 set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',repeat('f',64),true);
DO $test$
DECLARE req uuid:='40000000-0000-4000-8000-000000000002';source text;proof jsonb;t timestamptz:='2026-11-11 12:00:00+00';
BEGIN
 SELECT source_id INTO STRICT source FROM pg_temp.burimunsi_observation_requests WHERE request_id=req;
 proof:=pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t);
 IF proof IS NULL OR proof->'record'->>'sourceId'<>source OR proof->'put'->>'state'<>'committed'
  OR proof->'namespace'->>'bucket'<>'collect-evidence' THEN RAISE EXCEPTION 'complete acknowledgement proof missing';END IF;
 IF pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('9',64),repeat('f',64),repeat('a',64),t) IS NOT NULL
  OR pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('9',64),repeat('a',64),t) IS NOT NULL
  OR pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t+interval '1 day') IS NOT NULL
  THEN RAISE EXCEPTION 'changed request acknowledged';END IF;
 PERFORM set_config('fixture.collection','group-b',true);
 IF pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t) IS NOT NULL
  THEN RAISE EXCEPTION 'foreign collection acknowledged';END IF;
 PERFORM set_config('fixture.collection','group-a',true);
 PERFORM set_config('fixture.account','10000000-0000-4000-8000-000000000002',true);
 IF pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t) IS NOT NULL
  THEN RAISE EXCEPTION 'foreign account acknowledged';END IF;
 PERFORM set_config('fixture.account','',true);PERFORM set_config('fixture.installation','20000000-0000-4000-8000-000000000002',true);
 IF pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t) IS NOT NULL
  THEN RAISE EXCEPTION 'foreign installation acknowledged';END IF;
 PERFORM set_config('fixture.installation','',true);PERFORM set_config('fixture.grant_version','2',true);
 IF pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t) IS NOT NULL
  THEN RAISE EXCEPTION 'changed grant acknowledged';END IF;
 PERFORM set_config('fixture.grant_version','',true);PERFORM set_config('fixture.consent_generation','2',true);
 IF pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t) IS NOT NULL
  THEN RAISE EXCEPTION 'changed consent generation acknowledged';END IF;
 PERFORM set_config('fixture.consent_generation','',true);PERFORM set_config('fixture.consent','no',true);
 BEGIN PERFORM pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t);
  RAISE EXCEPTION 'revoked consent acknowledged';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.consent','yes',true);PERFORM set_config('fixture.authorized','no',true);
 BEGIN PERFORM pg_temp.burimunsi_sms_recovery_ack_snapshot(source,req,repeat('b',64),repeat('d',64),repeat('f',64),repeat('a',64),t);
  RAISE EXCEPTION 'revoked authority acknowledged';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 RAISE NOTICE 'synthetic read-only held acknowledgement passed';
END;$test$;
ROLLBACK;
`);
