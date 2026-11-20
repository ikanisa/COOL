-- QUALIFICATION ONLY: disposable fenced PostgreSQL, after operator-seed,
-- native session renewal and passcode rotation migrations. All tokens, PIN
-- hashes and identities are public synthetic test values. SQL proves atomic
-- CAS/authority rotation; service-side PIN verification has separate tests.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
CREATE FUNCTION pg_temp.rotation_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Native passcode rotation: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.rotation_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Native passcode rotation SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Native passcode rotation expected SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.rotation_hash(raw text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
 SELECT encode(sha256(convert_to(raw,'UTF8')),'hex')
$fn$;
CREATE FUNCTION pg_temp.rotation_pin() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $fn$
 SELECT jsonb_build_object('algorithm','pbkdf2-sha256+hmac-v1','pepperId','qualification-only',
  'iterations',600000,'salt',repeat('b',32),'hash',repeat('c',64))
$fn$;
DO $catalog$
DECLARE role_name text;signature text:='private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)';
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_temp.rotation_check(has_function_privilege('collect_runtime',signature,'EXECUTE'),'runtime operation allowed');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
  PERFORM pg_temp.rotation_check(NOT has_function_privilege(role_name,signature,'EXECUTE'),'operation private from '||role_name);
 END LOOP;
END;$catalog$;

-- Both profiles run independently against rolled-back synthetic state. The
-- long-lived predecessor is created with original auth time >5 minutes ago;
-- routine renewal has not faked a fresh PIN event.
SAVEPOINT receiver_profile;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'ff900000-0000-4000-8000-000000000001','internal_receiver',pg_temp.rotation_hash(repeat('2',64)),1,
 'ff000000-0000-4000-8000-000000000001',pg_temp.rotation_hash(repeat('1',64)),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT private.burimunsi_set_pin_context(repeat('1',64),'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver');
SELECT private.burimunsi_pin_claim_custody('buri-qualification-group',(SELECT grant_id FROM private.burimunsi_pin_context()),
 'f7000000-0000-4000-8000-000000000001');
RESET ROLE;
INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,
 token_hash,created_at,expires_at,principal_user_id,auth_method)
 SELECT 'ff000000-0000-4000-8000-000000000002',collection_id,account_id,grant_id,installation_id,credential_version,grant_version,
 pg_temp.rotation_hash(repeat('3',64)),floor(extract(epoch FROM clock_timestamp())*1000)::bigint-301000,
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,principal_user_id,auth_method
 FROM private.burimunsi_sessions WHERE id='ff000000-0000-4000-8000-000000000001';
INSERT INTO private.burimunsi_pin_session_links(native_session_id,collection_id,account_id,principal_user_id,account_version,scope_version,authority_snapshot,created_at)
 SELECT 'ff000000-0000-4000-8000-000000000002',l.collection_id,l.account_id,l.principal_user_id,l.account_version,l.scope_version,l.authority_snapshot,s.created_at
 FROM private.burimunsi_pin_session_links l JOIN private.burimunsi_sessions s ON s.id='ff000000-0000-4000-8000-000000000002'
 WHERE l.native_session_id='ff000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT private.burimunsi_set_pin_context(repeat('3',64),'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver');
SELECT pg_temp.rotation_expect($q$SELECT private.burimunsi_pin_assert_actor(NULL,'buri-qualification-group',NULL,1,300)$q$,'42501');
SELECT pg_temp.rotation_expect($q$SELECT private.burimunsi_pin_rotate_passcode('f7000000-0000-4000-8000-000000000001',
 'ff000000-0000-4000-8000-000000000002',2,1,pg_temp.rotation_pin(),pg_temp.rotation_hash(repeat('4',64)),repeat('5',64),1800000)$q$,'42501');
SELECT pg_temp.rotation_expect($q$SELECT private.burimunsi_pin_rotate_passcode('f7000000-0000-4000-8000-000000000001',
 'ff000000-0000-4000-8000-000000000002',1,1,pg_temp.rotation_pin(),pg_temp.rotation_hash(repeat('2',64)),repeat('5',64),1800000)$q$,'42501');
DO $receiver$
DECLARE result jsonb;replacement record;
BEGIN
 result:=private.burimunsi_pin_rotate_passcode('f7000000-0000-4000-8000-000000000001','ff000000-0000-4000-8000-000000000002',
  1,1,pg_temp.rotation_pin(),pg_temp.rotation_hash(repeat('4',64)),repeat('5',64),1800000);
 PERFORM pg_temp.rotation_check(result->>'rotated'='true','receiver rotated');
 PERFORM pg_temp.rotation_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('3',64),
  'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver')),'old receiver proof revoked');
 SELECT * INTO STRICT replacement FROM private.burimunsi_pin_session_context(repeat('4',64),
  'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver');
 PERFORM pg_temp.rotation_check(replacement.expires_at=(result->>'expiresAt')::bigint AND replacement.profile='internal_receiver',
  'candidate is current receiver session');
 PERFORM pg_temp.rotation_check((SELECT custodian_account_id='f7000000-0000-4000-8000-000000000001'::uuid
  FROM private.burimunsi_device_grants WHERE id=replacement.grant_id),'receiver grant and custody unchanged');
 PERFORM pg_temp.rotation_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('4',64),
  'ff900000-0000-4000-8000-000000000001',repeat('7',64),'internal_receiver')),'candidate requires device secret');
 UPDATE private.burimunsi_sessions SET revoked=true WHERE id=replacement.native_session_id;
 PERFORM pg_temp.rotation_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('4',64),
  'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver')),'candidate logout is final');
END;$receiver$;
ROLLBACK TO receiver_profile;

SAVEPOINT staff_profile;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000002',
 'ff900000-0000-4000-8000-000000000002','staff',pg_temp.rotation_hash(repeat('7',64)),1,
 'ff000000-0000-4000-8000-000000000003',pg_temp.rotation_hash(repeat('6',64)),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT private.burimunsi_set_pin_context(repeat('6',64),'ff900000-0000-4000-8000-000000000002',repeat('7',64),'staff');
DO $staff$
DECLARE result jsonb;replacement record;
BEGIN
 result:=private.burimunsi_pin_rotate_passcode('f7000000-0000-4000-8000-000000000002','ff000000-0000-4000-8000-000000000003',
  1,1,pg_temp.rotation_pin(),pg_temp.rotation_hash(repeat('8',64)),repeat('9',64),1800000);
 SELECT * INTO STRICT replacement FROM private.burimunsi_pin_session_context(repeat('8',64),
  'ff900000-0000-4000-8000-000000000002',repeat('7',64),'staff');
 PERFORM pg_temp.rotation_check(result->>'rotated'='true' AND replacement.profile='staff' AND replacement.role='staff',
  'staff candidate keeps staff profile and role');
 PERFORM pg_temp.rotation_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('6',64),
  'ff900000-0000-4000-8000-000000000002',repeat('7',64),'staff')),'old staff proof revoked');
 PERFORM pg_temp.rotation_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('8',64),
  'ff900000-0000-4000-8000-000000000002',repeat('7',64),'internal_receiver')),'staff cannot switch profile');
END;$staff$;
ROLLBACK TO staff_profile;
ROLLBACK;
