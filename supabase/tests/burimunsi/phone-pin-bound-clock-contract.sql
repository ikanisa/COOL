-- SYNTHETIC ONLY. A test-scoped function definition injects a deterministic
-- database clock value; all definitions, sessions and consent changes roll back.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
CREATE FUNCTION pg_temp.check_clock(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'PIN bound clock qualification: %',label;END IF;END;$fn$;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'fe900000-0000-4000-8000-000000000061','internal_receiver',encode(sha256(convert_to(repeat('2',64),'UTF8')),'hex'),1,
 'ff000000-0000-4000-8000-000000000001',encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT private.burimunsi_set_pin_context(repeat('1',64),'fe900000-0000-4000-8000-000000000061',repeat('2',64),'internal_receiver');
SELECT set_config('qualification.pin_created',(SELECT created_at::text FROM private.burimunsi_pin_context()),true);
RESET ROLE;
CREATE FUNCTION pg_temp.inject_pin_clock(skew bigint) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE definition text;old text:=$old$at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;$old$;
 replacement text:=format('at_ms bigint:=%s::bigint;',current_setting('qualification.pin_created')::bigint-skew);
BEGIN
 SELECT pg_get_functiondef('private.burimunsi_pin_bound_session(text,uuid,text,text)'::regprocedure) INTO definition;
 IF length(definition)-length(replace(definition,old,''))<>length(old) THEN RAISE EXCEPTION 'clock injector predecessor changed';END IF;
 EXECUTE replace(definition,old,replacement);
END;$fn$;
-- Reset the definition to the exact migration body after every iteration before
-- injecting the next time; the test deliberately changes no host clock.
CREATE TEMP TABLE qualification_pin_definition AS SELECT pg_get_functiondef('private.burimunsi_pin_bound_session(text,uuid,text,text)'::regprocedure) AS body;
SELECT pg_temp.inject_pin_clock(100);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.check_clock((SELECT count(*)=1 FROM private.burimunsi_pin_context()),'100 ms database rollback admits exact current proof');
SELECT pg_temp.check_clock(private.burimunsi_observation_set_consent(true,1)='{ "enabled":true,"generation":1 }'::jsonb,'observation consent uses the same bounded proof');
SELECT pg_temp.check_clock((SELECT count(*)=0 FROM private.burimunsi_pin_session_context(repeat('3',64),'fe900000-0000-4000-8000-000000000061',repeat('2',64),'internal_receiver')),'wrong bearer stays denied');
SELECT pg_temp.check_clock((SELECT count(*)=0 FROM private.burimunsi_pin_session_context(repeat('1',64),'fe900000-0000-4000-8000-000000000061',repeat('3',64),'internal_receiver')),'wrong device stays denied');
SAVEPOINT before_revoke;
UPDATE private.burimunsi_sessions SET revoked=true WHERE id='ff000000-0000-4000-8000-000000000001';
SELECT pg_temp.check_clock((SELECT count(*)=0 FROM private.burimunsi_pin_context()),'revoked proof stays denied');
ROLLBACK TO before_revoke;
RESET ROLE;
DO $restore$ BEGIN EXECUTE (SELECT body FROM qualification_pin_definition);END;$restore$;
SELECT pg_temp.inject_pin_clock(5000);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.check_clock((SELECT count(*)=1 FROM private.burimunsi_pin_context()),'5,000 ms database boundary accepted');
RESET ROLE;
DO $restore$ BEGIN EXECUTE (SELECT body FROM qualification_pin_definition);END;$restore$;
SELECT pg_temp.inject_pin_clock(5001);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.check_clock((SELECT count(*)=0 FROM private.burimunsi_pin_context()),'5,001 ms database boundary denied');
DO $deny$ BEGIN
 BEGIN PERFORM private.burimunsi_observation_set_consent(false,2);RAISE EXCEPTION 'outside bound allowed consent';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$deny$;
RESET ROLE;
ROLLBACK;
