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


SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'ff900000-0000-4000-8000-000000000001','internal_receiver',pg_temp.rotation_hash(repeat('2',64)),1,
 'ff000000-0000-4000-8000-000000000001',pg_temp.rotation_hash(repeat('1',64)),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT private.burimunsi_set_pin_context(repeat('1',64),'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver');
RESET ROLE;
-- A synthetic-only wrapper returns a genuinely shorter persisted expiry. The
-- original implementation still creates both sessions, and the transaction
-- rolls back the wrapper and all data. No host clock is changed.
ALTER FUNCTION private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint)
 RENAME TO burimunsi_pin_create_session_qualification_original;
CREATE FUNCTION private.burimunsi_pin_create_session(p_collection text,p_account uuid,p_installation uuid,p_profile text,
 p_device text,p_credential bigint,p_session uuid,p_token text,p_created bigint,p_expires bigint,p_version bigint)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE value jsonb;adjusted bigint:=p_expires;
BEGIN
 IF p_expires-p_created>60000 THEN adjusted:=p_expires-1000;END IF;
 value:=private.burimunsi_pin_create_session_qualification_original(p_collection,p_account,p_installation,p_profile,
  p_device,p_credential,p_session,p_token,p_created,adjusted,p_version);
 IF p_expires-p_created>60000 THEN
  PERFORM set_config('qualification.rotation_requested_expiry',p_expires::text,true);
  PERFORM set_config('qualification.rotation_actual_expiry',value->>'expiresAt',true);
  IF current_setting('qualification.rotation_malformed',true)='true' THEN RETURN value||'{"expiresAt":null}'::jsonb;END IF;
 END IF;
 RETURN value;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint) TO collect_runtime;
SET LOCAL ROLE collect_runtime;
SAVEPOINT malformed_expiry;
SELECT set_config('qualification.rotation_malformed','true',true);
SELECT pg_temp.rotation_expect($q$SELECT private.burimunsi_pin_rotate_passcode('f7000000-0000-4000-8000-000000000001',
 'ff000000-0000-4000-8000-000000000001',1,1,pg_temp.rotation_pin(),pg_temp.rotation_hash(repeat('4',64)),repeat('5',64),1800000)$q$,'42501');
SELECT pg_temp.rotation_check(EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('1',64),
 'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver')),'malformed result rolls back old-session revocation');
SELECT pg_temp.rotation_check((SELECT version=1 AND credential_version=1 FROM private.burimunsi_accounts WHERE id='f7000000-0000-4000-8000-000000000001'),
 'malformed result rolls back credential update');
ROLLBACK TO malformed_expiry;
DO $test$
DECLARE result jsonb;persisted bigint;requested bigint;reported bigint;
BEGIN
 result:=private.burimunsi_pin_rotate_passcode('f7000000-0000-4000-8000-000000000001','ff000000-0000-4000-8000-000000000001',
  1,1,pg_temp.rotation_pin(),pg_temp.rotation_hash(repeat('4',64)),repeat('5',64),1800000);
 SELECT expires_at INTO STRICT persisted FROM private.burimunsi_sessions WHERE token_hash=pg_temp.rotation_hash(repeat('4',64));
 requested:=current_setting('qualification.rotation_requested_expiry')::bigint;
 reported:=(result->>'expiresAt')::bigint;
 PERFORM pg_temp.rotation_check(persisted=current_setting('qualification.rotation_actual_expiry')::bigint AND persisted<requested,
  'controlled replacement session expiry really shortened');
 PERFORM pg_temp.rotation_check(reported=persisted,'response returns exact persisted replacement expiry');
 PERFORM pg_temp.rotation_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('1',64),
  'ff900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver')),'successful rotation revokes old session');
END;$test$;
ROLLBACK;
