-- CANDIDATE ONLY. Apply only after independent review in the fenced,
-- drained, source-qualified Cloud cutover. Recovery remains OFF.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR (SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') FROM supabase_migrations.schema_migrations
   WHERE version='20261117220000') IS DISTINCT FROM '870284f6146cf4c1a5ee428e5883c378cd30036333a5da5f062e97d00deefd46'
  OR to_regprocedure('private.burimunsi_held_v2_ready(text,bigint,text)') IS NOT NULL
  OR to_regprocedure('private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint)') IS NOT NULL
  OR to_regprocedure('private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'sms_held_v2_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;
CREATE FUNCTION private.burimunsi_held_v2_ready(p_source text,p_generation bigint,p_migration_sha text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;consent private.burimunsi_observation_consents%ROWTYPE;
 prior text:=current_setting('burimunsi.observation_frame',true);
 trigger_ok boolean;tables_ok boolean;resume_ok boolean;index_ok boolean;
 read_mode boolean:=current_setting('transaction_read_only')='on';
BEGIN
 IF read_mode THEN
  IF current_setting('transaction_isolation') IS DISTINCT FROM 'repeatable read' THEN
   RAISE EXCEPTION 'sms_held_v2_read_snapshot_required' USING ERRCODE='25006';END IF;
  PERFORM private._collect_fence_require_runtime();
 ELSE
  PERFORM private.burimunsi_setup_fence();
  PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 END IF;
 IF p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' OR p_migration_sha IS NULL OR p_migration_sha !~ '^[a-f0-9]{64}$'
  OR p_generation IS NULL OR p_generation NOT BETWEEN 1 AND 9007199254740991
  OR (NOT read_mode AND p_source IS DISTINCT FROM current_setting('collect.fence_source_sha256',true)) THEN
  RAISE EXCEPTION 'sms_held_v2_invalid' USING ERRCODE='22023';END IF;
 IF NOT read_mode THEN
  PERFORM private.collect_fence_assert_write(NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid,
   NULLIF(current_setting('collect.fence_epoch',true),'')::bigint,p_source);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control c WHERE c.singleton AND c.mode='open'
  AND c.source_sha256=p_source AND (read_mode OR c.epoch=NULLIF(current_setting('collect.fence_epoch',true),'')::bigint)) THEN
  RAISE EXCEPTION 'sms_held_v2_source_changed' USING ERRCODE='55000';END IF;
 actor:=private.burimunsi_observation_actor(true);
 IF actor->>'collectionId' IS DISTINCT FROM current_setting('burimunsi.collection_id',true) THEN
  RAISE EXCEPTION 'sms_held_v2_scope_changed' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 IF read_mode THEN
  SELECT * INTO consent FROM private.burimunsi_observation_consents c
   WHERE c.collection_id=actor->>'collectionId' AND c.account_id=(actor->>'accountId')::uuid
    AND c.installation_id=(actor->>'installationId')::uuid;
 ELSE
  SELECT * INTO consent FROM private.burimunsi_observation_consents c
   WHERE c.collection_id=actor->>'collectionId' AND c.account_id=(actor->>'accountId')::uuid
    AND c.installation_id=(actor->>'installationId')::uuid FOR SHARE;
 END IF;
 IF NOT FOUND OR consent.enabled IS DISTINCT FROM true OR consent.generation IS DISTINCT FROM p_generation
  OR consent.grant_id IS DISTINCT FROM (actor->>'grantId')::uuid
  OR consent.grant_version IS DISTINCT FROM (actor->>'grantVersion')::bigint THEN
  RAISE EXCEPTION 'sms_held_v2_consent_changed' USING ERRCODE='40001';END IF;
 IF EXISTS(SELECT 1 FROM (VALUES
  ('20261117205959','7a03e8d4e35b7be99c9bf072b4f835654809e582aa8e3247f45582dd686f225c'),
  ('20261117210000','1decb00238e969e2ad58b7283741bae10a968e7affbddbaf21dc196667a29651'),
  ('20261117220000','870284f6146cf4c1a5ee428e5883c378cd30036333a5da5f062e97d00deefd46'),
  ('20261117220639',p_migration_sha)) e(version,digest)
  LEFT JOIN supabase_migrations.schema_migrations m ON m.version=e.version
  WHERE encode(sha256(convert_to(m.statements[1],'UTF8')),'hex') IS DISTINCT FROM e.digest) THEN
  RAISE EXCEPTION 'sms_held_v2_migration_changed' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM (VALUES
  ('private.collect_sms_held_authorize(text,jsonb)','c5a843a9d22d62ab475608aefeb44ac4c9fde490207dffd2fb5dddb2c3b93ec7'),
  ('private.collect_sms_held_payload_guard()','7f2acd3cdba5b0b2236cc6c4d8e321477b85e652908adb49c86bb830f4fd54ef'),
  ('private.collect_sms_held_upload_guard()','297ce148372422ddeb58b29735ec449e63dd61340c8c525a497f2fcc7e646fe1'),
  ('private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz)','fa97f3f72d863a8fd715cd63889ca65accfc4563e062f3b5e4798ed0a00a6a7a'),
  ('private.burimunsi_auto_snapshot(text)','526606c23ad6d8a3b511136a8eff9e2ddf5f7a775f068b5ce8615c02a7a90dd6'),
  ('private.burimunsi_auto_candidates(text)','156a2179d3e2065e9116985f3d1a88b034a8cf8c26a988fd48f9ccccc665192f'),
  ('private.burimunsi_native_work_candidates(uuid,integer)','d218510947003efd8721305b84afb16b60b69a93308bbef4c85b69095a1514ea'),
  ('private.burimunsi_native_sms_post_candidates(integer)','0b0778810e6e86f83dc7cbc950b2aa9b258a7e6ee2d1a3c85c48e8ce41e4521e'),
  ('private.collect_sms_held_source_guard()','a3029d9460cc7f515aed5096cde699ee120e95537a3e5261893a5e09b52f9cc0'),
  ('private.collect_sms_recovery_held(text)','353a9c76dfe04e60f62ddd005dddcba1f4da423fa48113284f733d134e0ac3ca'),
  ('private.collect_sms_recovery_work_guard()','d34eb5497661179bd817c73fb981b2fec215d2ccf773b03cbfba520f5d183b87'),
  ('private.collect_sms_recovery_raw_work_guard()','339cb3e77b644ddb359e74b6847a1698bbee4c3023caaf3a7118c2a8b8d13b6d'),
  ('private.collect_sms_recovery_transaction_matches(text,text)','d0eb949bf0e1547abd080e13262df14004e4225a2e50958d014d4f91703650ad'),
  ('private.collect_sms_recovery_scope_guard()','981338e7866ed560955ad98627f0f2eddb84f0e9e142b57521429740009a4a18'),
  ('private.collect_sms_recovery_financial_guard()','0bbe97cd0928561597413749053a9e7ef2a5b1c8569e985be0337f38d5347e71'),
  ('private.collect_sms_witness_immutable()','8002c6a0cb39fc691c5027ece5e1af15458334805ab25ecef9cc67f9ca43cc2c'),
  ('private.collect_sms_request_witness_guard()','ccf51907a4e2ff6107c925b6cf9a34c2fba58786c48907c5033362cba4d388cc'),
  ('private.collect_sms_payload_witness_guard()','4d6bac36fc6b05c7f947459cb47d58287a4191080ad07fc091c9663c4b287155'),
  ('private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text)','08604196e97299947b1dac9237297d00566959cfce18963c4c4e785ed3a813e1'),
  ('private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)','9d4ab9d548e4d544a918f81f4b0072389de1abee6c070492d4d3609137c6bd8a'),
  ('private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)','573323471c79766de7dbe908aec97bb29eede153cdd066e89308ee75ee8f86c5'),
  ('private.burimunsi_observation_actor(boolean)','e6f1bf1db6c84209a8bf00465201e1db997dc8c03a972399af7e6fcb48f4f9e1'),
  ('private.burimunsi_observation_consent_current()','4c7f0cea13f47ef0a040c36e3059ded889f42932f0696a554513bf470fa060f9'),
  ('private.burimunsi_observation_own(text,boolean)','f306b9c50fafa238f64816bf7a242a21d9f828ad9df5a8c565ada001b15aa7d1'),
  ('private.burimunsi_observation_lookup(uuid,text)','bda49fee71b6944325a1fa9d7d884016a00691f4a9a4a0b0f7212a4fb50c71ae'),
  ('private.burimunsi_observation_reconcile_status()','dbc081cd16057fb2bf07da3514aab3b3afe4e7d35427651bd8187da0e809c30e'),
  ('private.burimunsi_observation_reconcile_verified_status()','9a8ed9eed540ff7eac74a85ae3765fb10e8eb1b81d3017046eccc62f0d46f4b0'),
  ('private.burimunsi_observation_context()','013e4eaba3a764365b0762d4d83decd3e0563ad89ebcb57518630f87b702b370'),
  ('private.burimunsi_observation_key_prepare(text,text,text,uuid,text,text,text,text,bigint)','4d921a1bbfe2b4ac096e4419a5d9ed5d6b43ac2af8de88faf07cffd7d45c89ea'),
  ('private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text)','96216aa4f5d3107aa08678ead3bf49b1cdc9e60dda2321475176b85f06fe3ce0')
,
  ('private._collect_fence_no_erasure()','36d8e62e234269e7b637fd276c2e08f393e2506abb41bd907b5cd60887ebe149'),
  ('private._collect_fence_statement()','0b886c44b329012c91e5eb85fce1a160a60e4172e016a284f2c280121b0a217d'),
  ('private.burimunsi_setup_fence()','abe658b11beb1688cd05474d58c7c82399cdbdd2a2ff88aa45630f6b2bd5a8d3')
 ) e(signature,digest) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 LEFT JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid IS NULL OR p.proowner IS DISTINCT FROM 'postgres'::regrole::oid OR NOT p.prosecdef OR p.provolatile IS DISTINCT FROM 'v' OR l.lanname<>'plpgsql'
  OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, pg_temp']::text[]
  OR encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') IS DISTINCT FROM e.digest
  OR (e.signature=ANY(ARRAY['private.burimunsi_auto_snapshot(text)','private.burimunsi_auto_candidates(text)','private.collect_sms_held_source_guard()','private.collect_sms_recovery_held(text)','private.collect_sms_recovery_work_guard()','private.collect_sms_recovery_raw_work_guard()','private.collect_sms_recovery_transaction_matches(text,text)','private.collect_sms_recovery_scope_guard()','private.collect_sms_recovery_financial_guard()','private.collect_sms_witness_immutable()','private.collect_sms_request_witness_guard()','private.collect_sms_payload_witness_guard()','private.collect_sms_held_upload_guard()','private.collect_sms_held_payload_guard()','private.burimunsi_observation_actor(boolean)','private._collect_fence_no_erasure()','private._collect_fence_statement()','private.burimunsi_setup_fence()']::text[]) AND p.proacl::text IS DISTINCT FROM '{postgres=X/postgres}')
  OR (e.signature=ANY(ARRAY['private.burimunsi_native_work_candidates(uuid,integer)','private.burimunsi_native_sms_post_candidates(integer)','private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text)','private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)','private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)','private.burimunsi_observation_consent_current()','private.burimunsi_observation_own(text,boolean)','private.burimunsi_observation_lookup(uuid,text)','private.burimunsi_observation_reconcile_status()','private.burimunsi_observation_reconcile_verified_status()','private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz)','private.collect_sms_held_authorize(text,jsonb)','private.burimunsi_observation_context()','private.burimunsi_observation_key_prepare(text,text,text,uuid,text,text,text,text,bigint)','private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text)']::text[]) AND p.proacl::text IS DISTINCT FROM '{postgres=X/postgres,collect_runtime=X/postgres}')
  OR has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE')
  OR has_function_privilege('service_role',p.oid,'EXECUTE') OR has_function_privilege('collect_importer',p.oid,'EXECUTE')
  OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE x.grantee=0)
  OR EXISTS(SELECT 1 FROM pg_roles r
 WHERE NOT r.rolsuper AND r.rolname NOT IN('postgres','collect_runtime')
 AND (has_function_privilege(r.oid,p.oid,'EXECUTE') OR
  (pg_has_role(r.oid,'collect_runtime','MEMBER') AND NOT (
   r.rolname='cli_login_postgres' AND r.rolcanlogin AND NOT r.rolinherit
   AND NOT r.rolcreaterole AND NOT r.rolcreatedb AND NOT r.rolreplication AND NOT r.rolbypassrls
   AND EXISTS(SELECT 1 FROM pg_roles owner_role WHERE owner_role.rolname='postgres'
    AND NOT owner_role.rolsuper AND owner_role.rolcanlogin AND owner_role.rolinherit
    AND owner_role.rolcreaterole AND owner_role.rolbypassrls)
   AND (SELECT count(*) FROM pg_auth_members d WHERE d.member=r.oid)=1
   AND EXISTS(SELECT 1 FROM pg_auth_members d WHERE d.member=r.oid AND d.roleid=to_regrole('postgres')
    AND d.grantor=to_regrole('supabase_admin') AND NOT d.admin_option AND NOT d.inherit_option AND d.set_option)
   AND (SELECT count(*) FROM pg_auth_members d WHERE d.member=to_regrole('postgres')
    AND d.roleid=to_regrole('collect_runtime'))=2
   AND EXISTS(SELECT 1 FROM pg_auth_members d WHERE d.member=to_regrole('postgres') AND d.roleid=to_regrole('collect_runtime')
    AND d.grantor=to_regrole('postgres') AND NOT d.admin_option AND NOT d.inherit_option AND d.set_option)
   AND EXISTS(SELECT 1 FROM pg_auth_members d WHERE d.member=to_regrole('postgres') AND d.roleid=to_regrole('collect_runtime')
    AND d.grantor=to_regrole('supabase_admin') AND d.admin_option AND NOT d.inherit_option AND NOT d.set_option)
  )))
)) THEN
  RAISE EXCEPTION 'sms_held_v2_guard_changed' USING ERRCODE='55000';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
  WHERE p.oid=to_regprocedure('private.trg_storage_identity()') AND p.proowner='postgres'::regrole
   AND NOT p.prosecdef AND p.provolatile='v' AND l.lanname='plpgsql'
   AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='2d1816d30d91303bb7f4e4df4a3cae5c3913f0d2a147da8bb057628d2e4ccddf') THEN
  RAISE EXCEPTION 'sms_held_v2_guard_changed' USING ERRCODE='55000';END IF;
 SELECT checks.triggers_ok,checks.tables_ok INTO trigger_ok,tables_ok FROM (WITH expected(relation_name,trigger_name,function_name,trigger_type,deferred) AS (VALUES
 ('app.sms_receipts','collect_sms_held_source_guard','private.collect_sms_held_source_guard()',23,false),
 ('private.burimunsi_auto_sms_jobs','collect_sms_recovery_work_guard','private.collect_sms_recovery_work_guard()',31,false),
 ('private.burimunsi_native_financial_work','collect_sms_recovery_work_guard','private.collect_sms_recovery_work_guard()',31,false),
 ('app.momo_processing_jobs','collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()',31,false),
 ('app.momo_parse_attempts','collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()',31,false),
 ('app.momo_transaction_sources','collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()',31,false),
 ('private.burimunsi_transaction_scopes','collect_sms_recovery_scope_guard','private.collect_sms_recovery_scope_guard()',23,false),
 ('app.momo_financial_links','collect_sms_recovery_financial_guard','private.collect_sms_recovery_financial_guard()',23,false),
 ('app.payments','collect_sms_recovery_financial_guard','private.collect_sms_recovery_financial_guard()',19,false),
 ('private.burimunsi_observation_requests','collect_sms_request_witness_guard','private.collect_sms_request_witness_guard()',5,true),
 ('private.storage_payload_reservations','collect_sms_payload_witness_guard','private.collect_sms_payload_witness_guard()',7,false),
 ('private.collect_sms_witnesses','collect_sms_witness_immutable','private.collect_sms_witness_immutable()',19,false),
 ('private.burimunsi_recovered_sms_holds','recovered_sms_hold_immutable','private._collect_fence_no_erasure()',18,false),
 ('private.collect_sms_witnesses','collect_fence_statement_v1','private._collect_fence_statement()',62,false),
 ('private.burimunsi_recovered_sms_holds','collect_fence_statement_v1','private._collect_fence_statement()',62,false),
 ('private.collect_sms_witnesses','collect_sms_no_erasure','private._collect_fence_no_erasure()',42,false),
 ('private.burimunsi_recovered_sms_holds','collect_sms_no_erasure','private._collect_fence_no_erasure()',42,false)
), checked_triggers AS (
 SELECT e.*,coalesce(t.tgfoid=to_regprocedure(e.function_name) AND t.tgenabled='A' AND NOT t.tgisinternal
  AND t.tgtype::int=e.trigger_type AND t.tgdeferrable=e.deferred AND t.tginitdeferred=e.deferred
  AND (t.tgconstraint<>0)=e.deferred AND t.tgqual IS NULL AND t.tgnargs=0
  AND CASE WHEN e.relation_name='app.payments' THEN t.tgattr::text=(SELECT a.attnum::text FROM pg_attribute a
   WHERE a.attrelid=t.tgrelid AND a.attname='collection_id' AND NOT a.attisdropped) ELSE t.tgattr::text='' END,false) ok
 FROM expected e LEFT JOIN pg_trigger t ON t.tgrelid=to_regclass(e.relation_name) AND t.tgname=e.trigger_name
), checked_tables AS (
 SELECT n.relation_name,coalesce(c.relkind='r' AND c.relowner='postgres'::regrole AND c.relrowsecurity AND c.relforcerowsecurity
  AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime']) role_name
   CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) privilege_name
   WHERE has_table_privilege(role_name,c.oid,privilege_name))
  AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl WHERE acl.grantee=0)
  AND (SELECT count(*)=1 AND bool_and(p.polname='collect_sms_witness_owner_frame' AND p.polcmd='*'
    AND p.polpermissive AND p.polroles=ARRAY['postgres'::regrole::oid]
    AND pg_get_expr(p.polqual,p.polrelid)='((current_setting(''role''::text, true) = ''collect_runtime''::text) AND (current_setting(''collect.edge_verified''::text, true) = ''true''::text) AND (current_setting(''collect.sms_witness_frame''::text, true) = ''1''::text))' AND pg_get_expr(p.polwithcheck,p.polrelid)='((current_setting(''role''::text, true) = ''collect_runtime''::text) AND (current_setting(''collect.edge_verified''::text, true) = ''true''::text) AND (current_setting(''collect.sms_witness_frame''::text, true) = ''1''::text))')
   FROM pg_policy p WHERE p.polrelid=c.oid),false) ok
 FROM (VALUES('private.collect_sms_witnesses'),('private.burimunsi_recovered_sms_holds')) n(relation_name)
 LEFT JOIN pg_class c ON c.oid=to_regclass(n.relation_name)
) SELECT (SELECT count(*)=17 AND bool_and(ok) FROM checked_triggers) triggers_ok,
 (SELECT count(*)=2 AND bool_and(ok) FROM checked_tables) tables_ok) checks;
 SELECT checks.ok INTO resume_ok FROM (WITH expected(relation_name,trigger_name,function_name,trigger_type) AS (VALUES
 ('private.storage_payload_reservations','collect_sms_held_payload_guard','private.collect_sms_held_payload_guard()',7),
 ('private.storage_upload_attempts','collect_sms_held_upload_guard','private.collect_sms_held_upload_guard()',7),
 ('private.storage_upload_attempts','storage_upload_identity','private.trg_storage_identity()',27),
 ('private.storage_put_intents','storage_put_identity','private.trg_storage_identity()',27)
) SELECT count(*)=4 AND bool_and(coalesce(t.tgfoid=to_regprocedure(e.function_name) AND t.tgenabled='A' AND NOT t.tgisinternal
 AND t.tgtype::int=e.trigger_type AND NOT t.tgdeferrable AND NOT t.tginitdeferred AND t.tgconstraint=0
 AND t.tgqual IS NULL AND t.tgnargs=0 AND t.tgattr::text='',false)) AS ok
 FROM expected e LEFT JOIN pg_trigger t ON t.tgrelid=to_regclass(e.relation_name) AND t.tgname=e.trigger_name) checks;
 SELECT checks.ok INTO index_ok FROM (SELECT count(*)=1 AND bool_and(c.relowner='postgres'::regrole
 AND i.indrelid=to_regclass('app.momo_transaction_sources') AND c.relkind='i' AND am.amname='btree'
 AND i.indisvalid AND i.indisready AND i.indislive AND NOT i.indisunique AND NOT i.indisexclusion
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=2 AND i.indnatts=2
 AND (SELECT array_agg(a.attname::text ORDER BY k.position) FROM unnest(i.indkey) WITH ORDINALITY k(attnum,position)
  JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum AND NOT a.attisdropped)=ARRAY['raw_sms_id','transaction_id']) ok
 FROM pg_class c JOIN pg_index i ON i.indexrelid=c.oid JOIN pg_am am ON am.oid=c.relam
 WHERE c.oid=to_regclass('app.burimunsi_momo_sources_raw_lookup')) checks;
 IF trigger_ok IS DISTINCT FROM true OR tables_ok IS DISTINCT FROM true OR resume_ok IS DISTINCT FROM true
  OR index_ok IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'sms_held_v2_catalog_changed' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(prior,''),true);
 RETURN jsonb_build_object('groupId',actor->>'collectionId','sourceSha256',p_source,
  'migrationSha256',p_migration_sha,'consentGeneration',p_generation);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
CREATE FUNCTION private.burimunsi_sms_recovery_prepare(
 p_key text,p_content text,p_body text,p_request uuid,p_fingerprint text,p_source text,
 p_profile_version text,p_profile_sha text,p_expected_consent_generation bigint,
 p_expected_source text,p_migration_sha text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private.burimunsi_held_v2_ready(p_expected_source,p_expected_consent_generation,p_migration_sha);
 RETURN private.burimunsi_observation_key_prepare(p_key,p_content,p_body,p_request,p_fingerprint,
  p_source,p_profile_version,p_profile_sha,p_expected_consent_generation);
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_held_v2_ready(text,bigint,text),
 private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_held_v2_ready(text,bigint,text),
 private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text) TO collect_runtime;
COMMIT;
