-- Candidate exact-request resume guard. The original held-recovery migration
-- remains unchanged. Apply only as part of the fenced, drained Cloud cutover.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE item record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR (SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') FROM supabase_migrations.schema_migrations
    WHERE version='20261117210000') IS DISTINCT FROM '1decb00238e969e2ad58b7283741bae10a968e7affbddbaf21dc196667a29651'
  OR to_regprocedure('private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz)') IS NOT NULL
  OR to_regprocedure('private.collect_sms_held_upload_guard()') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)')
   AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='9d4ab9d548e4d544a918f81f4b0072389de1abee6c070492d4d3609137c6bd8a')
  OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private.trg_storage_identity()')
   AND p.proowner='postgres'::regrole AND NOT p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog']
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='2d1816d30d91303bb7f4e4df4a3cae5c3913f0d2a147da8bb057628d2e4ccddf') THEN
  RAISE EXCEPTION 'sms_held_resume_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.storage_put_intents','storage_put_identity'),('private.storage_upload_attempts','storage_upload_identity')
 ) e(relation_name,trigger_name) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass(item.relation_name)
   AND t.tgname=item.trigger_name AND t.tgfoid='private.trg_storage_identity()'::regprocedure
   AND t.tgenabled IN('O','A') AND t.tgtype=27 AND NOT t.tgisinternal AND t.tgqual IS NULL
   AND t.tgnargs=0 AND t.tgconstraint=0 AND NOT t.tgdeferrable AND NOT t.tginitdeferred
   AND cardinality(t.tgattr::smallint[])=0) THEN
   RAISE EXCEPTION 'sms_held_resume_identity_changed' USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

-- Preserve every attempt as immutable evidence and keep the original
-- monotonic-attempt/unknown-outcome rules active under all replication modes.
ALTER TABLE private.storage_put_intents ENABLE ALWAYS TRIGGER storage_put_identity;
ALTER TABLE private.storage_upload_attempts ENABLE ALWAYS TRIGGER storage_upload_identity;

-- This trigger is the authority to START a provider PUT. It applies to every
-- writer and every route, not just the recovery HTTP handler. Its global lock
-- serializes it with recovery admission; the intent row and attempt history
-- serialize competing starts. A single durable attempt is the maximum even if
-- a provider later returns 404, 409, a timeout or an unknown outcome.
CREATE FUNCTION private.collect_sms_held_upload_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE intent private.storage_put_intents%ROWTYPE;held boolean;
 prior text:=current_setting('collect.sms_witness_frame',true);
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT * INTO intent FROM private.storage_put_intents WHERE operation_id=NEW.operation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'sms_held_upload_intent_missing' USING ERRCODE='55000';END IF;
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_recovered_sms_holds h WHERE h.object_key=intent.object_key) INTO held;
 IF held AND (intent.state<>'pending' OR intent.attempts<>0 OR intent.active_attempt IS NOT NULL
   OR intent.upload_unresolved OR intent.delete_tombstone
   OR EXISTS(SELECT 1 FROM private.storage_upload_attempts a WHERE a.operation_id=NEW.operation_id)) THEN
  RAISE EXCEPTION 'sms_held_upload_already_attempted' USING ERRCODE='55000';END IF;
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_held_upload_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_held_upload_guard BEFORE INSERT ON private.storage_upload_attempts
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_held_upload_guard();
ALTER TABLE private.storage_upload_attempts ENABLE ALWAYS TRIGGER collect_sms_held_upload_guard;

-- A normal capture route can also encounter an already-held deterministic
-- source. Before ANY route resumes it, revalidate the exact account, group,
-- installation, grant, fingerprint, body, inbox time and current consent.
-- A changed consent generation remains pending; it is not upload authority.
CREATE FUNCTION private.collect_sms_held_resume_check(p_source text,p_request uuid,p_fingerprint text,p_body text,p_inbox timestamptz)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE held boolean;consent jsonb;generation bigint;
 prior text:=current_setting('collect.sms_witness_frame',true);
 old_o text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM private.collect_fence_assert_write(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_recovered_sms_holds h WHERE h.source_id=p_source) INTO held;
 IF held THEN
  PERFORM private.burimunsi_sms_recovery_hold(p_source,p_request,p_fingerprint,p_body,p_inbox);
  consent:=private.burimunsi_observation_consent_current();
  PERFORM set_config('burimunsi.observation_frame','1',true);
  SELECT initial_consent_generation INTO generation FROM private.burimunsi_observation_requests WHERE source_id=p_source;
  IF consent->'enabled' IS DISTINCT FROM 'true'::jsonb OR generation IS DISTINCT FROM (consent->>'generation')::bigint THEN
   RAISE EXCEPTION 'sms_held_resume_consent_changed' USING ERRCODE='42501';END IF;
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RETURN held;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz) TO collect_runtime;
COMMIT;
