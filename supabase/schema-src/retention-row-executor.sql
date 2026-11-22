-- Distinct, explicitly approved SQL-row disposition contract. Provider and
-- physical-object erasure are unsupported and remain blocked. No activation.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR to_regclass('private.retention_inventory_manifests') IS NULL THEN
  RAISE EXCEPTION 'retention_row_owner_install_required' USING ERRCODE='55000';END IF;
END$$;
CREATE TABLE private.retention_row_plans(
 id uuid PRIMARY KEY,manifest_id uuid NOT NULL REFERENCES private.retention_inventory_manifests(id),
 app_plan_id text NOT NULL UNIQUE REFERENCES app.privacy_retention_plans(id),subject_id text NOT NULL,
 actor_id text NOT NULL,session_id text NOT NULL,input_sha256 text NOT NULL CHECK(input_sha256~'^[a-f0-9]{64}$'),
 policy_raw text NOT NULL,policy_sha256 text NOT NULL CHECK(policy_sha256~'^[a-f0-9]{64}$'),policy_revision bigint NOT NULL,
 environment text NOT NULL CHECK(environment IN('test','production','development','staging','qualification')),
 targets jsonb NOT NULL CHECK(jsonb_typeof(targets)='object'),
 state text NOT NULL DEFAULT 'planned' CHECK(state IN('planned','quarantining','quarantined','processing','completed','superseded')),
 revision bigint NOT NULL DEFAULT 0 CHECK(revision BETWEEN 0 AND 1000000000),
 fence bigint NOT NULL DEFAULT 0 CHECK(fence BETWEEN 0 AND 1000000000),active_claim uuid,superseded_by uuid,
 created_seconds bigint NOT NULL DEFAULT extract(epoch FROM clock_timestamp())::bigint,
 CHECK(encode(sha256(convert_to(policy_raw,'UTF8')),'hex')=policy_sha256),CHECK((state='superseded')=(superseded_by IS NOT NULL))
);
CREATE TABLE private.retention_row_claims(
 id uuid PRIMARY KEY,operation_id uuid NOT NULL UNIQUE,plan_id uuid NOT NULL REFERENCES private.retention_row_plans(id),
 class_name text NOT NULL CHECK(class_name IN('access','notification_devices','notification_preferences','notification_events','support_requests')),
 actor_id text NOT NULL,session_id text NOT NULL,input_sha256 text NOT NULL CHECK(input_sha256~'^[a-f0-9]{64}$'),
 expected_revision bigint NOT NULL,fence bigint NOT NULL CHECK(fence BETWEEN 1 AND 1000000000),
 claimed_seconds bigint NOT NULL,expires_seconds bigint NOT NULL,
 CHECK(expires_seconds>claimed_seconds AND expires_seconds<=claimed_seconds+120),UNIQUE(plan_id,fence)
);
ALTER TABLE private.retention_row_plans ADD CONSTRAINT retention_row_active_claim_fk FOREIGN KEY(active_claim) REFERENCES private.retention_row_claims(id) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE private.retention_row_operations(
 operation_id uuid PRIMARY KEY,plan_id uuid NOT NULL REFERENCES private.retention_row_plans(id),
 claim_id uuid NOT NULL REFERENCES private.retention_row_claims(id),fence bigint NOT NULL,
 actor_id text NOT NULL,session_id text NOT NULL,input_sha256 text NOT NULL CHECK(input_sha256~'^[a-f0-9]{64}$'),
 outcome jsonb NOT NULL CHECK(jsonb_typeof(outcome)='object'),recorded_seconds bigint NOT NULL
);
CREATE TABLE private.retention_row_effects(
 plan_id uuid NOT NULL REFERENCES private.retention_row_plans(id),operation_id uuid NOT NULL REFERENCES private.retention_row_operations(operation_id) DEFERRABLE INITIALLY DEFERRED,
 class_name text NOT NULL CHECK(class_name IN('users','auth_sessions','admin_sessions','private:bff_sessions','notification_devices','notification_preferences','notification_events','support_requests')),
 key_sha256 text NOT NULL CHECK(key_sha256~'^[a-f0-9]{64}$'),
 before_descriptor jsonb NOT NULL,after_descriptor jsonb,
 before_row_sha256 text GENERATED ALWAYS AS(before_descriptor->>'row_sha256') STORED,
 after_row_sha256 text GENERATED ALWAYS AS(after_descriptor->>'row_sha256') STORED,
 PRIMARY KEY(plan_id,class_name,key_sha256,before_row_sha256),
 UNIQUE(plan_id,class_name,key_sha256,after_row_sha256),
 CHECK(before_descriptor->>'kind'='row' AND before_descriptor->>'key_sha256'=key_sha256 AND before_descriptor->>'row_sha256'~'^[a-f0-9]{64}$'),
 CHECK(after_descriptor IS NULL OR(after_descriptor->>'kind'='row' AND after_descriptor->>'key_sha256'=key_sha256 AND after_descriptor->>'row_sha256'~'^[a-f0-9]{64}$'))
);
CREATE INDEX retention_row_subject ON private.retention_row_plans(subject_id,id);
CREATE INDEX retention_row_operation_plan ON private.retention_row_operations(plan_id,recorded_seconds,operation_id);
CREATE FUNCTION private._retention_row_plan_transition_v2() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $$BEGIN
 IF to_jsonb(NEW)-ARRAY['state','revision','fence','active_claim','superseded_by'] IS DISTINCT FROM to_jsonb(OLD)-ARRAY['state','revision','fence','active_claim','superseded_by']
  OR NEW.revision<>OLD.revision+1 OR NEW.fence NOT IN(OLD.fence,OLD.fence+1)
  OR(OLD.state IN('completed','superseded') AND NEW.state<>OLD.state) OR(OLD.superseded_by IS NOT NULL AND NEW.superseded_by IS DISTINCT FROM OLD.superseded_by)
  OR(OLD.state IN('quarantined','processing','completed') AND NEW.state IN('planned','quarantining')) THEN
  RAISE EXCEPTION 'retention_row_plan_transition_invalid' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['retention_row_plans','retention_row_claims','retention_row_effects','retention_row_operations'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',t);
  EXECUTE format('CREATE TRIGGER retention_row_immutable BEFORE %s ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._retention_manifest_immutable_v2()',CASE WHEN t='retention_row_plans' THEN 'DELETE OR TRUNCATE' ELSE 'UPDATE OR DELETE OR TRUNCATE' END,t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER retention_row_immutable',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
 END LOOP;
END$$;
CREATE TRIGGER retention_row_plan_transition BEFORE UPDATE ON private.retention_row_plans FOR EACH ROW EXECUTE FUNCTION private._retention_row_plan_transition_v2();
ALTER TABLE private.retention_row_plans ENABLE ALWAYS TRIGGER retention_row_plan_transition;

CREATE FUNCTION private._retention_row_descriptor_v2(p_class text,p_row jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$DECLARE key text;hash text;BEGIN
 IF p_class NOT IN('users','auth_sessions','admin_sessions','private:bff_sessions','notification_devices','notification_preferences','notification_events','support_requests') OR jsonb_typeof(p_row)<>'object' THEN
  RAISE EXCEPTION 'retention_row_adapter_unavailable' USING ERRCODE='42501';END IF;
 key:=CASE WHEN p_class='private:bff_sessions' THEN p_row->>'token_hash' ELSE coalesce(p_row->>'id',p_row->>'user_id',p_row::text) END;
 hash:=encode(sha256(convert_to(p_row::text,'UTF8')),'hex');
 RETURN jsonb_build_object('kind','row','key_sha256',encode(sha256(convert_to(key,'UTF8')),'hex'),'row_sha256',hash,'identity_sha256',hash,'lifecycle','{}'::jsonb);
END$$;

-- The policy is a separate, externally activated raw-byte decision. Every
-- identity and rule is exact; no endpoint can create or approve this value.
CREATE FUNCTION private._retention_row_policy_v2(p_manifest uuid,p_sha text,p_environment text,p_source text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE m private.retention_inventory_manifests%ROWTYPE;c app.runtime_config%ROWTYPE;p jsonb;r record;keys text[];expected text[];rule jsonb;deadline timestamptz;
BEGIN
 SELECT * INTO m FROM private.retention_inventory_manifests WHERE id=p_manifest;
 SELECT * INTO c FROM app.runtime_config WHERE key='privacy:retention:approved:v2';
 IF m.id IS NULL OR c.key IS NULL OR p_sha IS NULL OR p_sha!~'^[a-f0-9]{64}$' OR encode(sha256(convert_to(c.value_json,'UTF8')),'hex')<>p_sha THEN
  RAISE EXCEPTION 'retention_row_policy_unavailable' USING ERRCODE='42501';END IF;
 p:=c.value_json::jsonb;
 SELECT array_agg(k ORDER BY k) INTO keys FROM jsonb_object_keys(p) k;
 SELECT array_agg(k ORDER BY k) INTO expected FROM unnest(ARRAY['contract_version','scope','policy_id','environment','synthetic_test_only','approval_evidence_sha256','approved_by','approved_at','expires_at','source_id','schema_sha256','manifest_id','manifest_sha256','request_id','subject_id','review_revision','rules','writer_fence','copy_inventory','quarantine_continuation']) k;
 IF keys IS DISTINCT FROM expected OR EXISTS(SELECT 1 FROM jsonb_each(p) e WHERE e.value='null'::jsonb AND e.key<>'quarantine_continuation')
  OR p->'contract_version' IS DISTINCT FROM '2'::jsonb OR p->>'scope' IS DISTINCT FROM 'sql_rows_only'
  OR p->>'environment'<>p_environment OR p_environment NOT IN('test','production','development','staging','qualification')
  OR jsonb_typeof(p->'synthetic_test_only')<>'boolean' OR(p->>'synthetic_test_only')::boolean AND p_environment<>'test'
  OR p->>'policy_id' !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p->>'approved_by' !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' OR p->>'approved_by'=m.subject_id
  OR p->>'approval_evidence_sha256' !~ '^[a-f0-9]{64}$'
  OR p->>'source_id' IS DISTINCT FROM p_source OR p_source IS DISTINCT FROM m.source_sha256
  OR p->>'schema_sha256' IS DISTINCT FROM m.schema_sha256
  OR p->>'manifest_id' IS DISTINCT FROM m.id::text OR p->>'manifest_sha256' IS DISTINCT FROM m.manifest_sha256
  OR p->>'request_id' IS DISTINCT FROM m.request_id OR p->>'subject_id' IS DISTINCT FROM m.subject_id
  OR p->'review_revision' IS DISTINCT FROM m.control_identity->'review_revision'
  OR (p->>'approved_at')::timestamptz>clock_timestamp() OR(p->>'expires_at')::timestamptz<=clock_timestamp()
  OR p->>'approved_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
  OR p->>'expires_at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$' THEN
  RAISE EXCEPTION 'retention_row_policy_unavailable' USING ERRCODE='42501';END IF;
 SELECT array_agg(k ORDER BY k) INTO keys FROM jsonb_object_keys(p->'rules') k;
 SELECT array_agg(k ORDER BY k) INTO expected FROM(SELECT jsonb_object_keys(m.class_counts) AS k UNION ALL SELECT 'access') q;
 IF keys IS DISTINCT FROM expected THEN RAISE EXCEPTION 'retention_row_policy_classes_changed' USING ERRCODE='42501';END IF;
 FOR r IN SELECT * FROM jsonb_each(p->'rules') LOOP
  rule:=r.value;
  IF jsonb_typeof(rule)<>'object' OR(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(rule) k) IS DISTINCT FROM ARRAY['action','basis_reference','deadline']::text[]
   OR EXISTS(SELECT 1 FROM jsonb_each(rule) e WHERE jsonb_typeof(e.value)<>'string')
   OR rule->>'action' NOT IN('retain','erase','quarantine','blocked') OR length(btrim(rule->>'basis_reference')) NOT BETWEEN 1 AND 256
   OR rule->>'deadline' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$' THEN RAISE EXCEPTION 'retention_row_policy_rule_invalid' USING ERRCODE='42501';END IF;
  deadline:=(rule->>'deadline')::timestamptz;
  IF(r.key='access' AND rule->>'action'<>'quarantine') OR(r.key<>'access' AND rule->>'action'='quarantine')
   OR(rule->>'action'='erase' AND r.key NOT IN('notification_devices','notification_preferences','notification_events','support_requests'))
   OR(r.key LIKE 'private:%' OR r.key LIKE 'managed:%' OR r.key LIKE 'r2:%' OR r.key LIKE 'external:%'
      OR r.key IN('privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers','notification_email_job_dispatches')
      OR r.key<>'access' AND m.class_counts->r.key->>'status'<>'observed') AND rule->>'action'<>'blocked' THEN
   RAISE EXCEPTION 'retention_row_unsupported_disposition' USING ERRCODE='42501';END IF;
 END LOOP;
 IF jsonb_typeof(p->'writer_fence')<>'object' OR(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p->'writer_fence') k) IS DISTINCT FROM ARRAY['evidence_sha256','source_id','unknown_in_flight']::text[]
  OR p->'writer_fence'->>'source_id' IS DISTINCT FROM p_source OR NOT coalesce(p->'writer_fence'->>'evidence_sha256'~'^[a-f0-9]{64}$',false) OR p->'writer_fence'->'unknown_in_flight' IS DISTINCT FROM 'false'::jsonb
  OR jsonb_typeof(p->'copy_inventory')<>'object' OR(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p->'copy_inventory') k) IS DISTINCT FROM ARRAY['bff_access_revocation','physical_objects','providers','unmapped_copies']::text[]
  OR EXISTS(SELECT 1 FROM jsonb_each(p->'copy_inventory') e WHERE jsonb_typeof(e.value)<>'string')
  OR p->'copy_inventory'->>'physical_objects'<>'blocked' OR p->'copy_inventory'->>'providers'<>'blocked' OR p->'copy_inventory'->>'unmapped_copies'<>'blocked'
  OR p->'copy_inventory'->>'bff_access_revocation' NOT IN('allow','block') THEN RAISE EXCEPTION 'retention_row_copy_coverage_unapproved' USING ERRCODE='42501';END IF;
 IF p->'quarantine_continuation'<>'null'::jsonb AND(jsonb_typeof(p->'quarantine_continuation')<>'object'
  OR(SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p->'quarantine_continuation') k) IS DISTINCT FROM ARRAY['approval_evidence_sha256','previous_barrier_sha256','previous_plan_id','superseded_plan_id']::text[]
  OR EXISTS(SELECT 1 FROM jsonb_each(p->'quarantine_continuation') e WHERE jsonb_typeof(e.value)<>'string' AND NOT(e.key='superseded_plan_id' AND e.value='null'::jsonb))
  OR(p->'quarantine_continuation'->'superseded_plan_id'<>'null'::jsonb AND p->'quarantine_continuation'->>'superseded_plan_id'!~'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$')
  OR p->'quarantine_continuation'->>'previous_plan_id'!~'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p->'quarantine_continuation'->>'previous_barrier_sha256'!~'^[a-f0-9]{64}$' OR p->'quarantine_continuation'->>'approval_evidence_sha256'!~'^[a-f0-9]{64}$') THEN
  RAISE EXCEPTION 'retention_row_continuation_unapproved' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('policy',p,'raw',c.value_json,'sha256',p_sha,'revision',c.revision);
END$$;

CREATE FUNCTION private._retention_row_current_v2(p_plan uuid)
RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
 SELECT r.class_name,r.descriptor FROM private.retention_row_plans p
 CROSS JOIN LATERAL private._retention_manifest_rows_v2(p.subject_id) r WHERE p.id=p_plan
 AND NOT(r.class_name='privacy_retention_plans' AND r.descriptor->>'kind'='row' AND r.descriptor->>'key_sha256'=encode(sha256(convert_to(p.app_plan_id,'UTF8')),'hex'))
 AND NOT(r.class_name='privacy_retention_guards' AND r.descriptor->>'kind'='row' AND EXISTS(SELECT 1 FROM app.privacy_retention_guards g WHERE g.plan_id=p.app_plan_id AND r.descriptor->>'key_sha256'=encode(sha256(convert_to(g.id,'UTF8')),'hex')))
 AND NOT(r.class_name='privacy_retention_barriers' AND r.descriptor->>'kind'='row' AND EXISTS(SELECT 1 FROM app.privacy_retention_barriers b WHERE b.plan_id=p.app_plan_id AND b.subject_id=p.subject_id) AND r.descriptor->>'key_sha256'=encode(sha256(convert_to(p.subject_id,'UTF8')),'hex'))
$$;

CREATE FUNCTION private._retention_row_normalized_v2(p_plan uuid)
RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE changed boolean;
BEGIN
 -- Every changed live row must match its exact committed postimage. Deleted
 -- preimages are restored only in the comparison stream, never in source data.
 WITH current AS MATERIALIZED(SELECT * FROM private._retention_row_current_v2(p_plan))
 SELECT EXISTS(SELECT 1 FROM private.retention_row_effects e LEFT JOIN current c ON c.class_name=e.class_name
  AND c.descriptor->>'key_sha256'=e.key_sha256 AND c.descriptor->>'row_sha256'=e.after_row_sha256 AND c.descriptor=e.after_descriptor
  WHERE e.plan_id=p_plan AND e.after_descriptor IS NOT NULL AND c.class_name IS NULL) INTO changed;
 IF changed THEN
  RAISE EXCEPTION 'retention_row_postimage_changed' USING ERRCODE='42501';END IF;
 RETURN QUERY WITH current AS MATERIALIZED(SELECT * FROM private._retention_row_current_v2(p_plan))
  SELECT c.class_name,coalesce(e.before_descriptor,c.descriptor) FROM current c LEFT JOIN private.retention_row_effects e
   ON e.plan_id=p_plan AND e.class_name=c.class_name AND e.key_sha256=c.descriptor->>'key_sha256' AND e.after_descriptor=c.descriptor
  UNION ALL SELECT e.class_name,e.before_descriptor FROM private.retention_row_effects e WHERE e.plan_id=p_plan AND e.after_descriptor IS NULL;
END$$;

CREATE FUNCTION private._retention_row_source_guard_v2(p_plan uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE p private.retention_row_plans%ROWTYPE;m private.retention_inventory_manifests%ROWTYPE;observed text;
BEGIN
 SELECT * INTO STRICT p FROM private.retention_row_plans WHERE id=p_plan;
 SELECT * INTO STRICT m FROM private.retention_inventory_manifests WHERE id=p.manifest_id;
 IF private._retention_manifest_schema_v2()<>m.schema_identity OR private._retention_manifest_control_v2(m.request_id,(m.control_identity->>'review_revision')::bigint,m.source_sha256)<>m.control_identity THEN
  RAISE EXCEPTION 'retention_row_controls_changed' USING ERRCODE='42501';END IF;
 WITH source AS MATERIALIZED(SELECT * FROM private._retention_row_normalized_v2(p_plan)),
 ordered AS(SELECT class_name,descriptor,(row_number() OVER(ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text)-1)/100 AS page FROM source),
 pages AS(SELECT page,jsonb_agg(jsonb_build_object('class_name',class_name)||descriptor ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text) AS items FROM ordered GROUP BY page)
 SELECT encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page,'sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex')) ORDER BY page)::text,'UTF8')),'hex') INTO observed FROM pages;
 IF observed IS DISTINCT FROM m.pages_sha256 THEN RAISE EXCEPTION 'retention_row_source_changed' USING ERRCODE='42501';END IF;
 RETURN true;
