-- Additive candidate: return the expiry actually persisted for the replacement
-- PIN session. The historical rotation and session migrations remain unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $install$
DECLARE item record;definition text;old text:=$old$RETURN jsonb_build_object('rotated',true,'expiresAt',expires_ms);$old$;
 replacement text:=$new$IF jsonb_typeof(created->'expiresAt') IS DISTINCT FROM 'number'
  OR coalesce(created->>'expiresAt','') !~ '^[0-9]{1,16}$'
  OR (created->>'expiresAt')::bigint<=at_ms OR (created->>'expiresAt')::bigint>expires_ms THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('rotated',true,'expiresAt',(created->>'expiresAt')::bigint);$new$;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_rotation_expiry_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)','2d08839db6c690d214bb7151446612d80398cc17a596f9f9155c76a370d40c40'),
  ('private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint)','3eabcd7e7d8910040c99906e6196c159b849dd4128d393170d263461557f0dc7')
 ) AS pinned(signature,body_sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(item.signature) AND pg_get_userbyid(p.proowner)='postgres'
    AND p.prokind='f' AND p.prosecdef AND NOT p.proleakproof AND p.provolatile='v' AND p.proparallel='u'
    AND l.lanname='plpgsql' AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
    AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.body_sha256) THEN
   RAISE EXCEPTION 'burimunsi_rotation_expiry_predecessor_changed' USING ERRCODE='55000';
  END IF;
 END LOOP;
 SELECT pg_get_functiondef(to_regprocedure('private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)')) INTO definition;
 IF length(definition)-length(replace(definition,old,''))<>length(old) THEN
  RAISE EXCEPTION 'burimunsi_rotation_expiry_predecessor_changed' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,old,replacement);
END;$install$;
COMMIT;
