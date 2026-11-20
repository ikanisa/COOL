-- Bind the reviewed Collect principal to an operator approval. This migration
-- changes neither existing approvals nor any credentials and requires the
-- reviewed original function and a fenced application before installation.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE prior regprocedure:=to_regprocedure('private.burimunsi_operator_approve(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint)');
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR prior IS NULL
  OR to_regprocedure('private.burimunsi_operator_approve_v2(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint,text)') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=prior AND prosecdef AND pg_get_userbyid(proowner)='postgres')
  OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=prior AND a.privilege_type='EXECUTE' AND a.grantee NOT IN
    (p.proowner,(SELECT oid FROM pg_roles WHERE rolname='collect_runtime')))
  OR encode(sha256(convert_to(pg_get_functiondef(prior),'UTF8')),'hex')<>'42e5bf7b87d2ed3516bf1aa21dd05dbf1e93ce7429cd64ba0e6fcf7ee58e3c52' THEN
  RAISE EXCEPTION 'burimunsi_operator_identity_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE FUNCTION private.burimunsi_operator_approve_v2(
 p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid,
 p_admin text,p_phone text,p_role text,p_capabilities text[],p_active boolean,p_expected bigint,
 p_expected_principal text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE target text;result jsonb;
BEGIN
 -- Take the existing mutation lock before owner and row locks, matching the
 -- legacy command. Row locks prevent a linked principal changing before commit.
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public);
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR p_expected_principal IS NULL
  OR p_expected_principal !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
  RAISE EXCEPTION 'burimunsi_invalid_approval' USING ERRCODE='22023';
 END IF;
 SELECT u.id INTO target FROM app.admin_users a
  JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  JOIN app.users u ON u.id=l.user_id WHERE a.id=p_admin FOR SHARE OF a,l,u;
 IF target IS DISTINCT FROM p_expected_principal THEN
  RAISE EXCEPTION 'burimunsi_approval_changed' USING ERRCODE='40001';
 END IF;
 result:=private.burimunsi_operator_approve(p_actor,p_cookie,p_origin,p_public,p_collection,p_request,
  p_admin,p_phone,p_role,p_capabilities,p_active,p_expected);
 -- An old receipt for the same request is never accepted for another principal.
 IF result->>'principalId' IS DISTINCT FROM p_expected_principal THEN
  RAISE EXCEPTION 'burimunsi_approval_request_conflict' USING ERRCODE='23505';
 END IF;
 RETURN result;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_operator_approve(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
REVOKE ALL ON FUNCTION private.burimunsi_operator_approve_v2(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_operator_approve_v2(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint,text) TO collect_runtime;
DO $postflight$
DECLARE prior regprocedure:='private.burimunsi_operator_approve(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint)'::regprocedure;
 guarded regprocedure:='private.burimunsi_operator_approve_v2(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint,text)'::regprocedure;
BEGIN
 IF has_function_privilege('collect_runtime',prior,'EXECUTE')
  OR NOT has_function_privilege('collect_runtime',guarded,'EXECUTE')
  OR has_function_privilege('anon',guarded,'EXECUTE')
  OR has_function_privilege('authenticated',guarded,'EXECUTE')
  OR has_function_privilege('service_role',guarded,'EXECUTE')
  OR has_function_privilege('collect_importer',guarded,'EXECUTE') THEN
  RAISE EXCEPTION 'burimunsi_operator_identity_privileges' USING ERRCODE='55000';
 END IF;
END;$postflight$;
COMMIT;
