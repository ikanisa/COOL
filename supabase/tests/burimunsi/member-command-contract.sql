-- Actual collect_runtime SQL execution and canonical shared statements. Auth
-- users/sessions/OTP rows are declared SQL fixtures, not GoTrue authentication.
-- The harness holds a genuine separately registered application WORK lease.
BEGIN;
SET LOCAL ROLE collect_runtime;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');
DO $role$ BEGIN
 IF current_user<>'collect_runtime' OR (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN
  RAISE EXCEPTION 'Normal runtime role required';
 END IF;
END;$role$;
__GUARDS__
__PERSON__
__MEMBERSHIP__
__AUDIT__
DO $person$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.users u JOIN app.memberships m ON m.user_id=u.id
   WHERE u.id='fa000000-0000-4000-8000-000000000001' AND m.collection_id='buri-qualification-group'
    AND u.member_type='direct' AND u.phone IS NULL AND u.email IS NULL AND u.momo_number='0789444111'
    AND u.public_id~'^[0-9]{6}$' AND m.role='member' AND m.active=1 AND m.revision=1)
  OR EXISTS(SELECT 1 FROM app.ledger_entries WHERE member_id='fa000000-0000-4000-8000-000000000001') THEN
  RAISE EXCEPTION 'Canonical Direct-member contract failed';
 END IF;
END;$person$;
__CHANGE__
DO $changed$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.memberships WHERE user_id='fa000000-0000-4000-8000-000000000001'
   AND collection_id='buri-qualification-group' AND role='member' AND active=0 AND revision=2) THEN
  RAISE EXCEPTION 'Canonical membership update failed';
 END IF;
END;$changed$;
-- Native permissions cannot make the shared read-only staff role a writer.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000002',
 'session_id','f2000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000002',repeat('b',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000002');
DO $staff$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM private.assert_actor('users.manage','buri-qualification-group',NULL,2,300);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Shared staff authority was widened';END IF;
END;$staff$;
ROLLBACK;
