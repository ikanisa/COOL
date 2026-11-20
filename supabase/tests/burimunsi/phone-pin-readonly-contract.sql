-- QUALIFICATION ONLY. Run LAST in the DISPOSABLE retained-schema database.
-- This fixture commits only synthetic native installation/session metadata so
-- the next independent transaction can genuinely execute READ ONLY. It then
-- revokes that synthetic session. No retained/live database, real credential,
-- GoTrue signup, business receiver or financial record is created here.
BEGIN;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'fe900000-0000-4000-8000-000000000099','internal_receiver',
 encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),1,'fe000000-0000-4000-8000-000000000099',
 encode(sha256(convert_to(repeat('0',64),'UTF8')),'hex'),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
COMMIT;
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('request.jwt.claims','{}',true);
DO $readonly$
DECLARE c record;result jsonb;
BEGIN
 IF current_setting('transaction_read_only')<>'on' THEN RAISE EXCEPTION 'Native read-only fixture is not READ ONLY';END IF;
 SELECT * INTO STRICT c FROM private.burimunsi_pin_session_context(repeat('0',64),
  'fe900000-0000-4000-8000-000000000099',repeat('1',64),'internal_receiver');
 IF c.collection_id<>'buri-qualification-group' OR c.principal_user_id<>'f3000000-0000-4000-8000-000000000001'
  OR c.native_session_id<>'fe000000-0000-4000-8000-000000000099'::uuid OR c.role<>'admin' OR c.shared_role<>'owner'
  OR c.expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint THEN
  RAISE EXCEPTION 'Native read-only current proof mismatch';END IF;
 result:=private.burimunsi_set_pin_context(repeat('0',64),'fe900000-0000-4000-8000-000000000099',repeat('1',64),'internal_receiver');
 IF result->>'collection_id'<>'buri-qualification-group' OR api.current_principal_id()<>c.principal_user_id
  OR api.current_session_id()<>c.native_session_id::text
  OR private.assert_actor('users.manage','buri-qualification-group',NULL,1,300)<>c.principal_user_id THEN
  RAISE EXCEPTION 'Native read-only context/actor path mismatch';END IF;
 IF EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(
  encode(sha256(convert_to(repeat('0',64),'UTF8')),'hex'),'fe900000-0000-4000-8000-000000000099',repeat('1',64),'internal_receiver')) THEN
  RAISE EXCEPTION 'Native read-only accepted stored hash as opaque proof';END IF;
END;$readonly$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
UPDATE private.burimunsi_sessions SET revoked=true WHERE id='fe000000-0000-4000-8000-000000000099';
DO $revoked$
BEGIN
 IF EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat('0',64),
  'fe900000-0000-4000-8000-000000000099',repeat('1',64),'internal_receiver')) THEN
  RAISE EXCEPTION 'Native read-only fixture session revocation failed';END IF;
END;$revoked$;
COMMIT;
