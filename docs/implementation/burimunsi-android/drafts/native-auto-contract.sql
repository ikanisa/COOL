-- SYNTHETIC ONLY: run after reviewed chain, private-quarantine draft and operator seed.
-- The lease placeholders are injected by the same isolated full-chain harness.
-- This checks authority/consent; synthetic journal rows are not provider evidence.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
CREATE FUNCTION pg_temp.check_observation(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'observation qualification: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.expect_observation(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'observation SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'observation expected SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.create_pin(account uuid,installation uuid,token_digit text,device_digit text) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT private.burimunsi_pin_create_session('buri-qualification-group',account,installation,'internal_receiver',
  encode(sha256(convert_to(repeat(device_digit,64),'UTF8')),'hex'),1,gen_random_uuid(),
  encode(sha256(convert_to(repeat(token_digit,64),'UTF8')),'hex'),floor(extract(epoch FROM clock_timestamp())*1000)::bigint,
  floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1)
$fn$;
-- Synthetic-only failure diagnostics; no token, body, phone number or private row is printed.
CREATE FUNCTION pg_temp.explain_pin(token_digit text,installation uuid,device_digit text) RETURNS jsonb
 LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'sessionPresent',s.id IS NOT NULL,'linkPresent',l.native_session_id IS NOT NULL,
  'createdAt',s.created_at,'linkCreatedAt',l.created_at,
  'dbNow',floor(extract(epoch FROM clock_timestamp())*1000)::bigint,
  'expiresAt',s.expires_at,'leaseExpiresAt',s.pin_lease_expires_at,
  'sessionNotRevoked',NOT s.revoked,'phonePin',s.auth_method='phone_pin',
  'linkMatches',l.collection_id=s.collection_id AND l.account_id=s.account_id AND l.principal_user_id=s.principal_user_id,
  'accountPresent',a.id IS NOT NULL,'accountActive',a.active AND NOT a.removed,
  'accountMatches',a.principal_user_id=s.principal_user_id AND a.credential_version=s.credential_version AND a.version=l.account_version,
  'userActive',u.access_status='active','grantActive',d.active,
  'grantMatches',d.installation_id=s.installation_id AND d.version=s.grant_version,
  'deviceMatches',d.token_hash=encode(sha256(convert_to(repeat(device_digit,64),'UTF8')),'hex') AND d.profile='internal_receiver',
  'deviceAccountPresent',da.account_id IS NOT NULL,'scopeMatches',scope.version=l.scope_version,
  'collectionActive',c.status='active','snapshotPresent',p.snapshot IS NOT NULL,'snapshotMatches',p.snapshot=l.authority_snapshot
  )), '[]'::jsonb)
 FROM private.burimunsi_sessions s
 LEFT JOIN private.burimunsi_pin_session_links l ON l.native_session_id=s.id
 LEFT JOIN private.burimunsi_accounts a ON a.id=s.account_id AND a.collection_id=s.collection_id
 LEFT JOIN app.users u ON u.id=a.principal_user_id
 LEFT JOIN private.burimunsi_device_grants d ON d.id=s.grant_id AND d.collection_id=s.collection_id
 LEFT JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=a.collection_id
 LEFT JOIN private.burimunsi_scopes scope ON scope.collection_id=s.collection_id
 LEFT JOIN app.collections c ON c.id=scope.collection_id
 LEFT JOIN LATERAL (SELECT private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities) snapshot) p ON true
 WHERE s.installation_id=installation AND s.token_hash=encode(sha256(convert_to(repeat(token_digit,64),'UTF8')),'hex')
