-- Real PostgreSQL READ ONLY policy/helper execution over synthetic fixture rows.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+60)::text,true);
DO $checks$
DECLARE current_parent record;denied boolean:=false;
BEGIN
 SELECT * INTO STRICT current_parent FROM private.burimunsi_managed_admin_snapshot();
 IF current_parent.principal_user_id<>'f3000000-0000-4000-8000-000000000001'
  OR current_parent.principal_session_id<>'f2000000-0000-4000-8000-000000000001'
  OR current_parent.transaction_read_only<>'on' OR current_parent.shared_role<>'owner'
  OR current_parent.expires_at>app.unixepoch()+60 THEN RAISE EXCEPTION 'readonly_parent_mismatch';END IF;
 -- Regression: the old source invoked this locking shared helper in READ ONLY.
 BEGIN PERFORM private.assert_actor();
 EXCEPTION WHEN read_only_sql_transaction THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'locking_shared_helper_regression_not_exercised';END IF;
 IF NOT private.burimunsi_operator_is_current('buri-qualification-group','f3000000-0000-4000-8000-000000000002',
  '+250780000002','staff',ARRAY['records.read','members.enroll']) THEN RAISE EXCEPTION 'approved_staff_missing';END IF;
 IF private.burimunsi_operator_is_current('buri-qualification-group','f3000000-0000-4000-8000-000000000002',
  '+250780000002','staff',ARRAY['records.read','payments.allocate']) THEN RAISE EXCEPTION 'approval_capability_ceiling_bypassed';END IF;
 PERFORM set_config('request.jwt.claims',(private.request_claims()||'{"exp":0}'::jsonb)::text,true);
 IF EXISTS(SELECT 1 FROM private.burimunsi_managed_admin_snapshot()) THEN RAISE EXCEPTION 'expired_jwt_snapshot_accepted';END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 IF EXISTS(SELECT 1 FROM private.burimunsi_managed_admin_snapshot()) THEN RAISE EXCEPTION 'missing_managed_claims_accepted';END IF;
END;$checks$;
ROLLBACK;