END$$;

CREATE FUNCTION private._retention_row_gate_v2(p_plan uuid,p_effect boolean DEFAULT true) RETURNS private.retention_row_plans
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE p private.retention_row_plans%ROWTYPE;m private.retention_inventory_manifests%ROWTYPE;approved jsonb;b app.privacy_retention_barriers%ROWTYPE;decision jsonb;
BEGIN
 SELECT * INTO p FROM private.retention_row_plans WHERE id=p_plan FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'retention_row_plan_unavailable' USING ERRCODE='42501';END IF;
 IF p.state='superseded' THEN RAISE EXCEPTION 'retention_row_plan_superseded' USING ERRCODE='42501';END IF;
 SELECT * INTO m FROM private.retention_inventory_manifests WHERE id=p.manifest_id;
 approved:=private._retention_row_policy_v2(m.id,p.policy_sha256,p.environment,m.source_sha256);
 IF approved->>'raw'<>p.policy_raw OR(approved->>'revision')::bigint<>p.policy_revision THEN RAISE EXCEPTION 'retention_row_policy_changed' USING ERRCODE='42501';END IF;
 PERFORM private._retention_row_source_guard_v2(p.id);
 IF p_effect AND((m.control_identity->>'active_hold_count')::bigint>0 OR EXISTS(SELECT 1 FROM jsonb_each(m.class_counts) c WHERE coalesce((c.value->>'unresolved_count')::bigint,0)>0 OR coalesce((c.value->>'hold_count')::bigint,0)>0)
  OR m.control_identity->>'principal_mapping_sha256' IS NULL
  OR EXISTS(SELECT 1 FROM app.privacy_retention_guards g JOIN app.privacy_retention_plans r ON r.id=g.plan_id WHERE r.subject_id=p.subject_id AND r.id<>p.app_plan_id)
  OR EXISTS(SELECT 1 FROM app.privacy_retention_tasks t JOIN app.privacy_retention_plans r ON r.id=t.plan_id JOIN app.privacy_retention_claims c ON c.id=t.claim_id WHERE r.subject_id=p.subject_id AND r.id<>p.app_plan_id AND t.state='claimed' AND c.expires_seconds>extract(epoch FROM clock_timestamp())::bigint)
  OR EXISTS(SELECT 1 FROM app.privacy_retention_effects e JOIN app.privacy_retention_tasks t ON t.id=e.task_id JOIN app.privacy_retention_plans r ON r.id=t.plan_id WHERE r.subject_id=p.subject_id AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_outcomes o WHERE o.task_id=t.id AND o.outcome_json::jsonb->'verified'='true'::jsonb AND o.outcome_json::jsonb->>'disposition'='catalog_object_absence_verified')))
 THEN RAISE EXCEPTION 'retention_row_hold_or_unknown_work' USING ERRCODE='42501';END IF;
 SELECT * INTO b FROM app.privacy_retention_barriers WHERE subject_id=p.subject_id;
 decision:=p.policy_raw::jsonb->'quarantine_continuation';
 IF b.subject_id IS NOT NULL AND b.plan_id<>p.app_plan_id THEN
  IF decision='null'::jsonb OR decision->>'previous_plan_id'<>b.plan_id OR decision->>'previous_barrier_sha256'<>encode(sha256(convert_to(to_jsonb(b)::text,'UTF8')),'hex') THEN
   RAISE EXCEPTION 'retention_row_continuation_unapproved' USING ERRCODE='42501';END IF;
 ELSIF b.subject_id IS NULL AND decision<>'null'::jsonb THEN RAISE EXCEPTION 'retention_row_continuation_unavailable' USING ERRCODE='42501';END IF;
 RETURN p;