$fn$;
CREATE FUNCTION pg_temp.set_pin(token_digit text,installation uuid,device_digit text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
BEGIN
 RETURN private.burimunsi_set_pin_context(repeat(token_digit,64),installation,repeat(device_digit,64),'internal_receiver');
EXCEPTION WHEN insufficient_privilege THEN
 RAISE EXCEPTION 'synthetic session context failed: %',pg_temp.explain_pin(token_digit,installation,device_digit) USING ERRCODE='42501';
END;$fn$;
SELECT pg_temp.check_observation(NOT EXISTS(SELECT 1 FROM app.sms_receipts),'no synthetic canonical receipts before test');
SELECT pg_temp.check_observation(NOT EXISTS(SELECT 1 FROM app.momo_processing_jobs),'no synthetic canonical jobs before test');
UPDATE app.momo_receiving_accounts SET profile_status='approved',profile_version='synthetic-approved-v1',
 profile_json='{"sender_allowlist":["Example Money"],"incoming_prefixes":["Received"],"currency_aliases":["RWF"],"transaction_id_prefixes":["Reference:"],"date_format":"YMD_HMS","utc_offset_minutes":120}'
 WHERE id='buri-qualification-wallet';
UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='buri-qualification-group' AND active_binding_id IS NULL;
CREATE FUNCTION pg_temp.auto_make_due(p_source text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET next_attempt_at=CASE WHEN state='retry' THEN 0 ELSE next_attempt_at END,
  lease_until=CASE WHEN state='processing' THEN 0 ELSE lease_until END WHERE source_id=p_source;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(prior,''),true);
END;$fn$;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT pg_temp.create_pin('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000061','1','2');
SELECT pg_temp.set_pin('1','fe900000-0000-4000-8000-000000000061','2');
SELECT pg_temp.check_observation(private.burimunsi_observation_consent_current()='{ "enabled":false,"generation":0 }'::jsonb,'unbound installation starts without consent');
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_context()','42501');
SELECT pg_temp.check_observation(private.burimunsi_observation_set_consent(true,1)='{ "enabled":true,"generation":1 }'::jsonb,'explicit enable');
SELECT pg_temp.check_observation(private.burimunsi_observation_set_consent(true,1)='{ "enabled":true,"generation":1 }'::jsonb,'identical retry');
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_set_consent(false,1)','40001');
SELECT pg_temp.check_observation(private.burimunsi_observation_set_consent(false,2)='{ "enabled":false,"generation":2 }'::jsonb,'newer disable');
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_set_consent(true,1)','40001');
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_context()','42501');
SELECT pg_temp.check_observation(private.burimunsi_observation_set_consent(true,3)='{ "enabled":true,"generation":3 }'::jsonb,'newer explicit re-enable');
SELECT pg_temp.check_observation(private.burimunsi_observation_context()->>'profile_version'='synthetic-approved-v1','prepared unbound scope serves approved profile');
SELECT pg_temp.check_observation(private.burimunsi_observation_page('','all',40,0)->>'totalCount'='0','new installation has empty own page');
-- Current SMS grants and role ceiling are checked independently of the
-- previously approved native capability; no paired-receiver reader is changed.
SAVEPOINT missing_read;
RESET ROLE;
DELETE FROM app.admin_grants WHERE user_id='f3000000-0000-4000-8000-000000000001' AND permission='sms.read';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_consent_current()','42501');
ROLLBACK TO missing_read;
SAVEPOINT missing_reveal;
RESET ROLE;
DELETE FROM app.admin_grants WHERE user_id='f3000000-0000-4000-8000-000000000001' AND permission='sms.reveal';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.check_observation(private.burimunsi_observation_own('none',false) IS NULL,'read works without reveal grant');
SELECT pg_temp.expect_observation($q$SELECT private.burimunsi_observation_own('none',true)$q$,'42501');
ROLLBACK TO missing_reveal;
-- A staff role cannot capture or read merely by installing the same app.
SELECT pg_temp.create_pin('f7000000-0000-4000-8000-000000000002','fe900000-0000-4000-8000-000000000062','3','4');
SELECT pg_temp.set_pin('3','fe900000-0000-4000-8000-000000000062','4');
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_consent_current()','42501');
-- A second authorized phone gets an independent disabled consent by default.
SELECT pg_temp.create_pin('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000063','5','6');
SELECT pg_temp.set_pin('5','fe900000-0000-4000-8000-000000000063','6') AS first_installation_context;
SELECT pg_temp.check_observation(private.burimunsi_observation_consent_current()='{ "enabled":false,"generation":0 }'::jsonb,'consent is per installation');
SELECT pg_temp.expect_observation('SELECT private.burimunsi_observation_context()','42501');
SELECT pg_temp.check_observation(private.burimunsi_observation_set_consent(true,1)='{ "enabled":true,"generation":1 }'::jsonb,'second phone independently consented');
SELECT pg_temp.set_pin('1','fe900000-0000-4000-8000-000000000061','2');
SELECT pg_temp.check_observation(private.burimunsi_observation_consent_current()='{ "enabled":true,"generation":3 }'::jsonb,'second phone did not replace first consent');
-- Build only a synthetic journal; these rows prove SQL guards, not an actual
-- provider upload or AES verification. All changes are rolled back below.

DO $storage$
DECLARE req uuid:='fe910000-0000-4000-8000-000000000001';ctx jsonb;h text;source text;k text;sc jsonb;
 body_sha text:=repeat('b',64);object_sha text:=repeat('c',64);fingerprint text:=repeat('d',64);result jsonb;
BEGIN
 ctx:=private.burimunsi_observation_context();
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||
  (ctx->>'principalUserId')||E'\n'||req::text,'UTF8')),'hex');
 source:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 k:='sms/'||source;sc:=jsonb_build_object('ownerId',ctx->>'principalUserId','entityId',source,'purpose','sms_receipt');
 PERFORM private.burimunsi_observation_prepare(req,fingerprint,source,ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
  VALUES(k,repeat('a',64),sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,'cipher');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
  VALUES('synthetic-private-observation-1',k,repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)),'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
  VALUES(k,'synthetic-private-observation-1',repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)));
 result:=private.burimunsi_observation_commit(req,fingerprint,source,body_sha,object_sha,4,
  ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 PERFORM pg_temp.check_observation(result->>'sourceId'=source,'private observation committed without canonical source');
 PERFORM pg_temp.check_observation((SELECT sealed_body IS NULL AND cleared_at IS NOT NULL
  FROM private.storage_payload_reservations WHERE object_key=k),'committed private source clears shared pending spool');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_lookup(req,fingerprint)->>'sourceId'=source,'identical request reconciles');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_observation_lookup(%L::uuid,%L)',req,repeat('0',64)),'23505');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_page('','all',40,0)->>'totalCount'='1','own page contains 1 committed source(s)');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_own(source,true)->>'bodySha256'=body_sha,'own source reveal proof');
 PERFORM set_config('qualification.source_1',source,true);
