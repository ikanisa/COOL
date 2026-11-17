-- Additive candidate: tolerate the existing five-second clock bound only when
-- independently validating an exact native PIN bearer/device/session proof.
-- Expiry, scope, credential, authority and revocation checks are unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $install$
DECLARE item record;definition text;
 old text:=$old$s.auth_method='phone_pin' AND NOT s.revoked AND s.created_at<=at_ms$old$;
 replacement text:=$new$s.auth_method='phone_pin' AND NOT s.revoked AND s.created_at<=at_ms+5000$new$;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_pin_bound_clock_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_pin_bound_session(text,uuid,text,text)','66735fbfbcb6a5c4aefea5e2af19fe59c1486de99dc75777773e6389657c9cd7','plpgsql','{postgres=X/postgres}'),
  ('private.burimunsi_pin_session_context(text,uuid,text,text)','6988640f64febc673870d8ee2414384ee89969cc8474cc1815b71a00c009b061','sql','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_pin_renew_session(text,uuid,text,text,text,bigint)','a6a802e4f77daac9dbc7062382f56b8a5fbab0faa58990c5a90c8d25f712ac07','plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_pin_context()','424f00ebd8731473cb5b1457b0304bd88551dd5a843a748d3b82e344561f55af','plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) AS pinned(signature,body_sha256,language,acl) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(item.signature) AND pg_get_userbyid(p.proowner)='postgres'
    AND p.prokind='f' AND p.prosecdef AND NOT p.proleakproof AND p.provolatile='v' AND p.proparallel='u'
    AND l.lanname=item.language AND p.proacl::text=item.acl
    AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.body_sha256) THEN
   RAISE EXCEPTION 'burimunsi_pin_bound_clock_predecessor_changed' USING ERRCODE='55000';
  END IF;
 END LOOP;
 SELECT pg_get_functiondef(to_regprocedure('private.burimunsi_pin_bound_session(text,uuid,text,text)')) INTO definition;
 IF length(definition)-length(replace(definition,old,''))<>length(old) THEN
  RAISE EXCEPTION 'burimunsi_pin_bound_clock_predecessor_changed' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,old,replacement);
END;$install$;
COMMIT;
