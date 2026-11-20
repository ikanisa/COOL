-- Reviewed candidate BODY, not a standalone migration. Execute only through
-- the fenced owner's transaction helper, after the graph has committed. The
-- caller supplies ONE row in pg_temp.collect_initial_account_input. No PIN
-- plaintext, device token, fake BFF session or old grant is accepted here.
-- The helper must hold exclusive WORK/WRITE locks and restore its exact
-- temporary fence/RLS changes before COMMIT.
DO $bootstrap$
DECLARE x record;admin_row private.burimunsi_accounts%ROWTYPE;staff_row private.burimunsi_accounts%ROWTYPE;
 owner_admin text;owner_binding jsonb;now_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 admin_caps text[]:=ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'];
 staff_caps text[]:=ARRAY['records.read','members.enroll','payments.allocate'];
 changed integer;fingerprint text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('role',true)<>'none'
  OR current_setting('row_security')<>'on' OR to_regclass('pg_temp.collect_initial_account_input') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory' AND classid=7346371::oid
    AND objid=1::oid AND objsubid=2 AND mode='ExclusiveLock' AND granted)
  OR NOT EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory' AND classid=7346371::oid
    AND objid=2::oid AND objsubid=2 AND mode='ExclusiveLock' AND granted)
  OR (SELECT count(*) FROM pg_temp.collect_initial_account_input)<>1 THEN
  RAISE EXCEPTION 'initial_account_bootstrap_precondition' USING ERRCODE='55000';END IF;
 SELECT * INTO STRICT x FROM pg_temp.collect_initial_account_input;
 IF x.operation_id IS NULL OR x.fence_operation_id IS NULL OR coalesce(x.source_sha256 !~ '^[a-f0-9]{64}$',true)
  OR coalesce(x.authorization_sha256 !~ '^[a-f0-9]{64}$',true) OR x.owner_principal_id IS NULL
  OR x.collection_id IS NULL OR x.admin_account_id IS NULL OR x.staff_account_id IS NULL
  OR x.admin_account_id=x.staff_account_id OR coalesce(x.admin_phone !~ '^\+2507[2389][0-9]{7}$',true)
  OR coalesce(x.staff_phone !~ '^\+2507[2389][0-9]{7}$',true) OR x.admin_phone=x.staff_phone
  OR current_setting('collect.graph_import_operation',true) IS DISTINCT FROM x.operation_id::text
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control c WHERE c.singleton AND c.project_ref='rrlduytparvsjfmegalh'
   AND c.mode='fenced' AND c.epoch=x.epoch AND c.operation_id=x.fence_operation_id AND c.source_sha256=x.source_sha256)
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.state IN('active','unresolved')
   AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) THEN
  RAISE EXCEPTION 'initial_account_bootstrap_precondition' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM app.audit_log WHERE action='burimunsi.migration.initial_accounts' AND request_id=x.operation_id::text)
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes s JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
   WHERE s.collection_id=x.collection_id AND (s.enabled OR s.active_binding_id IS NULL)) THEN
  RAISE EXCEPTION 'initial_account_bootstrap_precondition' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.collection_id',x.collection_id,true);
 PERFORM set_config('burimunsi.pin_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO STRICT admin_row FROM private.burimunsi_accounts WHERE id=x.admin_account_id AND collection_id=x.collection_id FOR UPDATE;
 SELECT * INTO STRICT staff_row FROM private.burimunsi_accounts WHERE id=x.staff_account_id AND collection_id=x.collection_id FOR UPDATE;
 IF admin_row.principal_user_id IS DISTINCT FROM x.owner_principal_id OR admin_row.phone IS DISTINCT FROM x.admin_phone
  OR admin_row.role IS DISTINCT FROM 'admin' OR admin_row.active OR admin_row.removed OR admin_row.pin_hash IS DISTINCT FROM '{}'::jsonb
  OR staff_row.phone IS DISTINCT FROM x.staff_phone OR staff_row.role IS DISTINCT FROM 'staff'
  OR staff_row.active OR staff_row.removed OR staff_row.pin_hash IS DISTINCT FROM '{}'::jsonb
  OR admin_row.version>=9007199254740991 OR staff_row.version>=9007199254740991
  OR admin_row.credential_version>=9007199254740991 OR staff_row.credential_version>=9007199254740991
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_native_receipt_origins o
   JOIN private.collect_imported_native_history h ON h.source_id=o.source_id AND h.collection_id=o.collection_id
   JOIN private.collect_migration_actor_lineage l ON l.source_actor_id=o.principal_user_id AND l.cloud_primary_id=x.owner_principal_id
   WHERE o.collection_id=x.collection_id AND o.account_id=x.admin_account_id)
  OR NOT EXISTS(SELECT 1 FROM app.users u WHERE u.id=staff_row.principal_user_id AND u.access_status='active' AND u.phone=x.staff_phone)
  OR EXISTS(SELECT 1 FROM app.admin_principal_links l WHERE l.user_id=staff_row.principal_user_id)
  OR EXISTS(SELECT 1 FROM private.burimunsi_operator_approvals WHERE collection_id=x.collection_id
   AND (principal_user_id=x.owner_principal_id OR phone IN(x.admin_phone,x.staff_phone)))
  OR EXISTS(SELECT 1 FROM private.burimunsi_native_staff_delegations WHERE collection_id=x.collection_id AND principal_user_id=staff_row.principal_user_id)
  OR EXISTS(SELECT 1 FROM private.burimunsi_sessions WHERE collection_id=x.collection_id
    AND account_id IN(x.admin_account_id,x.staff_account_id) AND NOT revoked)
  OR EXISTS(SELECT 1 FROM private.burimunsi_device_accounts da JOIN private.burimunsi_device_grants d ON d.id=da.grant_id
    WHERE da.collection_id=x.collection_id AND da.account_id IN(x.admin_account_id,x.staff_account_id) AND d.active) THEN
  RAISE EXCEPTION 'initial_account_bootstrap_identity_changed' USING ERRCODE='55000';END IF;
 SELECT a.id INTO STRICT owner_admin FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  JOIN app.users u ON u.id=l.user_id JOIN private.auth_principal_links p ON p.user_id=u.id JOIN auth.users au ON au.id=p.auth_user_id
  WHERE u.id=x.owner_principal_id AND u.access_status='active' AND a.role='owner' AND a.status='active'
   AND au.email_confirmed_at IS NOT NULL AND lower(au.email)=lower(a.email) AND au.deleted_at IS NULL
   AND (au.banned_until IS NULL OR au.banned_until<=clock_timestamp()) FOR SHARE OF a,l,u,p,au;
 owner_binding:=private.collect_owner_binding();
 IF owner_binding IS NULL OR owner_binding->>'adminId' IS DISTINCT FROM owner_admin
  OR owner_binding->>'principalId' IS DISTINCT FROM x.owner_principal_id
  OR NOT coalesce(private.collect_owner_is(owner_admin,x.owner_principal_id,owner_binding->>'email'),false) THEN
  RAISE EXCEPTION 'initial_account_bootstrap_owner_changed' USING ERRCODE='55000';END IF;
 IF jsonb_typeof(x.admin_pin_hash) IS DISTINCT FROM 'object' OR jsonb_typeof(x.staff_pin_hash) IS DISTINCT FROM 'object'
  OR (SELECT count(*) FROM jsonb_object_keys(x.admin_pin_hash))<>5 OR (SELECT count(*) FROM jsonb_object_keys(x.staff_pin_hash))<>5
  OR NOT(x.admin_pin_hash ?& ARRAY['algorithm','pepperId','iterations','salt','hash'])
  OR NOT(x.staff_pin_hash ?& ARRAY['algorithm','pepperId','iterations','salt','hash'])
  OR x.admin_pin_hash->>'algorithm' IS DISTINCT FROM 'pbkdf2-sha256+hmac-v1'
  OR x.staff_pin_hash->>'algorithm' IS DISTINCT FROM 'pbkdf2-sha256+hmac-v1'
  OR jsonb_typeof(x.admin_pin_hash->'iterations') IS DISTINCT FROM 'number'
  OR jsonb_typeof(x.staff_pin_hash->'iterations') IS DISTINCT FROM 'number'
  OR x.admin_pin_hash->>'pepperId' IS DISTINCT FROM x.pepper_id OR x.staff_pin_hash->>'pepperId' IS DISTINCT FROM x.pepper_id
  OR coalesce(x.pepper_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',true)
  OR x.admin_pin_hash->>'iterations' IS DISTINCT FROM '600000' OR x.staff_pin_hash->>'iterations' IS DISTINCT FROM '600000'
  OR coalesce(x.admin_pin_hash->>'salt' !~ '^[a-f0-9]{32}$',true) OR coalesce(x.staff_pin_hash->>'salt' !~ '^[a-f0-9]{32}$',true)
  OR coalesce(x.admin_pin_hash->>'hash' !~ '^[a-f0-9]{64}$',true) OR coalesce(x.staff_pin_hash->>'hash' !~ '^[a-f0-9]{64}$',true)
  OR x.admin_pin_hash->>'salt'=x.staff_pin_hash->>'salt' THEN
  RAISE EXCEPTION 'initial_account_bootstrap_pin_invalid' USING ERRCODE='55000';END IF;
 INSERT INTO private.burimunsi_operator_approvals(collection_id,principal_user_id,admin_user_id,phone,role,capabilities,active,version,approved_by,created_at,updated_at)
  VALUES(x.collection_id,x.owner_principal_id,owner_admin,x.admin_phone,'admin',admin_caps,true,1,x.owner_principal_id,now_ms,now_ms);
 UPDATE private.burimunsi_accounts SET pin_hash=x.admin_pin_hash,capabilities=admin_caps,active=true,
  version=version+1,credential_version=credential_version+1,updated_at=now_ms
  WHERE id=x.admin_account_id AND collection_id=x.collection_id AND NOT active AND NOT removed;
 GET DIAGNOSTICS changed=ROW_COUNT;IF changed<>1 THEN RAISE EXCEPTION 'initial_account_bootstrap_changed' USING ERRCODE='40001';END IF;
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(staff_row.name,x.staff_phone,staff_caps)::text,'UTF8')),'hex');
 INSERT INTO private.burimunsi_native_staff_delegations(collection_id,principal_user_id,parent_account_id,capability_ceiling,
  created_request_id,creation_fingerprint,created_at)
  VALUES(x.collection_id,staff_row.principal_user_id,x.admin_account_id,staff_caps,x.operation_id,fingerprint,now_ms);
 UPDATE private.burimunsi_accounts SET pin_hash=x.staff_pin_hash,capabilities=staff_caps,active=true,
  version=version+1,credential_version=credential_version+1,updated_at=now_ms
  WHERE id=x.staff_account_id AND collection_id=x.collection_id AND NOT active AND NOT removed;
 GET DIAGNOSTICS changed=ROW_COUNT;IF changed<>1 THEN RAISE EXCEPTION 'initial_account_bootstrap_changed' USING ERRCODE='40001';END IF;
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(x.owner_principal_id,NULL,'burimunsi.migration.initial_accounts','collection',x.collection_id,x.operation_id::text,
   jsonb_build_object('authorization_sha256',x.authorization_sha256,'kind','owner_authorized_migration',
    'admin_account_id',x.admin_account_id,'staff_account_id',x.staff_account_id,'old_sessions_reused',false)::text,
   to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
 IF private.burimunsi_pin_authority_snapshot(x.collection_id,x.owner_principal_id,x.admin_phone,'admin',admin_caps) IS NULL
  OR private.burimunsi_pin_authority_snapshot(x.collection_id,staff_row.principal_user_id,x.staff_phone,'staff',staff_caps) IS NULL THEN
  RAISE EXCEPTION 'initial_account_bootstrap_authority_unconfirmed' USING ERRCODE='55000';END IF;
END;$bootstrap$;