END;$storage$;
DO $storage$
DECLARE req uuid:='fe910000-0000-4000-8000-000000000002';ctx jsonb;h text;source text;k text;sc jsonb;
 body_sha text:=repeat('b',64);object_sha text:=repeat('c',64);fingerprint text:=repeat('9',64);result jsonb;
BEGIN
 ctx:=private.burimunsi_observation_context();
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||
  (ctx->>'principalUserId')||E'\n'||req::text,'UTF8')),'hex');
 source:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 k:='sms/'||source;sc:=jsonb_build_object('ownerId',ctx->>'principalUserId','entityId',source,'purpose','sms_receipt');
 PERFORM private.burimunsi_observation_prepare(req,fingerprint,source,ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
  VALUES(k,repeat('a',64),sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,'cipher');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
  VALUES('synthetic-private-observation-2',k,repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)),'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
  VALUES(k,'synthetic-private-observation-2',repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)));
 result:=private.burimunsi_observation_commit(req,fingerprint,source,body_sha,object_sha,4,
  ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 PERFORM pg_temp.check_observation(result->>'sourceId'=source,'private observation committed without canonical source');
 PERFORM pg_temp.check_observation((SELECT sealed_body IS NULL AND cleared_at IS NOT NULL
  FROM private.storage_payload_reservations WHERE object_key=k),'committed private source clears shared pending spool');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_lookup(req,fingerprint)->>'sourceId'=source,'identical request reconciles');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_observation_lookup(%L::uuid,%L)',req,repeat('0',64)),'23505');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_page('','all',40,0)->>'totalCount'='2','own page contains 2 committed source(s)');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_own(source,true)->>'bodySha256'=body_sha,'own source reveal proof');
 PERFORM set_config('qualification.source_2',source,true);
END;$storage$;
DO $storage$
DECLARE req uuid:='fe910000-0000-4000-8000-000000000003';ctx jsonb;h text;source text;k text;sc jsonb;
 body_sha text:=repeat('b',64);object_sha text:=repeat('c',64);fingerprint text:=repeat('8',64);result jsonb;
