CREATE FUNCTION private._retention_row_record_delta_v2(p_plan uuid,p_operation uuid,p_class text,p_before jsonb,p_after jsonb DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE before_descriptor jsonb:=private._retention_row_descriptor_v2(p_class,p_before);after_descriptor jsonb;
BEGIN
 IF p_after IS NOT NULL THEN after_descriptor:=private._retention_row_descriptor_v2(p_class,p_after);END IF;
 INSERT INTO private.retention_row_effects(plan_id,operation_id,class_name,key_sha256,before_descriptor,after_descriptor)
 VALUES(p_plan,p_operation,p_class,before_descriptor->>'key_sha256',before_descriptor,after_descriptor);
END$$;

CREATE FUNCTION private._retention_row_quarantine_v2(p_plan uuid,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE p private.retention_row_plans%ROWTYPE;m private.retention_inventory_manifests%ROWTYPE;r record;b jsonb;after_row jsonb;at bigint:=extract(epoch FROM clock_timestamp())::bigint;date text;
 revoked integer:=0;cookies integer:=0;custody integer:=0;remaining bigint;principal uuid;
BEGIN
 SELECT * INTO STRICT p FROM private.retention_row_plans WHERE id=p_plan;
 SELECT * INTO STRICT m FROM private.retention_inventory_manifests WHERE id=p.manifest_id;
 SELECT auth_user_id INTO principal FROM private.auth_principal_links WHERE user_id=p.subject_id;
 IF principal IS NULL THEN RAISE EXCEPTION 'retention_row_principal_unavailable' USING ERRCODE='42501';END IF;
 IF p.policy_raw::jsonb->'copy_inventory'->>'bff_access_revocation'<>'allow' AND EXISTS(SELECT 1 FROM private.bff_sessions WHERE auth_user_id=principal) THEN
  RAISE EXCEPTION 'retention_row_bff_revocation_unapproved' USING ERRCODE='42501';END IF;
 date:=to_char(to_timestamp(at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
 INSERT INTO app.privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds)
 VALUES(p.subject_id,p.app_plan_id,m.source_sha256,p.policy_sha256,at) ON CONFLICT(subject_id) DO NOTHING;
 SELECT to_jsonb(u) INTO b FROM app.users u WHERE id=p.subject_id FOR UPDATE;
 IF b IS NULL THEN RAISE EXCEPTION 'retention_row_subject_unavailable' USING ERRCODE='42501';END IF;
 IF b->>'access_status'='active' THEN
  UPDATE app.users SET access_status='suspended',updated_at=date WHERE id=p.subject_id;
  -- The existing AFTER trigger increments the account revision in a separate
  -- UPDATE. RETURNING would expose the earlier image and cannot prove the
  -- durable row. Read the final locked row after those triggers finish.
  SELECT to_jsonb(u) INTO after_row FROM app.users u WHERE id=p.subject_id;
  PERFORM private._retention_row_record_delta_v2(p.id,p_operation,'users',b,after_row);
 END IF;
 -- Access revocation itself is resumable. A long session history never causes
 -- an unbounded UPDATE or collapses a partially revoked account into success.
 FOR r IN SELECT * FROM app.auth_sessions WHERE user_id=p.subject_id AND revoked_at IS NULL ORDER BY id LIMIT 40 FOR UPDATE LOOP
  UPDATE app.auth_sessions SET revoked_at=at,revocation_reason='privacy_retention_quarantine' WHERE id=r.id RETURNING to_jsonb(auth_sessions) INTO after_row;
  PERFORM private._retention_row_record_delta_v2(p.id,p_operation,'auth_sessions',to_jsonb(r),after_row);revoked:=revoked+1;
 END LOOP;
 FOR r IN SELECT c.* FROM app.admin_sessions c WHERE c.user_id IN(SELECT admin_user_id FROM app.admin_principal_links WHERE user_id=p.subject_id) ORDER BY c.token_hash LIMIT 40 FOR UPDATE LOOP
  SELECT to_jsonb(s) INTO b FROM private.bff_sessions s WHERE s.token_hash=r.token_hash FOR UPDATE;
  DELETE FROM app.admin_sessions WHERE token_hash=r.token_hash;
  PERFORM private._retention_row_record_delta_v2(p.id,p_operation,'admin_sessions',to_jsonb(r),NULL);cookies:=cookies+1;
  IF b IS NOT NULL THEN
   DELETE FROM private.bff_sessions WHERE token_hash=r.token_hash;
   PERFORM private._retention_row_record_delta_v2(p.id,p_operation,'private:bff_sessions',b,NULL);custody:=custody+1;
  END IF;
 END LOOP;
 IF p.policy_raw::jsonb->'copy_inventory'->>'bff_access_revocation'='allow' THEN
  FOR r IN SELECT * FROM private.bff_sessions WHERE auth_user_id=principal ORDER BY token_hash LIMIT greatest(40-custody,0) FOR UPDATE LOOP
   DELETE FROM private.bff_sessions WHERE token_hash=r.token_hash;
   PERFORM private._retention_row_record_delta_v2(p.id,p_operation,'private:bff_sessions',to_jsonb(r),NULL);custody:=custody+1;
  END LOOP;
 END IF;
 SELECT(SELECT count(*) FROM app.auth_sessions WHERE user_id=p.subject_id AND revoked_at IS NULL)+
  (SELECT count(*) FROM app.admin_sessions WHERE user_id IN(SELECT admin_user_id FROM app.admin_principal_links WHERE user_id=p.subject_id))+
  (SELECT count(*) FROM private.bff_sessions WHERE auth_user_id=principal) INTO remaining;
 RETURN jsonb_build_object('verified',remaining=0,'disposition',CASE WHEN remaining=0 THEN 'access_quarantined' ELSE 'access_quarantine_chunk_verified' END,
  'sessions_revoked',revoked,'cookies_revoked',cookies,'custody_revoked',custody,'access_rows_remaining',remaining,'session_reapproval_required',true);
END$$;

CREATE FUNCTION private._retention_row_erase_chunk_v2(p_plan uuid,p_operation uuid,p_class text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE p private.retention_row_plans%ROWTYPE;r record;key_column text;deleted bigint;remaining bigint;absent bigint;changed integer:=0;
BEGIN
 SELECT * INTO STRICT p FROM private.retention_row_plans WHERE id=p_plan;
 IF p_class NOT IN('notification_devices','notification_preferences','notification_events','support_requests') THEN RAISE EXCEPTION 'retention_row_adapter_unavailable' USING ERRCODE='42501';END IF;
 key_column:=CASE WHEN p_class='notification_preferences' THEN 'user_id' ELSE 'id' END;
 FOR r IN EXECUTE format('SELECT r.%I::text AS row_id,to_jsonb(r) AS body FROM app.%I r WHERE r.user_id=$1 ORDER BY r.%I LIMIT 40 FOR UPDATE',key_column,p_class,key_column) USING p.subject_id LOOP
  EXECUTE format('DELETE FROM app.%I r WHERE r.user_id=$1 AND r.%I::text=$2 AND to_jsonb(r)=$3',p_class,key_column) USING p.subject_id,r.row_id,r.body;
  GET DIAGNOSTICS deleted=ROW_COUNT;
  IF deleted<>1 THEN RAISE EXCEPTION 'retention_row_preimage_changed' USING ERRCODE='42501';END IF;
  PERFORM private._retention_row_record_delta_v2(p.id,p_operation,p_class,r.body,NULL);changed:=changed+1;
 END LOOP;
 EXECUTE format('SELECT count(*) FROM app.%I WHERE user_id=$1',p_class) INTO remaining USING p.subject_id;
 SELECT count(*) INTO absent FROM private.retention_row_effects WHERE plan_id=p.id AND class_name=p_class AND after_descriptor IS NULL;
 IF absent+remaining<>(p.targets->>p_class)::bigint THEN RAISE EXCEPTION 'retention_row_target_count_changed' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('verified',remaining=0,'disposition',CASE WHEN remaining=0 THEN 'own_rows_absence_verified' ELSE 'own_rows_chunk_absence_verified' END,
  'rows_changed',changed,'rows_erased_or_confirmed_absent',absent,'rows_remaining',remaining);
END$$;

CREATE FUNCTION private.retention_execute_rows_v2(p_operation uuid,p_claim uuid,p_fence bigint,p_policy_sha text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;sid text;p private.retention_row_plans%ROWTYPE;c private.retention_row_claims%ROWTYPE;old private.retention_row_operations%ROWTYPE;m private.retention_inventory_manifests%ROWTYPE;
 fingerprint text;outcome jsonb;action text;guard text:=gen_random_uuid()::text;at bigint;next_state text;complete boolean;item record;remaining bigint;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);sid:=api.current_session_id();
 IF p_operation IS NULL OR p_claim IS NULL OR p_fence IS NULL OR p_fence NOT BETWEEN 1 AND 1000000000 THEN RAISE EXCEPTION 'retention_row_input_invalid' USING ERRCODE='22023';END IF;
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('operation',p_operation,'claim',p_claim,'fence',p_fence,'policy_pin',p_policy_sha,'actor',actor,'session',sid)::text,'UTF8')),'hex');
 SELECT * INTO old FROM private.retention_row_operations WHERE operation_id=p_operation;
 IF FOUND THEN
  IF old.input_sha256<>fingerprint THEN RAISE EXCEPTION 'retention_row_operation_conflict' USING ERRCODE='42501';END IF;
  RETURN old.outcome;
 END IF;
 SELECT * INTO c FROM private.retention_row_claims WHERE id=p_claim;
 IF NOT FOUND OR c.actor_id<>actor OR c.session_id<>sid OR c.fence<>p_fence THEN RAISE EXCEPTION 'retention_row_claim_unavailable' USING ERRCODE='42501';END IF;
 SELECT * INTO p FROM private.retention_row_plans WHERE id=c.plan_id;
 IF p.subject_id=actor THEN RAISE EXCEPTION 'retention_row_independent_review_required' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('retention-row-subject:'||p.subject_id,0));
 p:=private._retention_row_gate_v2(c.plan_id,true);
 IF p.policy_sha256 IS DISTINCT FROM p_policy_sha THEN RAISE EXCEPTION 'retention_row_policy_pin_changed' USING ERRCODE='42501';END IF;
 at:=extract(epoch FROM clock_timestamp())::bigint;
 IF p.active_claim IS DISTINCT FROM c.id OR p.fence<>p_fence OR c.expires_seconds<=at THEN RAISE EXCEPTION 'retention_row_claim_stale' USING ERRCODE='42501';END IF;
 SELECT * INTO m FROM private.retention_inventory_manifests WHERE id=p.manifest_id;
 action:=p.policy_raw::jsonb->'rules'->c.class_name->>'action';
 IF action='blocked' OR(p.policy_raw::jsonb->'rules'->c.class_name->>'deadline')::timestamptz>clock_timestamp() AND action IN('erase','quarantine') THEN
  RAISE EXCEPTION 'retention_row_disposition_not_due' USING ERRCODE='42501';END IF;
 INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) VALUES(guard,p.app_plan_id,c.class_name,1);
 IF c.class_name='access' AND action='quarantine' THEN
  outcome:=private._retention_row_quarantine_v2(p.id,p_operation);
  next_state:=CASE WHEN(outcome->>'verified')::boolean THEN CASE WHEN p.state='completed' THEN 'completed' ELSE 'quarantined' END ELSE 'quarantining' END;
 ELSE
  IF p.state NOT IN('quarantined','processing','completed') OR NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers WHERE subject_id=p.subject_id)
   OR EXISTS(SELECT 1 FROM app.users WHERE id=p.subject_id AND access_status='active')
   OR EXISTS(SELECT 1 FROM app.auth_sessions WHERE user_id=p.subject_id AND revoked_at IS NULL)
   OR EXISTS(SELECT 1 FROM app.admin_sessions WHERE user_id IN(SELECT admin_user_id FROM app.admin_principal_links WHERE user_id=p.subject_id)) THEN
   RAISE EXCEPTION 'retention_row_access_quarantine_required' USING ERRCODE='42501';END IF;
  IF action='erase' THEN outcome:=private._retention_row_erase_chunk_v2(p.id,p_operation,c.class_name);
  ELSIF action='retain' THEN outcome:=jsonb_build_object('verified',true,'disposition','own_rows_retained','rows_changed',0);
  ELSE RAISE EXCEPTION 'retention_row_adapter_unavailable' USING ERRCODE='42501';END IF;
  next_state:=CASE WHEN p.state='completed' THEN 'completed' ELSE 'processing' END;
 END IF;
 DELETE FROM app.privacy_retention_guards WHERE id=guard;
 -- Normalize only journaled exact deltas and recheck every original scoped
 -- class. A changed ledger, new source row or lost updated row rolls back the
 -- entire chunk, including its deletion, barrier and outcome record.
 PERFORM private._retention_row_source_guard_v2(p.id);
 complete:=next_state NOT IN('planned','quarantining');
 FOR item IN SELECT * FROM jsonb_each(p.targets) LOOP
  IF p.policy_raw::jsonb->'rules'->item.key->>'action'='erase' THEN
   EXECUTE format('SELECT count(*) FROM app.%I WHERE user_id=$1',item.key) INTO remaining USING p.subject_id;
   IF remaining<>0 THEN complete:=false;END IF;
  END IF;
 END LOOP;
 IF complete THEN next_state:='completed';END IF;
 outcome:=outcome||jsonb_build_object('contract_version',2,'scope','approved_sql_row_disposition','plan_id',p.id,'claim_id',c.id,'operation_id',p_operation,
  'class_name',c.class_name,'fence',c.fence,'source_id',m.source_sha256,'policy_sha256',p.policy_sha256,'manifest_sha256',m.manifest_sha256,
  'eligible_sql_dispositions_verified',complete,'scoped_financial_journal_preserved',true,'observation_only',true,'currentness_not_asserted',true,
  'erasure_completed',false,'all_data_erased',false,'all_actual_copy_outcomes_verified',false,'physical_objects_verified',false);
 INSERT INTO private.retention_row_operations(operation_id,plan_id,claim_id,fence,actor_id,session_id,input_sha256,outcome,recorded_seconds)
 VALUES(p_operation,p.id,c.id,c.fence,actor,sid,fingerprint,outcome,extract(epoch FROM clock_timestamp())::bigint);
 UPDATE private.retention_row_plans SET state=next_state,revision=revision+1,active_claim=NULL WHERE id=p.id;
 UPDATE app.privacy_retention_plans SET state=CASE WHEN complete THEN 'disposition_verified' ELSE 'processing' END,revision=revision+1 WHERE id=p.app_plan_id;
 RETURN outcome;
