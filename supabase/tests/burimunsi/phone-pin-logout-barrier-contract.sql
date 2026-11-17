-- QUALIFICATION ONLY. Disposable fenced PostgreSQL after operator-seed,
-- session renewal, passcode rotation and logout-barrier migrations.
-- All identifiers and bearer/device tokens below are public synthetic data.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
CREATE FUNCTION pg_temp.logout_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Native logout barrier: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.logout_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Native logout SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Native logout expected SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.logout_hash(value text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
 SELECT encode(sha256(convert_to(value,'UTF8')),'hex')
$fn$;
DO $catalog$
DECLARE r text;signature text:='private.burimunsi_pin_logout_barrier(text,uuid,text,text,text,text)';
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_temp.logout_check(has_function_privilege('collect_runtime',signature,'EXECUTE'),'runtime barrier allowed');
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
  PERFORM pg_temp.logout_check(NOT has_function_privilege(r,signature,'EXECUTE'),'barrier private from '||r);
 END LOOP;
END;$catalog$;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'fa900000-0000-4000-8000-000000000001','internal_receiver',pg_temp.logout_hash(repeat('2',64)),1,
 'fa000000-0000-4000-8000-000000000001',pg_temp.logout_hash(repeat('1',64)),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT private.burimunsi_set_pin_context(repeat('1',64),'fa900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver');
DO $absent$
DECLARE response jsonb;pin_hash jsonb:=jsonb_build_object('algorithm','pbkdf2-sha256+hmac-v1','pepperId','qualification-only',
 'iterations',600000,'salt',repeat('b',32),'hash',repeat('c',64));
BEGIN
 PERFORM pg_temp.logout_check(private.burimunsi_pin_logout_barrier(repeat('1',64),
  'fa900000-0000-4000-8000-000000000001',repeat('3',64),'internal_receiver','buri-qualification-group',NULL) IS NULL,'wrong device denied');
 PERFORM pg_temp.logout_check(private.burimunsi_pin_logout_barrier(repeat('1',64),
  'fa900000-0000-4000-8000-000000000001',repeat('2',64),'staff','buri-qualification-group',NULL) IS NULL,'wrong profile denied');
 PERFORM pg_temp.logout_check(private.burimunsi_pin_logout_barrier(repeat('1',64),
  'fa900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver','other-group',NULL) IS NULL,'wrong group denied');
 PERFORM pg_temp.logout_check(EXISTS(SELECT 1 FROM private.burimunsi_pin_context()),'bad proof has no effect');
 response:=private.burimunsi_pin_logout_barrier(repeat('1',64),'fa900000-0000-4000-8000-000000000001',
  repeat('2',64),'internal_receiver','buri-qualification-group',repeat('4',64));
 PERFORM pg_temp.logout_check(response->>'accountId'='f7000000-0000-4000-8000-000000000001','exact predecessor revoked');
 PERFORM pg_temp.logout_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_context()),'old proof cannot authorize');
 PERFORM pg_temp.logout_check(private.burimunsi_pin_logout_barrier(repeat('1',64),'fa900000-0000-4000-8000-000000000001',
  repeat('2',64),'internal_receiver','buri-qualification-group',repeat('4',64))=response,'idempotent logout acknowledgement');
 PERFORM pg_temp.logout_expect(format($q$SELECT private.burimunsi_pin_rotate_passcode(
  'f7000000-0000-4000-8000-000000000001','fa000000-0000-4000-8000-000000000001',1,1,%L::jsonb,%L,%L,1800000)$q$,
  pin_hash::text,pg_temp.logout_hash(repeat('4',64)),repeat('5',64)),'42501');
 PERFORM pg_temp.logout_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('4',64),
  'fa900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver')),'delayed rotation cannot resurrect candidate');
END;$absent$;

-- A candidate that already exists on the same account/grant is revoked in the
-- same barrier, even when the installation has since been suspended.
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'fa900000-0000-4000-8000-000000000001','internal_receiver',pg_temp.logout_hash(repeat('2',64)),1,
 'fa000000-0000-4000-8000-000000000002',pg_temp.logout_hash(repeat('6',64)),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT set_config('burimunsi.pin_token','',true),set_config('burimunsi.pin_installation','',true),
 set_config('burimunsi.pin_device','',true),set_config('burimunsi.pin_profile','',true);
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE installation_id='fa900000-0000-4000-8000-000000000001';
SELECT pg_temp.logout_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('6',64),
 'fa900000-0000-4000-8000-000000000001',repeat('2',64),'internal_receiver')),'suspended device denies ordinary authority');
SELECT pg_temp.logout_check(private.burimunsi_pin_logout_barrier(repeat('1',64),'fa900000-0000-4000-8000-000000000001',
 repeat('2',64),'internal_receiver','buri-qualification-group',repeat('6',64)) IS NOT NULL,'logout while suspended acknowledged');
SELECT pg_temp.logout_check((SELECT revoked FROM private.burimunsi_sessions WHERE id='fa000000-0000-4000-8000-000000000002'),
 'existing same-device candidate permanently revoked');
ROLLBACK;
