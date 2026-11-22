// Optional isolated PostgreSQL 17 fixture. This never connects to the live DB.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {loadBuriPostgresFixture} from './postgres-fixture.mjs';

const fixture=loadBuriPostgresFixture();
const migration=new URL('../../../../migrations/20261113130000_burimunsi_native_observation_dedup.sql',import.meta.url);
function sql(input,user='postgres'){
 const r=fixture.run(user,['-q'],input);
 assert.equal(r.status,0,(r.stderr||'fixture failed').slice(-3000));
}

test('real PostgreSQL source reservation preserves exact replay, distinct rows and authorization',{skip:!fixture},()=>{
 sql('CREATE ROLE collect_runtime; CREATE ROLE collect_importer; GRANT collect_runtime TO postgres; GRANT CREATE ON DATABASE postgres TO postgres;', 'supabase_admin');
 sql(`
 CREATE SCHEMA private; GRANT USAGE ON SCHEMA private TO collect_runtime;
 CREATE TABLE private.collect_fence_control(mode text); INSERT INTO private.collect_fence_control VALUES('fenced');
 CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS 'SELECT';
 CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE sql AS 'SELECT';
 CREATE TABLE private.burimunsi_observation_requests(source_id text PRIMARY KEY,collection_id text NOT NULL,account_id uuid NOT NULL,
  principal_user_id text NOT NULL,installation_id uuid NOT NULL,grant_id uuid NOT NULL,grant_version bigint NOT NULL,native_session_id uuid NOT NULL,
  request_id uuid NOT NULL,fingerprint text NOT NULL,initial_profile_version text NOT NULL,initial_profile_sha256 text NOT NULL,
  initial_profile_tuple_sha256 text NOT NULL,initial_consent_generation bigint NOT NULL,created_at bigint NOT NULL,UNIQUE(collection_id,account_id,request_id));
 CREATE TABLE private.burimunsi_unresolved_observations(source_id text PRIMARY KEY,collection_id text NOT NULL,request_id uuid NOT NULL,
  body_sha256 text NOT NULL,object_key text NOT NULL,object_sha256 text NOT NULL,size_bytes bigint NOT NULL,created_at bigint NOT NULL,
  principal_user_id text NOT NULL,fingerprint text NOT NULL);
 CREATE FUNCTION private.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE plpgsql AS $f$
 BEGIN IF current_setting('fixture.allowed',true) IS DISTINCT FROM 'yes' THEN RAISE EXCEPTION 'revoked' USING ERRCODE='42501';END IF;
  RETURN current_setting('fixture.actor')::jsonb;END;$f$;
 CREATE FUNCTION private.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS $$SELECT '{"enabled":true,"generation":1}'::jsonb$$;
 CREATE FUNCTION private.burimunsi_observation_context() RETURNS jsonb LANGUAGE sql AS $$SELECT private.burimunsi_observation_actor(false)||
  jsonb_build_object('profile_version','v1','profile_sha256',repeat('d',64),'profile_tuple_sha256',repeat('e',64),'consentGeneration',1)$$;
 CREATE FUNCTION private.burimunsi_observation_prepare(uuid,text,text,text,text,bigint) RETURNS jsonb LANGUAGE sql AS $$SELECT '{"kind":"legacy-resumable"}'::jsonb$$;
 CREATE FUNCTION private.burimunsi_observation_storage_matches(text,jsonb,text) RETURNS boolean LANGUAGE sql AS
  $$SELECT current_setting('fixture.storage_ok',true) IS DISTINCT FROM 'no'$$;
 CREATE FUNCTION private.fixture_source(p_owner text,p_request uuid) RETURNS text LANGUAGE sql AS $$
  SELECT substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12)
  FROM (SELECT encode(sha256(convert_to('collect.storage.entity.v1'||E'\\n'||'burimunsi.native.observation.v1'||E'\\n'||p_owner||E'\\n'||p_request::text,'UTF8')),'hex') h) q$$;
 GRANT EXECUTE ON FUNCTION private.fixture_source(text,uuid) TO collect_runtime;
 `);
 sql(readFileSync(migration,'utf8'));
 sql(`
 SELECT set_config('fixture.allowed','yes',false);
 SELECT set_config('fixture.actor',jsonb_build_object('collectionId','group-1','accountId','00000000-0000-4000-8000-000000000001',
  'principalUserId','principal-a','installationId','00000000-0000-4000-8000-000000000011','grantId','00000000-0000-4000-8000-000000000021',
  'grantVersion',1,'sessionId','00000000-0000-4000-8000-000000000031')::text,false);
 SET ROLE collect_runtime;
 DO $t$ DECLARE result jsonb;rid uuid:='10000000-0000-4000-8000-000000000001';source text;
 BEGIN source:=private.fixture_source('principal-a',rid);
  IF private.burimunsi_observation_legacy_present() THEN RAISE EXCEPTION 'no legacy request expected';END IF;
  result:=private.burimunsi_observation_key_prepare(repeat('a',64),repeat('b',64),repeat('c',64),rid,repeat('f',64),source,'v1',repeat('d',64),1);
  IF result->>'kind'<>'new' THEN RAISE EXCEPTION 'first source not admitted';END IF;
  result:=private.burimunsi_observation_key_prepare(repeat('a',64),repeat('b',64),repeat('c',64),rid,repeat('f',64),source,'v1',repeat('d',64),1);
  IF result->>'kind'<>'new' THEN RAISE EXCEPTION 'same request not resumable';END IF;
 END;$t$;
 RESET ROLE;
 INSERT INTO private.burimunsi_unresolved_observations VALUES(private.fixture_source('principal-a','10000000-0000-4000-8000-000000000001'),
  'group-1','10000000-0000-4000-8000-000000000001',repeat('c',64),'sms/synthetic',repeat('9',64),100,1,'principal-a',repeat('f',64));
 INSERT INTO private.burimunsi_observation_requests(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
  native_session_id,request_id,fingerprint,initial_profile_version,initial_profile_sha256,initial_profile_tuple_sha256,initial_consent_generation,created_at)
 VALUES('legacy-source','group-1','00000000-0000-4000-8000-000000000001','principal-a','00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000021',1,'00000000-0000-4000-8000-000000000031',
  '10000000-0000-4000-8000-000000000009',repeat('6',64),'v1',repeat('d',64),repeat('e',64),1,1);
 SET ROLE collect_runtime;
 DO $t$ BEGIN
  IF NOT private.burimunsi_observation_legacy_present() THEN RAISE EXCEPTION 'legacy request not detected';END IF;
  IF private.burimunsi_observation_legacy_retry_prepare('10000000-0000-4000-8000-000000000009',repeat('6',64),'legacy-source','v1',repeat('d',64),1)->>'kind'<>'legacy-resumable'
   THEN RAISE EXCEPTION 'admitted legacy retry blocked';END IF;
  BEGIN PERFORM private.burimunsi_observation_legacy_retry_prepare('10000000-0000-4000-8000-000000000008',repeat('6',64),'legacy-new','v1',repeat('d',64),1);
   RAISE EXCEPTION 'new unkeyed request admitted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 END;$t$;
 RESET ROLE;
 SELECT set_config('fixture.actor',jsonb_build_object('collectionId','group-1','accountId','00000000-0000-4000-8000-000000000002',
  'principalUserId','principal-b','installationId','00000000-0000-4000-8000-000000000012','grantId','00000000-0000-4000-8000-000000000022',
  'grantVersion',1,'sessionId','00000000-0000-4000-8000-000000000032')::text,false);
 SET ROLE collect_runtime;
 DO $t$ DECLARE result jsonb;rid uuid:='10000000-0000-4000-8000-000000000002';source text;
 BEGIN source:=private.fixture_source('principal-b',rid);
  result:=private.burimunsi_observation_key_prepare(repeat('a',64),repeat('b',64),repeat('c',64),rid,repeat('7',64),source,'v1',repeat('d',64),1);
  IF result->>'kind'<>'duplicate' OR result->'record'->>'sourceId'<>private.fixture_source('principal-a','10000000-0000-4000-8000-000000000001')
   THEN RAISE EXCEPTION 'cross-account replay not deduplicated';END IF;
  BEGIN PERFORM private.burimunsi_observation_key_prepare(repeat('a',64),repeat('b',64),repeat('8',64),rid,repeat('7',64),source,'v1',repeat('d',64),1);
   RAISE EXCEPTION 'changed content accepted';EXCEPTION WHEN unique_violation THEN NULL;END;
  result:=private.burimunsi_observation_key_prepare(repeat('2',64),repeat('b',64),repeat('c',64),rid,repeat('7',64),source,'v1',repeat('d',64),1);
  IF result->>'kind'<>'new' THEN RAISE EXCEPTION 'distinct row collapsed';END IF;
  BEGIN PERFORM private.burimunsi_observation_key_prepare(repeat('2',64),repeat('b',64),repeat('c',64),
    '10000000-0000-4000-8000-000000000003',repeat('7',64),private.fixture_source('principal-b','10000000-0000-4000-8000-000000000003'),'v1',repeat('d',64),1);
   RAISE EXCEPTION 'pending source acknowledged';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
  PERFORM set_config('fixture.allowed','no',true);
  BEGIN PERFORM private.burimunsi_observation_key_lookup(repeat('a',64),repeat('b',64),repeat('c',64));
   RAISE EXCEPTION 'revoked actor admitted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 END;$t$;
 `);
});