END$$;

CREATE FUNCTION private.retention_rows_status_v2(p_plan uuid,p_verify_current boolean,p_policy_sha text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;p private.retention_row_plans%ROWTYPE;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 SELECT * INTO p FROM private.retention_row_plans WHERE id=p_plan;
 IF NOT FOUND OR actor=p.subject_id OR p_verify_current IS NULL THEN RAISE EXCEPTION 'retention_row_plan_unavailable' USING ERRCODE='42501';END IF;
 IF p_verify_current THEN
  IF p.policy_sha256 IS DISTINCT FROM p_policy_sha THEN RAISE EXCEPTION 'retention_row_policy_pin_changed' USING ERRCODE='42501';END IF;
  PERFORM private._retention_row_gate_v2(p.id,false);
 END IF;
 RETURN private._retention_row_status_v2(p.id,p_verify_current);
END$$;

CREATE FUNCTION private.retention_rows_operation_v2(p_kind text,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;plan uuid;receipt jsonb;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF p_kind IS NULL OR p_kind NOT IN('plan','claim','execute') OR p_operation IS NULL THEN RAISE EXCEPTION 'retention_row_input_invalid' USING ERRCODE='22023';END IF;
 IF p_kind='plan' THEN
  SELECT id INTO plan FROM private.retention_row_plans WHERE id=p_operation;
  IF plan IS NOT NULL THEN receipt:=private._retention_row_status_v2(plan,false);END IF;
 ELSIF p_kind='claim' THEN
  SELECT c.plan_id,jsonb_build_object('claim_id',c.id,'operation_id',c.operation_id,'plan_id',c.plan_id,'class_name',c.class_name,'fence',c.fence,'claimed_seconds',c.claimed_seconds,'expires_seconds',c.expires_seconds) INTO plan,receipt FROM private.retention_row_claims c WHERE operation_id=p_operation;
 ELSE SELECT plan_id,outcome INTO plan,receipt FROM private.retention_row_operations WHERE operation_id=p_operation;
 END IF;
 IF plan IS NOT NULL AND EXISTS(SELECT 1 FROM private.retention_row_plans WHERE id=plan AND subject_id=actor) THEN RAISE EXCEPTION 'retention_row_independent_review_required' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('contract_version',2,'scope','sql_row_operation_receipt','operation_kind',p_kind,'operation_id',p_operation,'observed',plan IS NOT NULL,'receipt',receipt,
  'currentness_not_asserted',true,'erasure_completed',false,'all_data_erased',false);
END$$;
