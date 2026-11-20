// Print one rollback-only PostgreSQL fixture. It creates pg_temp objects and
// synthetic rows only. The function body is taken directly from the migration;
// substitute authorization/custody stubs do not prove live permission grants.
import {readFileSync} from 'node:fs';
const migration=new URL('../../../supabase/migrations/20261117190000_burimunsi_legacy_reconcile.sql',import.meta.url);
const source=readFileSync(migration,'utf8');
const start=source.indexOf('CREATE FUNCTION private.burimunsi_observation_legacy_candidates(');
const end=source.indexOf('$fn$;',source.indexOf('$fn$',start)+4);
if(start<0||end<0)throw new Error('fixture_source_not_found');
const fn=source.slice(start,end+5).replaceAll('private.','pg_temp.');
console.log(String.raw`
BEGIN;
CREATE TEMP TABLE collect_imported_native_history(source_id text,collection_id text,request_id uuid,
 body_sha256 text,object_sha256 text,source_fingerprint text);
CREATE TEMP TABLE burimunsi_native_receipt_origins(source_id text,collection_id text,account_id uuid,principal_user_id text,
 installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,body_sha256 text,object_sha256 text);
CREATE TEMP TABLE collect_migration_actor_lineage(source_actor_id text,cloud_primary_id text);
CREATE TEMP TABLE burimunsi_observation_requests(source_id text,collection_id text,account_id uuid,principal_user_id text,
 installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,source_key text);
CREATE TEMP TABLE fixture_financial_effects(marker text);
CREATE FUNCTION pg_temp.burimunsi_observation_actor(p_reveal boolean) RETURNS jsonb LANGUAGE plpgsql AS $a$
BEGIN
 IF current_setting('fixture.authorized',true) IS DISTINCT FROM 'yes'
  OR (p_reveal AND current_setting('fixture.reveal',true) IS DISTINCT FROM 'yes') THEN
  RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('collectionId','group-a','accountId','10000000-0000-4000-8000-000000000001',
  'principalUserId','cloud-owner','sessionId','40000000-0000-4000-8000-000000000001');
END;$a$;
CREATE FUNCTION pg_temp.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS
 $a$SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes','generation',1)$a$;
CREATE FUNCTION pg_temp.burimunsi_observation_history_own(p_source text) RETURNS jsonb LANGUAGE plpgsql AS $a$
DECLARE x record;
BEGIN
 IF current_setting('fixture.custody',true) IS DISTINCT FROM 'yes' THEN
  RAISE EXCEPTION 'storage changed' USING ERRCODE='55000';END IF;
 SELECT * INTO x FROM pg_temp.collect_imported_native_history h WHERE h.source_id=p_source;
 IF NOT FOUND THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('sourceId',x.source_id,'id',x.source_id,'requestId',x.request_id,
  'fingerprint',x.source_fingerprint,'bodySha256',x.body_sha256,'object_sha256',x.object_sha256,
  'object_key','sms/'||x.source_id,'size_bytes',12,'createdAt',1,'principalUserId','old-owner',
  'sessionId','40000000-0000-4000-8000-000000000001','consentGeneration',1);
END;$a$;
`);
console.log(fn);
console.log(String.raw`
SELECT set_config('fixture.authorized','yes',true),set_config('fixture.reveal','yes',true),
 set_config('fixture.consent','yes',true),set_config('fixture.custody','yes',true),
 set_config('burimunsi.collection_id','group-a',true);
INSERT INTO pg_temp.collect_migration_actor_lineage VALUES('old-owner','cloud-owner'),('other-owner','other-cloud');
INSERT INTO pg_temp.collect_imported_native_history
 SELECT source_id,collection_id,'50000000-0000-4000-8000-000000000001'::uuid,repeat('b',64),repeat('c',64),repeat('f',64)
 FROM (VALUES('good','group-a'),('foreign-account','group-a'),('foreign-collection','group-b'),
  ('foreign-lineage','group-a'),('keyed','group-a')) x(source_id,collection_id);
INSERT INTO pg_temp.burimunsi_native_receipt_origins
 SELECT h.source_id,h.collection_id,
  CASE WHEN h.source_id='foreign-account' THEN '10000000-0000-4000-8000-000000000002'::uuid
   ELSE '10000000-0000-4000-8000-000000000001'::uuid END,
  CASE WHEN h.source_id='foreign-lineage' THEN 'other-owner' ELSE 'old-owner' END,
  '20000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000001'::uuid,1,
  h.request_id,h.source_fingerprint,h.body_sha256,h.object_sha256 FROM pg_temp.collect_imported_native_history h;
INSERT INTO pg_temp.burimunsi_observation_requests
 SELECT source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
  request_id,fingerprint,CASE WHEN source_id='keyed' THEN repeat('a',64) ELSE NULL END
 FROM pg_temp.burimunsi_native_receipt_origins;
DO $test$
DECLARE v jsonb;
BEGIN
 v:=pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));
 IF jsonb_array_length(v)<>1 OR v->0->>'sourceId'<>'good' THEN RAISE EXCEPTION 'scoped candidate incorrect';END IF;
 IF pg_temp.burimunsi_observation_legacy_candidates(repeat('9',64))<>'[]'::jsonb THEN RAISE EXCEPTION 'empty search incorrect';END IF;
 PERFORM set_config('fixture.reveal','no',true);
 BEGIN PERFORM pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));RAISE EXCEPTION 'reveal bypass';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.reveal','yes',true);PERFORM set_config('fixture.consent','no',true);
 BEGIN PERFORM pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));RAISE EXCEPTION 'consent bypass';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.consent','yes',true);PERFORM set_config('fixture.custody','no',true);
 BEGIN PERFORM pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));RAISE EXCEPTION 'custody bypass';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 PERFORM set_config('fixture.custody','yes',true);
 UPDATE pg_temp.burimunsi_observation_requests SET fingerprint=repeat('e',64) WHERE source_id='good';
 BEGIN PERFORM pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));RAISE EXCEPTION 'changed lineage accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 UPDATE pg_temp.burimunsi_observation_requests SET fingerprint=repeat('f',64) WHERE source_id='good';
 DELETE FROM pg_temp.burimunsi_observation_requests WHERE source_id='good';
 BEGIN PERFORM pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));RAISE EXCEPTION 'pending candidate accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 INSERT INTO pg_temp.burimunsi_observation_requests SELECT source_id,collection_id,account_id,principal_user_id,installation_id,
  grant_id,grant_version,request_id,fingerprint,NULL FROM pg_temp.burimunsi_native_receipt_origins WHERE source_id='good';
 INSERT INTO pg_temp.collect_imported_native_history SELECT 'extra-'||n,collection_id,request_id,body_sha256,object_sha256,source_fingerprint
  FROM pg_temp.collect_imported_native_history CROSS JOIN generate_series(1,4) n WHERE source_id='good';
 INSERT INTO pg_temp.burimunsi_native_receipt_origins SELECT 'extra-'||n,collection_id,account_id,principal_user_id,installation_id,
  grant_id,grant_version,request_id,fingerprint,body_sha256,object_sha256 FROM pg_temp.burimunsi_native_receipt_origins
  CROSS JOIN generate_series(1,4) n WHERE source_id='good';
 INSERT INTO pg_temp.burimunsi_observation_requests SELECT source_id,collection_id,account_id,principal_user_id,installation_id,
  grant_id,grant_version,request_id,fingerprint,NULL FROM pg_temp.burimunsi_native_receipt_origins WHERE source_id LIKE 'extra-%';
 BEGIN PERFORM pg_temp.burimunsi_observation_legacy_candidates(repeat('b',64));RAISE EXCEPTION 'candidate limit bypass';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 IF EXISTS(SELECT 1 FROM pg_temp.fixture_financial_effects) THEN RAISE EXCEPTION 'unexpected financial effect';END IF;
 RAISE NOTICE 'synthetic legacy reconciliation SQL fixture passed';
END;$test$;
ROLLBACK;
`);
