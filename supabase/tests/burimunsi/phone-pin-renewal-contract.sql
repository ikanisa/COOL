-- QUALIFICATION ONLY. Run in a disposable fenced PostgreSQL clone after the
-- synthetic operator seed and the additive native-session renewal migration.
-- All token/device values below are public synthetic fixtures. Roll back all
-- data; this test never connects to a retained/live database or provider.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
CREATE FUNCTION pg_temp.renew_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Native session renewal: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.renew_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Native renewal SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Native renewal expected SQLSTATE %',expected;
END;$fn$;
DO $catalog$
DECLARE role_name text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_temp.renew_check(to_regclass('private.burimunsi_pin_session_leases') IS NULL,'no new private lease relation');
 PERFORM pg_temp.renew_check(EXISTS(SELECT 1 FROM pg_class WHERE oid='private.burimunsi_sessions'::regclass
  AND relrowsecurity AND relforcerowsecurity),'existing session FORCE RLS');
 PERFORM pg_temp.renew_check(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_sessions'::regclass
  AND tgname='collect_fence_statement_v1' AND tgenabled='A'),'existing session ALWAYS fence');
 PERFORM pg_temp.renew_check(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_sessions'::regclass
  AND tgname='burimunsi_pin_lease_guard' AND tgenabled='A'),'lease ALWAYS owner guard');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
  PERFORM pg_temp.renew_check(NOT has_function_privilege(role_name,'private.burimunsi_pin_bound_session(text,uuid,text,text)','EXECUTE'),'unexpired credential helper denied '||role_name);
  PERFORM pg_temp.renew_check(NOT has_function_privilege(role_name,'private.burimunsi_pin_lease_guard()','EXECUTE'),'lease guard denied '||role_name);
 END LOOP;
 PERFORM pg_temp.renew_check(has_function_privilege('collect_runtime','private.burimunsi_pin_renew_session(text,uuid,text,text,text,bigint)','EXECUTE'),'runtime renewal entry point');
END;$catalog$;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
DO $renewal$
DECLARE created bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 original_expiry bigint:=created+1200;
 original_session uuid:='fe000000-0000-4000-8000-000000000098';
 installation uuid:='fe900000-0000-4000-8000-000000000098';
 original record;renewed record;again record;stored record;
BEGIN
 PERFORM private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  installation,'internal_receiver',encode(sha256(convert_to(repeat('2',64),'UTF8')),'hex'),1,original_session,
  encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),created,original_expiry,1);
 SELECT * INTO STRICT original FROM private.burimunsi_pin_session_context(repeat('1',64),installation,repeat('2',64),'internal_receiver');
 PERFORM pg_temp.renew_check(original.native_session_id=original_session AND original.expires_at=original_expiry,'original current proof');
 -- A caller may know a session id and even spoof its transaction marker and
 -- raw device proof. Direct runtime writes must still fail the owner guard.
 PERFORM set_config('burimunsi.pin_renewal_frame',txid_current()::text||':'||original_session::text,true);
 PERFORM set_config('burimunsi.pin_renewal_token',repeat('1',64),true);
 PERFORM set_config('burimunsi.pin_renewal_installation',installation::text,true);
 PERFORM set_config('burimunsi.pin_renewal_device',repeat('2',64),true);
 PERFORM set_config('burimunsi.pin_renewal_profile','internal_receiver',true);
 PERFORM pg_temp.renew_expect(format('UPDATE private.burimunsi_sessions SET pin_renewed_at=%s,pin_lease_expires_at=%s WHERE id=%L',
  created,created+60000,original_session),'42501');
 PERFORM set_config('burimunsi.pin_renewal_frame','',true);
 PERFORM set_config('burimunsi.pin_renewal_token','',true);
 PERFORM set_config('burimunsi.pin_renewal_installation','',true);
 PERFORM set_config('burimunsi.pin_renewal_device','',true);
 PERFORM set_config('burimunsi.pin_renewal_profile','',true);
 PERFORM pg_sleep(1.3);
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('1',64),installation,repeat('2',64),'internal_receiver')),'expired ordinary proof denied');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('0',64),installation,repeat('2',64),'internal_receiver','buri-qualification-group',60000)),'wrong bearer');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),installation,repeat('2',64),'internal_receiver','buri-qualification-group',60000)),'stored bearer hash denied');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('3',64),'internal_receiver','buri-qualification-group',60000)),'wrong device secret');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('1',64),'fe900000-0000-4000-8000-000000000097',repeat('2',64),'internal_receiver','buri-qualification-group',60000)),'wrong installation');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('2',64),'staff','buri-qualification-group',60000)),'wrong profile');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('2',64),'internal_receiver','wrong-group',60000)),'wrong group');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('2',64),'internal_receiver','buri-qualification-group',28800001)),'unbounded duration denied');
 SELECT * INTO STRICT renewed FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('2',64),'internal_receiver','buri-qualification-group',60000);
 PERFORM pg_temp.renew_check(renewed.native_session_id=original_session AND renewed.created_at=created
  AND renewed.expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint,'exact original session renewed');
 SELECT * INTO STRICT stored FROM private.burimunsi_sessions WHERE id=original_session;
 PERFORM pg_temp.renew_check(stored.created_at=created AND stored.expires_at=original_expiry AND NOT stored.revoked
  AND stored.pin_renewed_at IS NOT NULL AND stored.pin_lease_expires_at=renewed.expires_at,'immutable original and bounded lease');
 PERFORM pg_temp.renew_check(coalesce(current_setting('burimunsi.pin_renewal_frame',true),'')=''
  AND coalesce(current_setting('burimunsi.pin_renewal_token',true),'')='','owner renewal proof frame cleared');
 PERFORM pg_temp.renew_expect(format('UPDATE private.burimunsi_sessions SET pin_renewed_at=NULL,pin_lease_expires_at=NULL WHERE id=%L',
  original_session),'42501');
 PERFORM pg_temp.renew_check(EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('1',64),installation,repeat('2',64),'internal_receiver') c
  WHERE c.native_session_id=original_session AND c.expires_at=renewed.expires_at),'ordinary current proof uses lease');
 SELECT * INTO STRICT again FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('2',64),'internal_receiver','buri-qualification-group',60000);
 PERFORM pg_temp.renew_check(again.native_session_id=original_session AND again.expires_at>=renewed.expires_at,'retry keeps same session');
 PERFORM private.burimunsi_set_pin_context(repeat('1',64),installation,repeat('2',64),'internal_receiver');
 PERFORM pg_temp.renew_check(private.burimunsi_pin_assert_actor(NULL,'buri-qualification-group',NULL,1,NULL)=renewed.principal_user_id,'renewal keeps original current authority');
 UPDATE private.burimunsi_sessions SET revoked=true WHERE id=original_session;
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_renew_session(repeat('1',64),installation,repeat('2',64),'internal_receiver','buri-qualification-group',60000)),'logout cannot be renewed');
 PERFORM pg_temp.renew_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('1',64),installation,repeat('2',64),'internal_receiver')),'logout denies ordinary proof');
END;$renewal$;
ROLLBACK;
