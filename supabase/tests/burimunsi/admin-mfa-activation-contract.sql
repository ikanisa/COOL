-- Disposable synthetic PostgreSQL fixture ONLY, exact59 + both new migrations.
-- Run as postgres in fenced mode with one active, fully enrolled synthetic
-- Owner, fresh matching provider/BFF AAL2 proofs and no pending transitions.
-- Substitute SOURCE, OWNER_ADMIN and OWNER_FACTOR. Never use real accounts.
BEGIN;
CREATE FUNCTION pg_temp.activation_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'MFA activation contract: %',label;END IF;END;$fn$;
DO $acl$
DECLARE role_name text;signature text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
  FOREACH signature IN ARRAY ARRAY[
   'private.collect_admin_mfa_activation_readiness_v1(text,text,uuid)',
   'private.collect_admin_mfa_policy_transition_v1(uuid,text,bigint,text,uuid,jsonb)'] LOOP
   PERFORM pg_temp.activation_assert(NOT has_function_privilege(role_name,signature,'EXECUTE'),'operator-only routine');
  END LOOP;
 END LOOP;
END;$acl$;
DO $contract$
DECLARE ready jsonb;answer jsonb;approval jsonb:=jsonb_build_object('version',1,'action','activate',
 'browser_qualification_sha256',repeat('b',64),'configuration_sha256',repeat('c',64),
 'owner_recovery_sha256',repeat('d',64),'owner_setup_sha256',repeat('e',64),'previous_operation',NULL);
 operation uuid:='fb151000-0000-4000-8000-000000000001';rollback_operation uuid:='fb151000-0000-4000-8000-000000000002';