END$$;

CREATE FUNCTION private._retention_row_status_v2(p_plan uuid,p_current boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE p private.retention_row_plans%ROWTYPE;m private.retention_inventory_manifests%ROWTYPE;tasks jsonb;barrier jsonb;
BEGIN
 SELECT * INTO STRICT p FROM private.retention_row_plans WHERE id=p_plan;
 SELECT * INTO STRICT m FROM private.retention_inventory_manifests WHERE id=p.manifest_id;
 SELECT jsonb_build_object('previous_plan_id',b.plan_id,'previous_barrier_sha256',encode(sha256(convert_to(to_jsonb(b)::text,'UTF8')),'hex')) INTO barrier FROM app.privacy_retention_barriers b WHERE b.subject_id=p.subject_id;
 SELECT jsonb_agg(jsonb_build_object('class_name',k,'action',p.policy_raw::jsonb->'rules'->k->>'action','target_count',(p.targets->>k)::bigint,
  'recorded_absent_count',(SELECT count(*) FROM private.retention_row_effects e WHERE e.plan_id=p.id AND e.class_name=k AND e.after_descriptor IS NULL)) ORDER BY k) INTO tasks
 FROM jsonb_object_keys(p.targets) k;
 RETURN jsonb_build_object('contract_version',2,'scope','approved_sql_row_disposition','plan_id',p.id,'manifest_id',m.id,'manifest_sha256',m.manifest_sha256,
  'request_id',m.request_id,'subject_id',m.subject_id,'source_id',m.source_sha256,'schema_sha256',m.schema_sha256,'policy_sha256',p.policy_sha256,
  'state',p.state,'revision',p.revision,'fence',p.fence,'active_claim',p.active_claim,'superseded_by',p.superseded_by,'quarantine_barrier',barrier,'tasks',tasks,
  'eligible_sql_dispositions_verified',p.state='completed','financial_journal_preserved',p_current,'source_current',p_current,
  'erasure_completed',false,'all_data_erased',false,'all_actual_copy_outcomes_verified',false,'physical_objects_verified',false,'operational_acceptance_granted',false);
END$$;

CREATE FUNCTION private.retention_plan_rows_v2(p_operation uuid,p_manifest uuid,p_manifest_sha text,p_policy_sha text,p_environment text,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;sid text;m private.retention_inventory_manifests%ROWTYPE;approved jsonb;fingerprint text;p private.retention_row_plans%ROWTYPE;targets jsonb;status jsonb;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);sid:=api.current_session_id();
 IF p_operation IS NULL OR p_manifest IS NULL THEN RAISE EXCEPTION 'retention_row_input_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO m FROM private.retention_inventory_manifests WHERE id=p_manifest;
 IF m.id IS NULL OR m.manifest_sha256 IS DISTINCT FROM p_manifest_sha OR m.subject_id=actor THEN RAISE EXCEPTION 'retention_row_scope_unavailable' USING ERRCODE='42501';END IF;
 approved:=private._retention_row_policy_v2(p_manifest,p_policy_sha,p_environment,p_source);
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('operation',p_operation,'manifest',p_manifest,'manifest_sha',p_manifest_sha,'policy_sha',p_policy_sha,'environment',p_environment,'source',p_source,'actor',actor,'session',sid)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('retention-row-subject:'||m.subject_id,0));
 SELECT * INTO p FROM private.retention_row_plans WHERE id=p_operation;
 IF FOUND THEN
  IF p.input_sha256<>fingerprint THEN RAISE EXCEPTION 'retention_row_operation_conflict' USING ERRCODE='42501';END IF;
  PERFORM private._retention_row_gate_v2(p.id,false);RETURN private._retention_row_status_v2(p.id,true);
 END IF;
 -- An expired/blocked SQL-only plan can be replaced only by a newly reviewed
 -- exact snapshot and explicit continuation of its original immutable barrier.
 FOR p IN SELECT * FROM private.retention_row_plans WHERE subject_id=m.subject_id AND state NOT IN('completed','superseded') FOR UPDATE LOOP
  IF approved->'policy'->'quarantine_continuation'->>'superseded_plan_id' IS DISTINCT FROM p.id::text
   OR EXISTS(SELECT 1 FROM private.retention_row_claims WHERE id=p.active_claim AND expires_seconds>extract(epoch FROM clock_timestamp())::bigint)
   OR NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers WHERE subject_id=p.subject_id AND plan_id=approved->'policy'->'quarantine_continuation'->>'previous_plan_id') THEN
   RAISE EXCEPTION 'retention_row_prior_plan_unresolved' USING ERRCODE='42501';END IF;
 END LOOP;
 status:=private.retention_inventory_page_v2(p_manifest,p_manifest_sha,0,true);
 IF status->'data_current' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'retention_row_source_changed' USING ERRCODE='42501';END IF;
 targets:=jsonb_build_object('notification_devices',(SELECT count(*) FROM app.notification_devices WHERE user_id=m.subject_id),
  'notification_preferences',(SELECT count(*) FROM app.notification_preferences WHERE user_id=m.subject_id),
  'notification_events',(SELECT count(*) FROM app.notification_events WHERE user_id=m.subject_id),'support_requests',(SELECT count(*) FROM app.support_requests WHERE user_id=m.subject_id));
 INSERT INTO app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)
 VALUES(p_operation::text,p_operation::text,m.request_id,m.subject_id,actor,sid,fingerprint,p_policy_sha,approved->>'raw',(approved->>'revision')::bigint,m.source_sha256,m.schema_sha256,
  jsonb_build_object('contract_version',2,'scope','sql_rows_only','manifest_id',m.id,'manifest_sha256',m.manifest_sha256)::text,m.manifest_sha256,m.manifest_sha256,(m.control_identity->>'review_revision')::bigint,extract(epoch FROM clock_timestamp())::bigint);
 INSERT INTO private.retention_row_plans(id,manifest_id,app_plan_id,subject_id,actor_id,session_id,input_sha256,policy_raw,policy_sha256,policy_revision,environment,targets)
 VALUES(p_operation,m.id,p_operation::text,m.subject_id,actor,sid,fingerprint,approved->>'raw',p_policy_sha,(approved->>'revision')::bigint,p_environment,targets);
 UPDATE private.retention_row_plans SET state='superseded',superseded_by=p_operation,active_claim=NULL,revision=revision+1
 WHERE subject_id=m.subject_id AND id<>p_operation AND state NOT IN('completed','superseded');
 PERFORM private._retention_row_gate_v2(p_operation,true);
 RETURN private._retention_row_status_v2(p_operation,true);