BEGIN
 ctx:=private.burimunsi_observation_context();
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||
  (ctx->>'principalUserId')||E'\n'||req::text,'UTF8')),'hex');
 source:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 k:='sms/'||source;sc:=jsonb_build_object('ownerId',ctx->>'principalUserId','entityId',source,'purpose','sms_receipt');
 PERFORM private.burimunsi_observation_prepare(req,fingerprint,source,ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
  VALUES(k,repeat('a',64),sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,'cipher');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
  VALUES('synthetic-private-observation-3',k,repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)),'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
  VALUES(k,'synthetic-private-observation-3',repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)));
 result:=private.burimunsi_observation_commit(req,fingerprint,source,body_sha,object_sha,4,
  ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 PERFORM pg_temp.check_observation(result->>'sourceId'=source,'private observation committed without canonical source');
 PERFORM pg_temp.check_observation((SELECT sealed_body IS NULL AND cleared_at IS NOT NULL
  FROM private.storage_payload_reservations WHERE object_key=k),'committed private source clears shared pending spool');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_lookup(req,fingerprint)->>'sourceId'=source,'identical request reconciles');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_observation_lookup(%L::uuid,%L)',req,repeat('0',64)),'23505');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_page('','all',40,0)->>'totalCount'='3','own page contains 3 committed source(s)');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_own(source,true)->>'bodySha256'=body_sha,'own source reveal proof');
 PERFORM set_config('qualification.source_3',source,true);
END;$storage$;
DO $storage$
DECLARE req uuid:='fe910000-0000-4000-8000-000000000004';ctx jsonb;h text;source text;k text;sc jsonb;
 body_sha text:=repeat('b',64);object_sha text:=repeat('c',64);fingerprint text:=repeat('7',64);result jsonb;
BEGIN
 ctx:=private.burimunsi_observation_context();
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||
  (ctx->>'principalUserId')||E'\n'||req::text,'UTF8')),'hex');
 source:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 k:='sms/'||source;sc:=jsonb_build_object('ownerId',ctx->>'principalUserId','entityId',source,'purpose','sms_receipt');
 PERFORM private.burimunsi_observation_prepare(req,fingerprint,source,ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
  VALUES(k,repeat('a',64),sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,'cipher');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
  VALUES('synthetic-private-observation-4',k,repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)),'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
  VALUES(k,'synthetic-private-observation-4',repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)));
 result:=private.burimunsi_observation_commit(req,fingerprint,source,body_sha,object_sha,4,
  ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 PERFORM pg_temp.check_observation(result->>'sourceId'=source,'private observation committed without canonical source');
 PERFORM pg_temp.check_observation((SELECT sealed_body IS NULL AND cleared_at IS NOT NULL
  FROM private.storage_payload_reservations WHERE object_key=k),'committed private source clears shared pending spool');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_lookup(req,fingerprint)->>'sourceId'=source,'identical request reconciles');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_observation_lookup(%L::uuid,%L)',req,repeat('0',64)),'23505');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_page('','all',40,0)->>'totalCount'='4','own page contains 4 committed source(s)');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_own(source,true)->>'bodySha256'=body_sha,'own source reveal proof');
 PERFORM set_config('qualification.source_4',source,true);
END;$storage$;
DO $storage$
DECLARE req uuid:='fe910000-0000-4000-8000-000000000005';ctx jsonb;h text;source text;k text;sc jsonb;
 body_sha text:=repeat('b',64);object_sha text:=repeat('c',64);fingerprint text:=repeat('6',64);result jsonb;