BEGIN
 PERFORM pg_temp.activation_assert(NOT private.collect_admin_mfa_policy_enabled_v1(),'migration leaves policy absent/OFF');
 ready:=private.collect_admin_mfa_activation_readiness_v1('__SOURCE__','__OWNER_ADMIN__','__OWNER_FACTOR__');
 PERFORM pg_temp.activation_assert(ready->'ready'='true'::jsonb AND ready->'activation_performed'='false'::jsonb,'fresh current owner ready');
 PERFORM pg_temp.activation_assert((private.collect_admin_mfa_activation_readiness_v1(repeat('f',64),'__OWNER_ADMIN__','__OWNER_FACTOR__')->'ready')='false'::jsonb,'wrong source not ready');
 PERFORM pg_temp.activation_assert((private.collect_admin_mfa_activation_readiness_v1('__SOURCE__','foreign-owner','__OWNER_FACTOR__')->'ready')='false'::jsonb,'foreign owner not ready');
 PERFORM pg_temp.activation_assert((private.collect_admin_mfa_activation_readiness_v1('__SOURCE__','__OWNER_ADMIN__','fb151000-0000-4000-8000-000000000099')->'ready')='false'::jsonb,'foreign factor not ready');
 BEGIN
  PERFORM private.collect_admin_mfa_policy_transition_v1(operation,'__SOURCE__',0,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval-'owner_recovery_sha256');
  RAISE EXCEPTION 'missing qualification accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN
  PERFORM private.collect_admin_mfa_policy_transition_v1(operation,repeat('f',64),0,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
  RAISE EXCEPTION 'wrong source accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM private.collect_admin_mfa_policy_transition_v1(operation,'__SOURCE__',1,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
  RAISE EXCEPTION 'stale revision accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE auth.mfa_factors SET status='unverified' WHERE id='__OWNER_FACTOR__';
 PERFORM pg_temp.activation_assert((private.collect_admin_mfa_activation_readiness_v1('__SOURCE__','__OWNER_ADMIN__','__OWNER_FACTOR__')->'ready')='false'::jsonb,'revoked/unverified factor not ready');
 BEGIN
  PERFORM private.collect_admin_mfa_policy_transition_v1(operation,'__SOURCE__',0,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
  RAISE EXCEPTION 'unenrolled owner activated';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE auth.mfa_factors SET status='verified' WHERE id='__OWNER_FACTOR__';
 answer:=private.collect_admin_mfa_policy_transition_v1(operation,'__SOURCE__',0,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
 PERFORM pg_temp.activation_assert(answer->>'state'='applied' AND answer->'required'='true'::jsonb AND answer->'policy_revision'='1'::jsonb,'qualified activation');
 PERFORM pg_temp.activation_assert(private.collect_admin_mfa_policy_enabled_v1(),'mandatory policy enabled only by transition');
 answer:=private.collect_admin_mfa_policy_transition_v1(operation,'__SOURCE__',0,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
 PERFORM pg_temp.activation_assert(answer->>'state'='recorded' AND answer->'current_policy_matches'='true'::jsonb,'lost-reply exact reconciliation');
 PERFORM pg_temp.activation_assert((SELECT count(*)=1 FROM app.audit_log WHERE request_id=operation::text AND action='admin.mfa.policy.transition'),'exactly one activation receipt');
 BEGIN
  PERFORM private.collect_admin_mfa_policy_transition_v1(operation,'__SOURCE__',0,'__OWNER_ADMIN__','__OWNER_FACTOR__',jsonb_set(approval,'{configuration_sha256}',to_jsonb(repeat('a',64))));
  RAISE EXCEPTION 'operation reuse accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1"}',true);
 BEGIN
  PERFORM private.collect_admin_mfa_assert_v1('{}',300);
  RAISE EXCEPTION 'AAL1 passed mandatory guard';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  UPDATE app.audit_log SET details_json='{}' WHERE request_id=operation::text AND action='admin.mfa.policy.transition';
  RAISE EXCEPTION 'receipt changed';
 EXCEPTION WHEN SQLSTATE '55000' THEN
  IF SQLERRM<>'collect_fence_closed' THEN RAISE;END IF;
 WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'immutable_audit' THEN RAISE;END IF;
 WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  DELETE FROM app.runtime_config WHERE key='security:admin_mfa_required:v1';
  RAISE EXCEPTION 'policy deletion allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;
 WHEN SQLSTATE '55000' THEN IF SQLERRM<>'collect_fence_closed' THEN RAISE;END IF;END;
 BEGIN
  UPDATE app.runtime_config SET value_json='{"version":1,"required":false}',revision=revision+1 WHERE key='security:admin_mfa_required:v1';
  RAISE EXCEPTION 'direct policy change allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;
 WHEN SQLSTATE '55000' THEN IF SQLERRM<>'collect_fence_closed' THEN RAISE;END IF;END;
 approval:=jsonb_set(jsonb_set(approval,'{action}','"rollback"'),'{previous_operation}',to_jsonb('fb151000-0000-4000-8000-000000000099'::text));
 BEGIN
  PERFORM private.collect_admin_mfa_policy_transition_v1(rollback_operation,'__SOURCE__',1,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
  RAISE EXCEPTION 'unbound rollback accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 approval:=jsonb_set(approval,'{previous_operation}',to_jsonb(operation::text));
 UPDATE auth.mfa_factors SET status='unverified' WHERE id='__OWNER_FACTOR__';
 answer:=private.collect_admin_mfa_policy_transition_v1(rollback_operation,'__SOURCE__',1,'__OWNER_ADMIN__','__OWNER_FACTOR__',approval);
 PERFORM pg_temp.activation_assert(answer->'required'='false'::jsonb AND answer->'policy_revision'='2'::jsonb,'fenced emergency recovery can disable after factor loss');
 PERFORM pg_temp.activation_assert(NOT private.collect_admin_mfa_policy_enabled_v1(),'rollback observed OFF');
 PERFORM pg_temp.activation_assert(current_setting('collect.admin_mfa_policy_commitment',true)=''
  AND current_setting('collect.admin_mfa_policy_write_frame',true)=''
  AND current_setting('collect.admin_mfa_policy_source',true)=''
  AND current_setting('collect.admin_mfa_policy_epoch',true)='','all policy contexts restored');
END;$contract$;
SET LOCAL ROLE collect_runtime;
DO $runtime_denial$
BEGIN
 BEGIN
  PERFORM private.collect_admin_mfa_activation_readiness_v1('__SOURCE__','__OWNER_ADMIN__','__OWNER_FACTOR__');
  RAISE EXCEPTION 'runtime routine exposed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('collect.admin_mfa_policy_commitment',repeat('a',64),true);
 BEGIN
  UPDATE app.runtime_config SET value_json='{"version":1,"required":true}',revision=revision+1 WHERE key='security:admin_mfa_required:v1';
  RAISE EXCEPTION 'forged runtime commitment accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;
 WHEN SQLSTATE '55000' THEN IF SQLERRM NOT IN('collect_fence_closed','collect_fence_unavailable') THEN RAISE;END IF;END;
END;$runtime_denial$;
ROLLBACK;
SELECT 'synthetic_admin_mfa_activation_rollback_contract_pass';
