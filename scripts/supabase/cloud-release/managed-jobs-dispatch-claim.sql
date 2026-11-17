-- Isolated candidate: install inside the same transaction as the reviewed,
-- initially disabled scheduler. Must be owned by the non-superuser postgres
-- operator; never grant ticket mutation to the Edge runtime. Values in the
-- pg_net queue are short-lived per-dispatch MACs, not reusable credentials.
CREATE TABLE private.collect_managed_job_tickets(
 dispatch_id uuid PRIMARY KEY REFERENCES collect_ops.jobs_dispatches(id) ON DELETE CASCADE,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload) IS NOT DISTINCT FROM 'object' AND jsonb_typeof(payload->'dispatch_id') IS NOT DISTINCT FROM 'string'
  AND payload->>'dispatch_id' IS NOT DISTINCT FROM dispatch_id::text AND jsonb_typeof(payload->'dispatch_expires_at') IS NOT DISTINCT FROM 'number'),
 created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
 expires_at timestamptz NOT NULL,
 claimed_at timestamptz,
 admission_id uuid,
 completed_at timestamptz,
 response_sha256 text CHECK(response_sha256 IS NULL OR response_sha256 ~ '^[a-f0-9]{64}$'),
 CHECK(expires_at>created_at AND expires_at<=created_at+interval '3 minutes'),
 CHECK((claimed_at IS NULL)=(admission_id IS NULL)),
 CHECK((completed_at IS NULL)=(response_sha256 IS NULL)),
 CHECK(completed_at IS NULL OR (claimed_at IS NOT NULL AND completed_at>=claimed_at))
);
ALTER TABLE private.collect_managed_job_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_managed_job_tickets FORCE ROW LEVEL SECURITY;
CREATE POLICY collect_managed_job_tickets_owner ON private.collect_managed_job_tickets TO postgres USING(true) WITH CHECK(true);
REVOKE ALL ON private.collect_managed_job_tickets FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.collect_managed_job_tickets
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.collect_managed_job_tickets ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

CREATE FUNCTION private.collect_managed_job_claim(p_dispatch uuid,p_source text,p_payload jsonb,p_signature text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $claim$
DECLARE v_admission uuid;v_epoch bigint;v_source text;v_key text;v_expected text;v_claimed uuid;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 v_admission:=NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid;
 v_epoch:=NULLIF(current_setting('collect.fence_epoch',true),'')::bigint;
 v_source:=NULLIF(current_setting('collect.fence_source_sha256',true),'');
 IF v_admission IS NULL OR v_epoch IS NULL OR v_source IS NULL OR p_dispatch IS NULL
  OR p_source IS DISTINCT FROM v_source OR NOT coalesce(p_source ~ '^[a-f0-9]{64}$',false)
  OR NOT coalesce(p_signature ~ '^[a-f0-9]{64}$',false)
  OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR p_payload->>'dispatch_id' IS DISTINCT FROM p_dispatch::text
 THEN RETURN false;END IF;
 PERFORM private.collect_fence_assert_write(v_admission,v_epoch,v_source);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.admission_id=v_admission
  AND a.epoch=v_epoch AND a.source_sha256=v_source AND a.kind='jobs' AND a.state='active') THEN RETURN false;END IF;
 IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1')<>1 THEN RETURN false;END IF;
 SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1';
 IF NOT coalesce(v_key ~ '^[a-f0-9]{64}$',false) THEN RETURN false;END IF;
 IF jsonb_typeof(p_payload->'dispatch_expires_at') IS DISTINCT FROM 'number' OR NOT coalesce(p_payload->>'dispatch_expires_at' ~ '^[1-9][0-9]{0,10}$',false) THEN RETURN false;END IF;
 v_expected:=encode(extensions.hmac(convert_to('collect.jobs.dispatch.v1'||E'\n'||'rrlduytparvsjfmegalh'||E'\n'||v_source||E'\n'||p_dispatch::text||E'\n'||(p_payload->>'dispatch_expires_at'),'UTF8'),convert_to(v_key,'UTF8'),'sha256'),'hex');
 IF p_signature IS DISTINCT FROM v_expected THEN RETURN false;END IF;
 UPDATE private.collect_managed_job_tickets t SET claimed_at=clock_timestamp(),admission_id=v_admission
  WHERE t.dispatch_id=p_dispatch AND t.source_sha256=v_source AND t.payload=p_payload AND t.claimed_at IS NULL
   AND t.created_at<=clock_timestamp() AND t.expires_at>clock_timestamp() AND t.expires_at=to_timestamp((p_payload->>'dispatch_expires_at')::bigint)
   AND EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches d WHERE d.id=t.dispatch_id AND d.state='awaiting' AND d.net_request_id IS NOT NULL)
  RETURNING t.dispatch_id INTO v_claimed;
 RETURN v_claimed IS NOT NULL;
END
$claim$;
REVOKE ALL ON FUNCTION private.collect_managed_job_claim(uuid,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_managed_job_claim(uuid,text,jsonb,text) TO collect_runtime;

-- pg_net response rows are writable by database roles. The scheduler may
-- confirm only the exact response whose digest was committed by the same
-- active jobs admission after all work completed successfully.
CREATE FUNCTION private.collect_managed_job_complete(p_dispatch uuid,p_source text,p_response_sha256 text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $complete$
DECLARE v_admission uuid;v_epoch bigint;v_source text;v_completed uuid;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 v_admission:=NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid;
 v_epoch:=NULLIF(current_setting('collect.fence_epoch',true),'')::bigint;
 v_source:=NULLIF(current_setting('collect.fence_source_sha256',true),'');
 IF v_admission IS NULL OR v_epoch IS NULL OR v_source IS NULL OR p_dispatch IS NULL
  OR p_source IS DISTINCT FROM v_source OR NOT coalesce(p_source ~ '^[a-f0-9]{64}$',false)
  OR NOT coalesce(p_response_sha256 ~ '^[a-f0-9]{64}$',false) THEN RETURN false;END IF;
 PERFORM private.collect_fence_assert_write(v_admission,v_epoch,v_source);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.admission_id=v_admission
  AND a.epoch=v_epoch AND a.source_sha256=v_source AND a.kind='jobs' AND a.state='active') THEN RETURN false;END IF;
 UPDATE private.collect_managed_job_tickets SET completed_at=clock_timestamp(),response_sha256=p_response_sha256
  WHERE dispatch_id=p_dispatch AND source_sha256=v_source AND admission_id=v_admission AND claimed_at IS NOT NULL AND completed_at IS NULL
  RETURNING dispatch_id INTO v_completed;
 RETURN v_completed IS NOT NULL;
END
$complete$;
REVOKE ALL ON FUNCTION private.collect_managed_job_complete(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_managed_job_complete(uuid,text,text) TO collect_runtime;