BEGIN
 ctx:=private.burimunsi_observation_context();
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||
  (ctx->>'principalUserId')||E'\n'||req::text,'UTF8')),'hex');
 source:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 k:='sms/'||source;sc:=jsonb_build_object('ownerId',ctx->>'principalUserId','entityId',source,'purpose','sms_receipt');
 PERFORM private.burimunsi_observation_prepare(req,fingerprint,source,ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
  VALUES(k,repeat('a',64),sc,'sms:'||source||':'||object_sha,'synthetic-key',object_sha,'cipher');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
  VALUES('synthetic-private-observation-5',k,repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)),'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
  VALUES(k,'synthetic-private-observation-5',repeat('e',64),repeat('f',64),6,sc,'{"contentType":"application/octet-stream"}',
   jsonb_build_object('sha256',object_sha,'key_id','synthetic-key','source_fingerprint',repeat('a',64)));
 result:=private.burimunsi_observation_commit(req,fingerprint,source,body_sha,object_sha,4,
  ctx->>'profile_version',ctx->>'profile_sha256',(ctx->>'consentGeneration')::bigint);
 PERFORM pg_temp.check_observation(result->>'sourceId'=source,'private observation committed without canonical source');
 PERFORM pg_temp.check_observation((SELECT sealed_body IS NULL AND cleared_at IS NOT NULL
  FROM private.storage_payload_reservations WHERE object_key=k),'committed private source clears shared pending spool');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_lookup(req,fingerprint)->>'sourceId'=source,'identical request reconciles');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_observation_lookup(%L::uuid,%L)',req,repeat('0',64)),'23505');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_page('','all',40,0)->>'totalCount'='5','own page contains 5 committed source(s)');
 PERFORM pg_temp.check_observation(private.burimunsi_observation_own(source,true)->>'bodySha256'=body_sha,'own source reveal proof');
 PERFORM set_config('qualification.source_5',source,true);