END$$;

CREATE FUNCTION private.retention_claim_rows_v2(p_operation uuid,p_plan uuid,p_class text,p_revision bigint,p_lease integer,p_policy_sha text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;sid text;p private.retention_row_plans%ROWTYPE;c private.retention_row_claims%ROWTYPE;fingerprint text;at bigint:=extract(epoch FROM clock_timestamp())::bigint;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);sid:=api.current_session_id();
 IF p_operation IS NULL OR p_plan IS NULL OR p_class NOT IN('access','notification_devices','notification_preferences','notification_events','support_requests') OR p_class IS NULL
  OR p_revision IS NULL OR p_revision NOT BETWEEN 0 AND 1000000000 OR p_lease IS NULL OR p_lease NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'retention_row_input_invalid' USING ERRCODE='22023';END IF;
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('operation',p_operation,'plan',p_plan,'class',p_class,'revision',p_revision,'lease',p_lease,'actor',actor,'session',sid)::text,'UTF8')),'hex');
 p:=private._retention_row_gate_v2(p_plan,true);
 IF p.policy_sha256 IS DISTINCT FROM p_policy_sha THEN RAISE EXCEPTION 'retention_row_policy_pin_changed' USING ERRCODE='42501';END IF;
 IF actor=p.subject_id THEN RAISE EXCEPTION 'retention_row_independent_review_required' USING ERRCODE='42501';END IF;
 SELECT * INTO c FROM private.retention_row_claims WHERE operation_id=p_operation;
 IF FOUND THEN
  IF c.input_sha256<>fingerprint THEN RAISE EXCEPTION 'retention_row_operation_conflict' USING ERRCODE='42501';END IF;
 ELSE
  IF p.revision<>p_revision OR p.fence>=1000000000 OR EXISTS(SELECT 1 FROM private.retention_row_claims WHERE id=p.active_claim AND expires_seconds>at)
   OR p_class<>'access' AND p.state NOT IN('quarantined','processing','completed') THEN RAISE EXCEPTION 'retention_row_claim_changed' USING ERRCODE='42501';END IF;
  INSERT INTO private.retention_row_claims(id,operation_id,plan_id,class_name,actor_id,session_id,input_sha256,expected_revision,fence,claimed_seconds,expires_seconds)
  VALUES(gen_random_uuid(),p_operation,p.id,p_class,actor,sid,fingerprint,p_revision,p.fence+1,at,at+p_lease) RETURNING * INTO c;
  UPDATE private.retention_row_plans SET revision=revision+1,fence=c.fence,active_claim=c.id WHERE id=p.id;
 END IF;
 RETURN jsonb_build_object('contract_version',2,'scope','sql_row_claim','claim_id',c.id,'operation_id',c.operation_id,'plan_id',c.plan_id,'class_name',c.class_name,'fence',c.fence,'claimed_seconds',c.claimed_seconds,'expires_seconds',c.expires_seconds,'erasure_completed',false);
END$$;

-- EXECUTION_FUNCTIONS

DO $$DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND(p.proname LIKE '\_retention\_row\_%' ESCAPE '\' OR p.proname IN('retention_plan_rows_v2','retention_claim_rows_v2','retention_execute_rows_v2','retention_rows_status_v2','retention_rows_operation_v2')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',f.signature);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.retention_plan_rows_v2(uuid,uuid,text,text,text,text),private.retention_claim_rows_v2(uuid,uuid,text,bigint,integer,text),
 private.retention_execute_rows_v2(uuid,uuid,bigint,text),private.retention_rows_status_v2(uuid,boolean,text),private.retention_rows_operation_v2(text,uuid) TO collect_runtime;
COMMIT;
