-- QUALIFICATION ONLY. Run after current operator-seed in an isolated disposable
-- database under an externally owned genuine WORK admission. All effects roll
-- back. No provider, GoTrue signup, actual native session or passcode is used.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
__PLATFORM_PUBLIC_INPUTS__
CREATE FUNCTION pg_temp.platform_case(p_name text) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $fn$
 SELECT pg_temp.platform_public_fixture('cases')->p_name
$fn$;
CREATE FUNCTION pg_temp.platform_run(p_name text) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE statement jsonb;observed jsonb;
BEGIN
 FOR statement IN SELECT value FROM jsonb_array_elements(pg_temp.platform_case(p_name)->'statements') LOOP
  IF (statement->>'kind')='outcome_lookup' THEN
   EXECUTE 'SELECT coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) FROM ('||(statement->>'sql')||') r' INTO observed;
  ELSIF (statement->>'kind')='native_members' THEN
   EXECUTE 'SELECT coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) FROM ('||(statement->>'sql')||') r' INTO observed;
   IF observed IS DISTINCT FROM '[]'::jsonb AND observed IS DISTINCT FROM '[{"total":0}]'::jsonb THEN
    RAISE EXCEPTION 'Unexpected native Members rows for empty sponsored group';END IF;
  ELSE EXECUTE (statement->>'sql');END IF;
 END LOOP;
 RETURN observed;
END;$fn$;
CREATE FUNCTION pg_temp.platform_expect(p_name text,p_state text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 BEGIN PERFORM pg_temp.platform_run(p_name);
 EXCEPTION WHEN OTHERS THEN IF SQLSTATE=p_state THEN RETURN;END IF;
  RAISE EXCEPTION 'Platform qualification state %, expected %',SQLSTATE,p_state;
 END;
 RAISE EXCEPTION 'Expected platform authority/conflict rejection';
END;$fn$;
-- Genuine person used ONLY for the unchanged private-creation control case.
INSERT INTO app.users(id,phone,full_name,public_id,member_type,momo_number,created_at,updated_at)
 VALUES('fd300000-0000-4000-8000-000000000001','+250780000003','QUALIFICATION Private Person','000003','direct','0780000003',
 app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
CREATE TEMP TABLE platform_before AS SELECT
 (SELECT count(*) FROM app.ledger_entries) ledger,
 (SELECT count(*) FROM app.payments) payments,
 (SELECT count(*) FROM auth.users) auth_users,
 (SELECT count(*) FROM auth.sessions) auth_sessions,
 (SELECT count(*) FROM private.burimunsi_accounts) native_accounts,
 (SELECT count(*) FROM private.burimunsi_sessions) native_sessions;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT pg_advisory_xact_lock(734636924058501::bigint);
SELECT pg_temp.platform_run('sponsor');
DO $sponsor$ DECLARE cid text:=pg_temp.platform_case('sponsor')->'result'->>'resource_id';BEGIN
 IF current_user<>'collect_runtime' OR(SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN
  RAISE EXCEPTION 'Ordinary runtime authority required';END IF;
 IF NOT EXISTS(SELECT 1 FROM app.collections WHERE id=cid AND creator_user_id='f3000000-0000-4000-8000-000000000001'
  AND status='active' AND visibility_status='public_approved' AND is_platform_sponsored=1
  AND receiver_network='mtn_momo' AND receiver_momo_number='0001' AND receiver_display_label='QUALIFICATION route label')
  OR EXISTS(SELECT 1 FROM app.memberships WHERE collection_id=cid) THEN RAISE EXCEPTION 'Sponsored creator/member separation failed';END IF;
 IF (SELECT response_json::jsonb FROM app.request_receipts WHERE user_id='f3000000-0000-4000-8000-000000000001'
  AND request_id=(pg_temp.platform_case('sponsor')->>'requestId')) IS DISTINCT FROM (pg_temp.platform_case('sponsor')->'result') THEN
  RAISE EXCEPTION 'Canonical sponsored receipt missing';END IF;
END;$sponsor$;
SELECT pg_temp.platform_run('replay');
DO $lookup$ DECLARE result jsonb;BEGIN
 result:=pg_temp.platform_run('lookup');
 IF jsonb_array_length(result)<>1 OR (result->0->>'response_json')::jsonb IS DISTINCT FROM (pg_temp.platform_case('sponsor')->'result')
  OR (result->0->>'request_id') IS DISTINCT FROM (pg_temp.platform_case('sponsor')->>'requestId') THEN
  RAISE EXCEPTION 'Original GET receipt does not match';END IF;
END;$lookup$;
SELECT pg_temp.platform_expect('race_conflict','23514');
SELECT pg_temp.platform_expect('wrong_cookie','42501');
SELECT pg_temp.platform_run('native_members');
SELECT pg_temp.platform_run('private');
RESET ROLE;
DO $preserve$ DECLARE sponsor text:=pg_temp.platform_case('sponsor')->'result'->>'resource_id';
 private_group text:=pg_temp.platform_case('private')->'result'->>'resource_id';BEGIN
 IF (SELECT count(*) FROM app.collections WHERE title LIKE 'QUALIFICATION%Public%')<>1
  OR EXISTS(SELECT 1 FROM app.memberships WHERE collection_id=sponsor)
  OR (SELECT count(*) FROM app.memberships WHERE collection_id=private_group AND user_id='fd300000-0000-4000-8000-000000000001' AND role='owner' AND active=1)<>1
  OR NOT EXISTS(SELECT 1 FROM app.collections WHERE id=private_group AND visibility_status='private' AND is_platform_sponsored=0) THEN
  RAISE EXCEPTION 'Sponsor replay/private-owner regression';END IF;
 IF EXISTS(SELECT 1 FROM platform_before WHERE ledger<>(SELECT count(*) FROM app.ledger_entries)
  OR payments<>(SELECT count(*) FROM app.payments) OR auth_users<>(SELECT count(*) FROM auth.users)
  OR auth_sessions<>(SELECT count(*) FROM auth.sessions) OR native_accounts<>(SELECT count(*) FROM private.burimunsi_accounts)
  OR native_sessions<>(SELECT count(*) FROM private.burimunsi_sessions)) THEN RAISE EXCEPTION 'Unrelated financial/Auth/native state changed';END IF;
END;$preserve$;
ROLLBACK;