END;$storage$;
-- Switch from the real synthetic phone/PIN admission to a separate admitted
-- jobs context. The original capture, consent and protected-storage metadata
-- remain the same; no PIN actor is fabricated for the worker.
SELECT set_config('collect.fence_admission_id','__JOB_ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__JOB_ADMISSION_EPOCH__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
DO $auto$
DECLARE s1 text:=current_setting('qualification.source_1');s2 text:=current_setting('qualification.source_2');
 s3 text:=current_setting('qualification.source_3');s4 text:=current_setting('qualification.source_4');
 s5 text:=current_setting('qualification.source_5');plan jsonb;collections jsonb;sources jsonb;v jsonb;v2 jsonb;
 fp text;ph text;lease uuid;attempt uuid;facts jsonb;old_lease uuid;i integer;
BEGIN
 collections:=private.burimunsi_auto_collections(10);
 PERFORM pg_temp.check_observation(collections=jsonb_build_array('buri-qualification-group'),'oldest eligible collection is selected');
 sources:=private.burimunsi_auto_sources(10);
 PERFORM pg_temp.check_observation(jsonb_array_length(sources)=5,'all five committed sources are listed');
 plan:=private.burimunsi_auto_plan(s1);fp:=plan->'proof'->>'fingerprint';ph:=plan->'profile'->>'profileSha256';
 PERFORM pg_temp.check_observation(plan->>'kind'='jobs' AND fp=repeat('d',64) AND ph IS NOT NULL
  AND plan->'actor'->>'sessionId' IS NULL AND plan->'proof'->>'object_key'='sms/'||s1,
  'worker plan derives original storage and genuine authority without a fabricated session');
 lease:='cc000000-0000-4000-8000-000000000001';attempt:='cc000000-0000-4000-8000-000000000002';
 v:=private.burimunsi_auto_begin(s1,lease,fp,ph);
 PERFORM pg_temp.check_observation(v->>'state'='processing' AND v->'started'='true'::jsonb,'initial worker claim');
 v:=private.burimunsi_auto_begin(s1,gen_random_uuid(),fp,ph);
 PERFORM pg_temp.check_observation(v->'started'='false'::jsonb,'active lease cannot be stolen');
 PERFORM pg_temp.check_observation(private.burimunsi_auto_dispatch(s1,lease,fp,ph),'dispatch durably precedes provider I/O');
 facts:=jsonb_build_object('event_kind','incoming_receipt','payment_outcome','successful','source_mode','catch_up',
  'provider_transaction_id','SYNTHETIC-TX','original_transaction_id',NULL,'amount_minor',500,'currency','RWF',
  'counterparty_name','Synthetic payer','counterparty_identifier',NULL,'transaction_at',NULL,'transaction_datetime_raw',NULL,
  'fee_minor',NULL,'wallet_balance_after_minor',NULL);
 v:=private.burimunsi_auto_finish(s1,lease,fp,ph,attempt,'synthetic-model','{}'::jsonb,facts);
 PERFORM pg_temp.check_observation(v->>'state'='completed' AND v->>'relation'='accepted' AND v->>'transactionId'=s1,
  'accepted source produces one canonical transaction');
 v2:=private.burimunsi_auto_finish(s1,lease,fp,ph,attempt,'synthetic-model','{}'::jsonb,facts);
 PERFORM pg_temp.check_observation(v2=v,'lost finish response resolves to exact original result');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_auto_finish(%L,%L::uuid,%L,%L,%L::uuid,%L,%L::jsonb,%L::jsonb)',
  s1,lease,fp,ph,attempt,'synthetic-model','{}',(facts||'{"amount_minor":999}'::jsonb)::text),'23505');
 PERFORM pg_temp.check_observation((SELECT count(*)=1 FROM app.momo_transactions WHERE id=s1 AND event_kind='incoming_receipt'
  AND amount_minor=500 AND mode='historical'),'catch-up transaction facts retained as historical');
 -- The same provider reference in a distinct original SMS is linked as a
 -- duplicate. A different direction remains an independent transaction.
 plan:=private.burimunsi_auto_plan(s3);lease:=gen_random_uuid();attempt:=gen_random_uuid();
 fp:=plan->'proof'->>'fingerprint';ph:=plan->'profile'->>'profileSha256';
 v:=private.burimunsi_auto_begin(s3,lease,fp,ph);PERFORM private.burimunsi_auto_dispatch(s3,lease,fp,ph);
 v:=private.burimunsi_auto_finish(s3,lease,fp,ph,attempt,'synthetic-model','{}'::jsonb,facts);
 PERFORM pg_temp.check_observation(v->>'relation'='duplicate' AND v->>'transactionId'=s1,'same transaction reference is not duplicated');
 plan:=private.burimunsi_auto_plan(s2);lease:=gen_random_uuid();attempt:=gen_random_uuid();
 fp:=plan->'proof'->>'fingerprint';ph:=plan->'profile'->>'profileSha256';
 facts:=facts||'{"event_kind":"outgoing","provider_transaction_id":"SYNTHETIC-OUT"}'::jsonb;
 v:=private.burimunsi_auto_begin(s2,lease,fp,ph);PERFORM private.burimunsi_auto_dispatch(s2,lease,fp,ph);
 v:=private.burimunsi_auto_finish(s2,lease,fp,ph,attempt,'synthetic-model','{}'::jsonb,facts);
 PERFORM pg_temp.check_observation(v->>'relation'='accepted' AND EXISTS(SELECT 1 FROM app.momo_transactions
  WHERE id=s2 AND event_kind='outgoing' AND allocation_state='not_applicable'),'outgoing is recorded but not a contribution');
 PERFORM pg_temp.check_observation(NOT EXISTS(SELECT 1 FROM app.ledger_entries),'automatic transaction capture writes no ledger effect');
 -- Provider or parser failures retry automatically beyond five attempts;
 -- exactly repeated retry acknowledgements stay stable and backoff is bounded.
 plan:=private.burimunsi_auto_plan(s4);fp:=plan->'proof'->>'fingerprint';ph:=plan->'profile'->>'profileSha256';
 FOR i IN 1..7 LOOP
  lease:=gen_random_uuid();v:=private.burimunsi_auto_begin(s4,lease,fp,ph);
  PERFORM pg_temp.check_observation(v->'started'='true'::jsonb,'eligible retry claims a new lease');
  PERFORM private.burimunsi_auto_dispatch(s4,lease,fp,ph);
  v:=private.burimunsi_auto_retry(s4,lease,fp,ph,'invalid_output');
  v2:=private.burimunsi_auto_retry(s4,lease,fp,ph,'invalid_output');
  PERFORM pg_temp.check_observation(v=v2 AND v->>'state'='retry' AND (v->>'attemptCount')::integer=i,
   'retry result is durable and exact');
  PERFORM pg_temp.check_observation(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(private.burimunsi_auto_sources(10)) e
   WHERE e->>'sourceId'=s4),'backoff prevents an immediate retry');
  PERFORM pg_temp.auto_make_due(s4);
 END LOOP;
 old_lease:=gen_random_uuid();v:=private.burimunsi_auto_begin(s4,old_lease,fp,ph);
 PERFORM private.burimunsi_auto_dispatch(s4,old_lease,fp,ph);
 PERFORM pg_temp.auto_make_due(s4);
 lease:=gen_random_uuid();v:=private.burimunsi_auto_begin(s4,lease,fp,ph);
 PERFORM pg_temp.check_observation(v->>'state'='processing' AND v->'started'='true'::jsonb,
  'an expired later dispatch is reclaimed automatically');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_auto_dispatch(%L,%L::uuid,%L,%L)',s4,old_lease,fp,ph),'40001');
 plan:=private.burimunsi_auto_plan(s5);fp:=plan->'proof'->>'fingerprint';ph:=plan->'profile'->>'profileSha256';lease:=gen_random_uuid();
 v:=private.burimunsi_auto_begin(s5,lease,fp,ph);
 v:=private.burimunsi_auto_skip_security(s5,lease,fp,ph);
 PERFORM pg_temp.check_observation(v->>'state'='security_message' AND NOT EXISTS(SELECT 1 FROM app.momo_transactions WHERE id=s5),
  'security-only message does not create a financial event');
 PERFORM set_config('burimunsi.collection_id','different-group',true);
 PERFORM pg_temp.check_observation(private.burimunsi_auto_sources(10)='[]'::jsonb,'different collection cannot enumerate these sources');
 PERFORM pg_temp.expect_observation(format('SELECT private.burimunsi_auto_plan(%L)',s1),'40001');
