-- Candidate for the fenced import transaction, AFTER lineage/marker creation
-- and imported graph, BEFORE commit and release. It patches only the existing
-- native history reader and its role-checked record projection.
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(7346371,1);
SELECT pg_advisory_xact_lock(7346371,2);
DO $preflight$
DECLARE item record;actual text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regclass('private.collect_migration_actor_lineage') IS NULL
  OR to_regclass('private.collect_imported_native_history') IS NULL
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NULL
  OR to_regprocedure('private.collect_imported_native_source(text)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_history_own(text)') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid='private.collect_migration_actor_lineage'::regclass
    AND p.polcmd IN ('r','*') AND 'postgres'::regrole=ANY(p.polroles) AND pg_get_expr(p.polqual,p.polrelid)='true')
  OR NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid='private.collect_imported_native_history'::regclass
    AND p.polcmd IN ('r','*') AND 'postgres'::regrole=ANY(p.polroles) AND pg_get_expr(p.polqual,p.polrelid)='true') THEN
  RAISE EXCEPTION 'imported_history_read_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_observation_history_rows(text)','84b3a0b23ac8d2b54f695e68755b077107a273d7e95cca5070430d373afc018a'),
  ('private.burimunsi_auto_projection(text)','975b5580a464de2f78464dd953809def6a1ed01e3b29c2fa195986635690805a')
 ) AS t(signature,expected) LOOP
  SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') INTO actual FROM pg_proc p
   WHERE p.oid=to_regprocedure(item.signature) AND p.proowner='postgres'::regrole AND p.prosecdef;
  IF actual IS DISTINCT FROM item.expected THEN RAISE EXCEPTION 'imported_history_read_predecessor_changed: %',item.signature USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

DO $patch$
DECLARE body text;definition text;anchor text;replacement text;
BEGIN
 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT body,definition FROM pg_proc p
  WHERE p.oid='private.burimunsi_observation_history_rows(text)'::regprocedure;
 anchor:=$old$ old_pin text:=current_setting('burimunsi.pin_frame',true);$old$;
 replacement:=$new$ old_pin text:=current_setting('burimunsi.pin_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$ PERFORM set_config('burimunsi.pin_frame','1',true);$old$;
 replacement:=$new$ PERFORM set_config('burimunsi.pin_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$  USING a,p_source;$old$;
 replacement:=$new$  USING a,p_source;
 -- Only immutable, lineage-proven imported observations owned by THIS exact
 -- current account and collection qualify. Historical grant/session and old
 -- principal remain retired; neither is used as present authority.
 RETURN QUERY EXECUTE $q$SELECT r.* FROM private.burimunsi_unresolved_observations r
 JOIN private.burimunsi_native_receipt_origins o ON o.source_id=r.source_id
  AND o.collection_id=r.collection_id AND o.account_id=r.account_id AND o.principal_user_id=r.principal_user_id
  AND o.installation_id=r.installation_id AND o.grant_id=r.grant_id AND o.grant_version=r.grant_version
  AND o.request_id=r.request_id AND o.fingerprint=r.fingerprint AND o.body_sha256=r.body_sha256 AND o.object_sha256=r.object_sha256
 JOIN private.collect_imported_native_history h ON h.source_id=r.source_id AND h.collection_id=r.collection_id
  AND h.request_id=r.request_id AND h.source_fingerprint=r.fingerprint
  AND h.body_sha256=r.body_sha256 AND h.object_sha256=r.object_sha256
 JOIN private.collect_migration_actor_lineage l ON l.source_actor_id=o.principal_user_id AND l.cloud_primary_id=$1->>'principalUserId'
 WHERE r.collection_id=$1->>'collectionId' AND r.account_id=($1->>'accountId')::uuid
  AND ($2 IS NULL OR r.source_id=$2)$q$
  ||CASE WHEN current_setting('transaction_read_only')='off' THEN ' FOR SHARE OF r,o,h,l' ELSE '' END
  USING a,p_source;$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$ PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);$old$;
 replacement:=$new$ PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);$new$;
 IF length(body)-length(replace(body,anchor,''))<>2*length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 SELECT prosrc INTO anchor FROM pg_proc WHERE oid='private.burimunsi_observation_history_rows(text)'::regprocedure;
 IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,anchor,body);

 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT body,definition FROM pg_proc p
  WHERE p.oid='private.burimunsi_auto_projection(text)'::regprocedure;
 anchor:=$old$  BEGIN can_reveal:=private.burimunsi_observation_own(p_source,true) IS NOT NULL;$old$;
 replacement:=$new$  BEGIN can_reveal:=CASE WHEN private.collect_imported_native_source(p_source)
   THEN private.burimunsi_observation_history_own(p_source) IS NOT NULL
   ELSE private.burimunsi_observation_own(p_source,true) IS NOT NULL END;$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor)
  OR length(definition)-length(replace(definition,body,''))<>length(body) THEN
  RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,body,replace(body,anchor,replacement));
END;$patch$;
