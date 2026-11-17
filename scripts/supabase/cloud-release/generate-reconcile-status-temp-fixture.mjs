// Emits one rollback-only SQL fixture. It creates only pg_temp objects and uses
// synthetic rows; it neither reads nor locks application tables. Run in a
// disposable session. This checks PostgreSQL execution, not production RLS.
import {readFileSync} from 'node:fs';
const migration=new URL('../../../supabase/migrations/20261117180000_burimunsi_observation_reconcile_status.sql',import.meta.url);
const text=readFileSync(migration,'utf8');
const start=text.indexOf('CREATE FUNCTION private.burimunsi_observation_reconcile_status()');
const end=text.indexOf('$fn$;',text.indexOf('$fn$',start)+4);
if(start<0||end<0)throw Error('fixture_source_not_found');
const fn=text.slice(start,end+5).replaceAll('private.','pg_temp.').replaceAll('app.sms_receipts','pg_temp.sms_receipts');
const limited=fn.replace('pg_temp.burimunsi_observation_reconcile_status()',
 'pg_temp.burimunsi_observation_reconcile_status_small()').replaceAll('LIMIT 100001','LIMIT 3').replaceAll('>100000','>2');
console.log(String.raw`
BEGIN;
CREATE TEMP TABLE burimunsi_observation_requests(source_id text PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,
 installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,source_key text);
CREATE TEMP TABLE burimunsi_unresolved_observations(source_id text PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,
 installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,body_sha256 text,object_key text,object_sha256 text);
CREATE TEMP TABLE storage_put_intents(object_key text PRIMARY KEY,operation_id text,scope jsonb,state text,delete_tombstone boolean,
 upload_unresolved boolean,active_attempt uuid,sha256 text,size bigint,http_metadata jsonb,custom_metadata jsonb);
CREATE TEMP TABLE storage_objects(object_key text PRIMARY KEY,operation_id text,scope jsonb,sha256 text,size bigint,http_metadata jsonb,custom_metadata jsonb);
CREATE TEMP TABLE storage_payload_reservations(object_key text PRIMARY KEY,scope jsonb,aad text,plaintext_sha256 text,key_id text,
 source_fingerprint text,sealed_body text,cleared_at timestamptz);
CREATE TEMP TABLE storage_delete_intents(object_key text PRIMARY KEY,state text);
CREATE TEMP TABLE burimunsi_sms_source_scopes(source_id text PRIMARY KEY,collection_id text,owner_user_id text,source_body_sha256 text,object_sha256 text);
CREATE TEMP TABLE sms_receipts(id text PRIMARY KEY,owner_user_id text,body_sha256 text,object_sha256 text,object_key text);
CREATE FUNCTION pg_temp.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE plpgsql AS $a$
BEGIN
 IF current_setting('fixture.authorized',true) IS DISTINCT FROM 'yes' THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('collectionId',current_setting('fixture.collection',true));
END;$a$;
CREATE FUNCTION pg_temp.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS
 $a$SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes')$a$;
CREATE FUNCTION pg_temp.burimunsi_observation_storage_matches(p_key text,p_scope jsonb,p_plain text) RETURNS boolean LANGUAGE sql AS $a$
 SELECT EXISTS(SELECT 1 FROM pg_temp.burimunsi_unresolved_observations r
  JOIN pg_temp.storage_put_intents i ON i.object_key=r.object_key
  JOIN pg_temp.storage_objects o ON o.object_key=i.object_key AND o.operation_id=i.operation_id
  WHERE r.object_key=p_key AND r.object_sha256=p_plain AND i.scope=p_scope AND o.scope=p_scope
   AND i.state='committed' AND NOT i.delete_tombstone AND NOT i.upload_unresolved AND i.active_attempt IS NULL
   AND i.sha256=o.sha256 AND i.size=o.size AND i.http_metadata=o.http_metadata AND i.custom_metadata=o.custom_metadata
   AND o.custom_metadata->>'sha256'=r.object_sha256
   AND NOT EXISTS(SELECT 1 FROM pg_temp.storage_delete_intents d WHERE d.object_key=r.object_key))
$a$;
`);
console.log(fn);console.log(limited);
console.log(String.raw`
SELECT set_config('fixture.authorized','yes',true),set_config('fixture.consent','yes',true),
 set_config('fixture.collection','group-a',true),set_config('burimunsi.collection_id','group-a',true);
DO $test$
DECLARE v jsonb;base text;prior text;
BEGIN
 v:=pg_temp.burimunsi_observation_reconcile_status();
 IF v->>'groupId'<>'group-a' OR (v->>'hasPending')::boolean OR (v->>'hasRecorded')::boolean
  OR (v->>'recordedCount')::integer<>0 OR (v->>'hasUnmatchedCanonical')::boolean OR length(v->>'revision')<>64
  THEN RAISE EXCEPTION 'empty status incorrect';END IF;
 base:=v->>'revision';
 INSERT INTO pg_temp.burimunsi_observation_requests VALUES('other','group-b','00000000-0000-4000-8000-000000000001','other-user',
  '00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003',1,
  '00000000-0000-4000-8000-000000000004',repeat('f',64),NULL);
 IF pg_temp.burimunsi_observation_reconcile_status()->>'revision'<>base THEN RAISE EXCEPTION 'foreign collection leaked';END IF;
 INSERT INTO pg_temp.burimunsi_observation_requests VALUES('source-a','group-a','10000000-0000-4000-8000-000000000001','synthetic-owner',
  '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,
  '40000000-0000-4000-8000-000000000001',repeat('f',64),NULL);
 v:=pg_temp.burimunsi_observation_reconcile_status();
 IF NOT (v->>'hasPending')::boolean OR (v->>'recordedCount')::integer<>0 OR v->>'revision'=base
  THEN RAISE EXCEPTION 'pending source omitted';END IF;
 INSERT INTO pg_temp.burimunsi_unresolved_observations SELECT source_id,collection_id,account_id,principal_user_id,
  installation_id,grant_id,grant_version,request_id,fingerprint,repeat('b',64),'sms/'||source_id,repeat('c',64)
  FROM pg_temp.burimunsi_observation_requests WHERE source_id='source-a';
 INSERT INTO pg_temp.storage_put_intents VALUES('sms/source-a','synthetic-operation',
  jsonb_build_object('ownerId','synthetic-owner','purpose','sms_receipt','entityId','source-a'),'committed',false,false,NULL,
  repeat('d',64),10,'{"contentType":"application/octet-stream"}'::jsonb,
  jsonb_build_object('sha256',repeat('c',64),'key_id','synthetic-key','source_fingerprint',repeat('e',64)));
 INSERT INTO pg_temp.storage_objects SELECT object_key,operation_id,scope,sha256,size,http_metadata,custom_metadata FROM pg_temp.storage_put_intents;
 INSERT INTO pg_temp.storage_payload_reservations SELECT object_key,scope,'sms:source-a:'||repeat('c',64),repeat('c',64),
  'synthetic-key',repeat('e',64),NULL,clock_timestamp() FROM pg_temp.storage_put_intents;
 v:=pg_temp.burimunsi_observation_reconcile_status();
 IF (v->>'hasPending')::boolean OR NOT (v->>'hasRecorded')::boolean OR (v->>'recordedCount')::integer<>1
  THEN RAISE EXCEPTION 'retained source omitted';END IF;
 prior:=v->>'revision';
 UPDATE pg_temp.storage_payload_reservations SET key_id='changed';
 BEGIN PERFORM pg_temp.burimunsi_observation_reconcile_status();RAISE EXCEPTION 'invalid custody accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 UPDATE pg_temp.storage_payload_reservations SET key_id='synthetic-key',cleared_at=clock_timestamp();
 v:=pg_temp.burimunsi_observation_reconcile_status();IF v->>'revision'=prior THEN RAISE EXCEPTION 'custody revision unchanged';END IF;
 UPDATE pg_temp.burimunsi_unresolved_observations SET collection_id='group-b';
 BEGIN PERFORM pg_temp.burimunsi_observation_reconcile_status();RAISE EXCEPTION 'cross-scope source accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 UPDATE pg_temp.burimunsi_unresolved_observations SET collection_id='group-a';
 INSERT INTO pg_temp.sms_receipts VALUES('source-a','synthetic-owner',repeat('b',64),repeat('c',64),'sms/source-a');
 INSERT INTO pg_temp.burimunsi_sms_source_scopes VALUES('source-a','group-a','synthetic-owner',repeat('b',64),repeat('c',64));
 v:=pg_temp.burimunsi_observation_reconcile_status();
 IF (v->>'hasUnmatchedCanonical')::boolean OR (v->>'recordedCount')::integer<>1
  THEN RAISE EXCEPTION 'same-source canonical counted separately';END IF;
 prior:=v->>'revision';UPDATE pg_temp.sms_receipts SET body_sha256=repeat('9',64) WHERE id='source-a';
 v:=pg_temp.burimunsi_observation_reconcile_status();
 IF NOT (v->>'hasUnmatchedCanonical')::boolean OR v->>'revision'=prior THEN RAISE EXCEPTION 'unmatched canonical missed';END IF;
 PERFORM set_config('fixture.consent','no',true);
 BEGIN PERFORM pg_temp.burimunsi_observation_reconcile_status();RAISE EXCEPTION 'disabled consent accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.consent','yes',true);PERFORM set_config('fixture.authorized','no',true);
 BEGIN PERFORM pg_temp.burimunsi_observation_reconcile_status();RAISE EXCEPTION 'unauthorized actor accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.authorized','yes',true);
 INSERT INTO pg_temp.burimunsi_observation_requests SELECT 'pending-'||n,'group-a',account_id,principal_user_id,
  installation_id,grant_id,grant_version,request_id,fingerprint,NULL
  FROM pg_temp.burimunsi_observation_requests CROSS JOIN generate_series(1,2) n WHERE source_id='source-a';
 BEGIN PERFORM pg_temp.burimunsi_observation_reconcile_status_small();RAISE EXCEPTION 'overflow accepted';
 EXCEPTION WHEN SQLSTATE '54000' THEN NULL;END;
 RAISE NOTICE 'synthetic temporary reconciliation fixture passed';
END;$test$;
-- Timing uses only synthetic temporary rows and is not production latency.
INSERT INTO pg_temp.burimunsi_observation_requests
 SELECT 'bench-'||n,'group-a','10000000-0000-4000-8000-000000000001','synthetic-owner',
  '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,
  ('90000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,repeat('f',64),NULL
 FROM generate_series(1,1000) n;
INSERT INTO pg_temp.burimunsi_unresolved_observations
 SELECT source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,request_id,fingerprint,
  repeat('b',64),'sms/'||source_id,repeat('c',64)
 FROM pg_temp.burimunsi_observation_requests WHERE source_id LIKE 'bench-%';
INSERT INTO pg_temp.storage_put_intents
 SELECT object_key,'operation-'||source_id,jsonb_build_object('ownerId',principal_user_id,'purpose','sms_receipt','entityId',source_id),
  'committed',false,false,NULL,repeat('d',64),10,'{"contentType":"application/octet-stream"}'::jsonb,
  jsonb_build_object('sha256',object_sha256,'key_id','synthetic-key','source_fingerprint',repeat('e',64))
 FROM pg_temp.burimunsi_unresolved_observations WHERE source_id LIKE 'bench-%';
INSERT INTO pg_temp.storage_objects
 SELECT object_key,operation_id,scope,sha256,size,http_metadata,custom_metadata
 FROM pg_temp.storage_put_intents WHERE object_key LIKE 'sms/bench-%';
INSERT INTO pg_temp.storage_payload_reservations
 SELECT i.object_key,i.scope,'sms:'||r.source_id||':'||r.object_sha256,r.object_sha256,'synthetic-key',repeat('e',64),NULL,clock_timestamp()
 FROM pg_temp.storage_put_intents i JOIN pg_temp.burimunsi_unresolved_observations r ON r.object_key=i.object_key
 WHERE i.object_key LIKE 'sms/bench-%';
DO $bench$
DECLARE at_time timestamptz;value jsonb;elapsed_ms numeric;
BEGIN
 at_time:=clock_timestamp();value:=pg_temp.burimunsi_observation_reconcile_status();
 elapsed_ms:=extract(epoch FROM (clock_timestamp()-at_time))*1000;
 IF (value->>'recordedCount')::integer<>1001 THEN RAISE EXCEPTION 'synthetic benchmark source count incorrect';END IF;
 RAISE NOTICE 'synthetic 1001 retained sources: database function % ms',round(elapsed_ms,2);
END;$bench$;
ROLLBACK;
`);