END;$auto$;
-- Re-enter real actor scope and check same-phone original SMS visibility.
SELECT set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT pg_temp.set_pin('1','fe900000-0000-4000-8000-000000000061','2');
SELECT pg_temp.check_observation(private.burimunsi_auto_projection(current_setting('qualification.source_1'))->'canReveal'='true'::jsonb,
 'capturing administrator phone can reveal source');
SELECT pg_temp.set_pin('5','fe900000-0000-4000-8000-000000000063','6');
SELECT pg_temp.check_observation(private.burimunsi_auto_projection(current_setting('qualification.source_1'))->'canReveal'='false'::jsonb,
 'another phone cannot reveal original source');
SELECT pg_temp.set_pin('3','fe900000-0000-4000-8000-000000000062','4');
SELECT pg_temp.check_observation(private.burimunsi_auto_projection(current_setting('qualification.source_1'))->'canReveal'='false'::jsonb,
 'staff cannot reveal original source');
-- Exercise the actual managed Admin visibility function against the synthetic
-- owner and the completed native transaction, with no native PIN context.
SELECT set_config('burimunsi.pin_token','',true),set_config('burimunsi.pin_installation','',true),
 set_config('burimunsi.pin_device','',true),set_config('burimunsi.pin_profile','',true),
 set_config('collect.admin_email_context',jsonb_build_object(
  'admin_id','f4000000-0000-4000-8000-000000000001','cookie_hash',repeat('a',64),
  'origin','https://admin.collect.example','public_session_id','f5000000-0000-4000-8000-000000000001')::text,true),
 set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
  'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1',
  'exp',app.unixepoch()+600,'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',auth_at)))::text,true)
 FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001';
SELECT pg_temp.check_observation(private.burimunsi_admin_transaction_visibility(current_setting('qualification.source_1'))->>'kind'='visible',
 'approved managed owner can see the native transaction');
SELECT pg_temp.check_observation(private.burimunsi_admin_transaction_visibility('synthetic-managed-transaction')->>'kind'='managed',
 'non-native transactions retain the existing managed path');
-- Force deferred origin/receipt constraints before rolling back the fixture.
SET CONSTRAINTS ALL IMMEDIATE;
RESET ROLE;
SELECT pg_temp.check_observation((SELECT count(*) FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') item
 WHERE item->>'relation' IN ('private.burimunsi_auto_sms_jobs','private.burimunsi_native_receipt_origins')
 AND item->>'scope'='unmapped_private' AND item->'blocked'='true'::jsonb)=2,
 'new private relations remain blocked in retention inventory');
SELECT pg_temp.check_observation(private._retention_manifest_schema_v2() IS NOT NULL,
 'retention schema inspection remains available after adding the relations');
SET LOCAL ROLE collect_runtime;
ROLLBACK;
