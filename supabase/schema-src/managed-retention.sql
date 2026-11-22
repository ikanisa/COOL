-- Read-only provider database inventory. Returns bounded opaque row hashes,
-- never Auth secrets/tokens/emails/factor values or object contents. Unknown
-- managed relations fail closed. Provider logs/backups/unlinked identifiers
-- are not proven absent by this scoped database observation.
CREATE FUNCTION private.retention_managed_inventory(p_subject text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE
 relation record;managed_id uuid;keys text[]:=ARRAY[]::text[];bucket_name text;
 auth_rows jsonb:='[]';storage_rows jsonb:='[]';found jsonb;schema_rows jsonb;schema_identity jsonb;
 predicate text;sql_text text;auth_status text;storage_status text;has_storage boolean;bucket_private boolean:=false;storage_count bigint:=0;
 known_auth text[]:=ARRAY['audit_log_entries','custom_oauth_providers','flow_state','identities','instances','mfa_amr_claims','mfa_challenges','mfa_factors','mfa_recovery_code_sets','mfa_recovery_codes','oauth_authorizations','oauth_client_states','oauth_clients','oauth_consents','one_time_tokens','refresh_tokens','saml_providers','saml_relay_states','schema_migrations','scim_tokens','scim_users','sessions','sso_domains','sso_providers','users','webauthn_challenges','webauthn_credentials'];
 known_storage text[]:=ARRAY['buckets','buckets_analytics','buckets_vectors','migrations','objects','s3_multipart_uploads','s3_multipart_uploads_parts','vector_indexes'];
BEGIN
 PERFORM private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF p_subject IS NOT NULL AND (length(p_subject)<1 OR length(p_subject)>200) THEN RAISE EXCEPTION 'retention_subject_invalid' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'kind',c.relkind,
  'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'foreign_keys',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid AND x.contype='f')) ORDER BY n.nspname,c.relname),'[]') INTO schema_rows
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('auth','storage') AND c.relkind IN('r','p');
 FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('auth','storage') AND c.relkind IN('r','p') LOOP
  IF (relation.nspname='auth' AND NOT relation.relname=ANY(known_auth)) OR (relation.nspname='storage' AND NOT relation.relname=ANY(known_storage)) THEN RAISE EXCEPTION 'retention_unknown_managed_relation' USING ERRCODE='42501';END IF;
 END LOOP;
 schema_identity:=jsonb_build_object('sha256',encode(sha256(convert_to(schema_rows::text,'UTF8')),'hex'),'contract','collect.managed.inventory.v1');
 SELECT auth_user_id INTO managed_id FROM private.auth_principal_links WHERE user_id=p_subject;
 SELECT bucket INTO bucket_name FROM private.storage_namespace WHERE singleton;
 SELECT coalesce(array_agg(object_key ORDER BY object_key),ARRAY[]::text[]) INTO keys FROM (
  (SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=p_subject LIMIT 501)
  UNION (SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=p_subject LIMIT 501)
  UNION (SELECT object_key FROM app.payment_evidence WHERE owner_user_id=p_subject LIMIT 501)
  UNION (SELECT object_key FROM app.sms_receipts WHERE owner_user_id=p_subject LIMIT 501)
  UNION (SELECT source_object_key FROM app.roster_imports WHERE user_id=p_subject LIMIT 501)
  UNION (SELECT object_key FROM app.upload_objects WHERE user_id=p_subject LIMIT 501)
  LIMIT 501
 ) owned;
 IF cardinality(keys)>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
 FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='auth' AND c.relkind IN('r','p') ORDER BY c.relname LOOP
  predicate:=CASE relation.relname
   WHEN 'users' THEN 'r.id=$1'
   WHEN 'refresh_tokens' THEN 'r.user_id=$1::text OR r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'flow_state' THEN 'r.user_id=$1 OR to_jsonb(r)->>''linking_target_id''=$1::text'
   WHEN 'mfa_amr_claims' THEN 'r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'mfa_challenges' THEN 'r.factor_id IN(SELECT id FROM auth.mfa_factors WHERE user_id=$1)'
   WHEN 'mfa_recovery_codes' THEN 'r.mfa_recovery_code_set_id IN(SELECT id FROM auth.mfa_recovery_code_sets WHERE user_id=$1)'
   WHEN 'oauth_client_states' THEN 'r.id IN(SELECT (to_jsonb(f)->>''oauth_client_state_id'')::uuid FROM auth.flow_state f WHERE f.user_id=$1 OR to_jsonb(f)->>''linking_target_id''=$1::text)'
   WHEN 'saml_relay_states' THEN 'r.flow_state_id IN(SELECT id FROM auth.flow_state WHERE user_id=$1)'
   WHEN 'audit_log_entries' THEN 'r.payload::jsonb->>''actor_id''=$1::text OR r.payload::jsonb->>''user_id''=$1::text'
   WHEN 'custom_oauth_providers' THEN NULL WHEN 'instances' THEN NULL WHEN 'oauth_clients' THEN NULL WHEN 'saml_providers' THEN NULL WHEN 'schema_migrations' THEN NULL WHEN 'scim_tokens' THEN NULL WHEN 'sso_domains' THEN NULL WHEN 'sso_providers' THEN NULL
   ELSE 'r.user_id=$1' END;
  -- Shared provider configuration has no subject ownership column. Its schema
  -- is bound above; its contents are not represented as erased subject copies.
  IF predicate IS NULL OR managed_id IS NULL THEN CONTINUE;END IF;
  sql_text:=format('SELECT coalesce(jsonb_agg(jsonb_build_object(''key_sha256'',encode(sha256(convert_to(%L||'':''||coalesce(to_jsonb(q)->>''id'',to_jsonb(q)->>''session_id'')||'':''||coalesce(to_jsonb(q)->>''authentication_method'',''''),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(q)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(q)::text,''UTF8'')),''hex''),''lifecycle'',''{}''::jsonb) ORDER BY to_jsonb(q)::text),''[]'') FROM (SELECT r.* FROM auth.%I r WHERE %s LIMIT 501) q',relation.relname,relation.relname,predicate);
  EXECUTE sql_text INTO found USING managed_id;
  auth_rows:=auth_rows||found;
  IF jsonb_array_length(auth_rows)>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
 END LOOP;
 has_storage:=to_regclass('storage.objects') IS NOT NULL AND to_regclass('storage.buckets') IS NOT NULL;
 IF has_storage AND bucket_name IS NOT NULL THEN EXECUTE 'SELECT coalesce(public=false,false) FROM storage.buckets WHERE id=$1' INTO bucket_private USING bucket_name;END IF;
 IF has_storage AND bucket_name IS NOT NULL THEN
  FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='storage' AND c.relkind IN('r','p') AND c.relname IN('objects','s3_multipart_uploads','s3_multipart_uploads_parts') ORDER BY c.relname LOOP
   predicate:=CASE relation.relname WHEN 'objects' THEN 'r.name=ANY($2) OR to_jsonb(r)->>''owner_id''=$1::text OR to_jsonb(r)->>''owner''=$1::text' ELSE 'r.key=ANY($2) OR to_jsonb(r)->>''owner_id''=$1::text' END;
   sql_text:=format('SELECT coalesce(jsonb_agg(jsonb_build_object(''key_sha256'',encode(sha256(convert_to(object_key,''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(body::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(body::text,''UTF8'')),''hex''),''lifecycle'',jsonb_build_object(''catalog_rows'',jsonb_array_length(body))) ORDER BY object_key),''[]'') FROM (SELECT %s AS object_key,jsonb_agg(jsonb_build_object(''relation'',%L,''value'',to_jsonb(r)) ORDER BY to_jsonb(r)::text) AS body FROM (SELECT * FROM storage.%I r WHERE r.bucket_id=$3 AND (%s) LIMIT 501) r GROUP BY %s) grouped',CASE WHEN relation.relname='objects' THEN 'r.name' ELSE 'r.key' END,relation.relname,relation.relname,predicate,CASE WHEN relation.relname='objects' THEN 'r.name' ELSE 'r.key' END);
   EXECUTE sql_text INTO found USING managed_id,keys,bucket_name;
   storage_count:=storage_count+(SELECT coalesce(sum((item->'lifecycle'->>'catalog_rows')::bigint),0) FROM jsonb_array_elements(found) item);
   IF storage_count>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
   storage_rows:=storage_rows||found;
   IF jsonb_array_length(storage_rows)>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
  END LOOP;
 END IF;
 -- Multiple managed mirror relations for one key are folded into one opaque
 -- descriptor, including every actual archived/version/part row observed.
 SELECT coalesce(jsonb_agg(jsonb_build_object('key_sha256',key_sha256,'row_sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex'),'identity_sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex'),'lifecycle',jsonb_build_object('mirror_groups',jsonb_array_length(items),'catalog_rows',(SELECT sum((part->'lifecycle'->>'catalog_rows')::bigint) FROM jsonb_array_elements(items) part))) ORDER BY key_sha256),'[]') INTO storage_rows
 FROM (SELECT item->>'key_sha256' AS key_sha256,jsonb_agg(item ORDER BY item::text) AS items FROM jsonb_array_elements(storage_rows) item GROUP BY item->>'key_sha256') folded;
 SELECT coalesce(jsonb_agg(item ORDER BY item->>'key_sha256'),'[]') INTO auth_rows FROM jsonb_array_elements(auth_rows) item;
 auth_status:=CASE WHEN managed_id IS NULL THEN 'unmapped' ELSE 'observed' END;
 storage_status:=CASE WHEN has_storage AND bucket_name IS NOT NULL AND bucket_private THEN 'observed' ELSE 'unavailable' END;
 RETURN jsonb_build_object('contract_version',1,'schema',schema_identity,'classes',jsonb_build_object(
  'managed:auth',jsonb_build_object('status',auth_status,'count',jsonb_array_length(auth_rows),'rows',auth_rows),
  'managed:storage',jsonb_build_object('status',storage_status,'count',storage_count,'rows',storage_rows)));
END$$;
REVOKE ALL ON FUNCTION private.retention_managed_inventory(text) FROM PUBLIC;
DO $$DECLARE r text;BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON FUNCTION private.retention_managed_inventory(text) FROM %I',r);END IF;
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.retention_managed_inventory(text) TO collect_runtime;
