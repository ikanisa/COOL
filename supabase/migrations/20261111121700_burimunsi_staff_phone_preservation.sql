-- UNREGISTERED DRAFT. Install only under the existing fenced migration path.
-- No identity, phone, PIN, grant, approval, or session is seeded or rewritten.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE expected record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regprocedure('private.burimunsi_pin_staff_phone_available(text,uuid,text)') IS NOT NULL
  OR to_regprocedure('private.burimunsi_pin_context()') IS NULL
  OR to_regprocedure('private.burimunsi_pin_authority_snapshot(text,text,text,text,text[])') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='private' AND c.relname='burimunsi_accounts' AND c.relkind='r' AND c.relrowsecurity AND c.relforcerowsecurity)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE t.tgrelid='private.burimunsi_accounts'::regclass AND t.tgname='burimunsi_pin_account_version'
     AND t.tgenabled='O' AND NOT t.tgisinternal AND p.oid='private.burimunsi_pin_account_version()'::regprocedure
     AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='528af5ae9c257622115d01b6feb47c99f23b8c522c79bab93dba902e9d6d2e98') THEN
  RAISE EXCEPTION 'burimunsi_staff_phone_uniqueness_precondition' USING ERRCODE='55000';
 END IF;
 FOR expected IN SELECT * FROM (VALUES
  ('private.burimunsi_pin_authority_snapshot(text,text,text,text,text[])','870f00f58d8451848ac9e2563b9db232a3f0122a6201bbdff1eafaca670fc469','s','plpgsql'),
  ('private.burimunsi_pin_context()','424f00ebd8731473cb5b1457b0304bd88551dd5a843a748d3b82e344561f55af','v','plpgsql'),
  ('private.burimunsi_pin_session_context(text,uuid,text,text)','6988640f64febc673870d8ee2414384ee89969cc8474cc1815b71a00c009b061','v','sql'),
  ('private.burimunsi_setup_fence()','abe658b11beb1688cd05474d58c7c82399cdbdd2a2ff88aa45630f6b2bd5a8d3','v','plpgsql'),
  ('private.burimunsi_pin_account_actor()','5304b083c82d8bc9770b913d1a1fe0fcb14a85354076cd83499a48f26bc11105','v','plpgsql'),
  ('private.burimunsi_account_requires_approval()','6837d020be36ca4757ecdf637222988b57e977ceb74cd9eabc654ec3793b71c0','v','plpgsql')
 ) AS pin(signature,body_sha256,volatility,language) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(expected.signature) AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
    AND p.provolatile::text=expected.volatility AND l.lanname=expected.language
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=expected.body_sha256) THEN
   RAISE EXCEPTION 'burimunsi_staff_phone_predecessor_changed: %',expected.signature USING ERRCODE='55000';
  END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_accounts'::regclass AND tgname='burimunsi_pin_account_actor'
   AND tgenabled='O' AND tgfoid='private.burimunsi_pin_account_actor()'::regprocedure)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_accounts'::regclass AND tgname='burimunsi_account_requires_approval'
   AND tgenabled='O' AND tgfoid='private.burimunsi_account_requires_approval()'::regprocedure) THEN
  RAISE EXCEPTION 'burimunsi_staff_phone_predecessor_changed' USING ERRCODE='55000';
 END IF;
END;$preflight$;
-- Called inside the authenticated staff-edit transaction holding the standard
-- Collect mutation lock. Returns no other group's identity or phone metadata.
CREATE FUNCTION private.burimunsi_pin_staff_phone_available(p_collection text,p_target uuid,p_phone text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;target private.burimunsi_accounts%ROWTYPE;old_frame text:=current_setting('burimunsi.pin_frame',true);available boolean;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_collection IS NULL OR p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR p_target IS NULL OR p_phone IS NULL OR p_phone !~ '^\+2507[2389][0-9]{7}$' THEN
  RAISE EXCEPTION 'burimunsi_staff_phone_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.collection_id IS DISTINCT FROM p_collection OR actor.role<>'admin'
  OR NOT('staff.manage'=ANY(actor.capabilities)) THEN
  RAISE EXCEPTION 'burimunsi_staff_phone_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT * INTO target FROM private.burimunsi_accounts a WHERE a.id=p_target AND a.collection_id=p_collection FOR UPDATE;
 IF NOT FOUND OR target.role<>'staff' OR NOT target.active OR target.removed OR target.phone=p_phone
  OR private.burimunsi_pin_authority_snapshot(p_collection,target.principal_user_id,target.phone,target.role,target.capabilities) IS NULL
  OR private.burimunsi_pin_authority_snapshot(p_collection,target.principal_user_id,p_phone,target.role,target.capabilities) IS NULL THEN
  RAISE EXCEPTION 'burimunsi_staff_phone_denied' USING ERRCODE='42501';END IF;
 SELECT NOT EXISTS(SELECT 1 FROM private.burimunsi_accounts a WHERE a.id<>p_target AND a.phone=p_phone AND a.active AND NOT a.removed)
  INTO available;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN available;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_staff_phone_available(text,uuid,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_pin_staff_phone_available(text,uuid,text) TO collect_runtime;
COMMIT;
