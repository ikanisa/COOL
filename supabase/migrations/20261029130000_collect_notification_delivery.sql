-- Additive Android FCM obligations. No activation, credential, event replay or
-- provider call occurs in this migration. Existing migration bytes are intact.
BEGIN;
CREATE TABLE app.notification_deliveries (
 id text PRIMARY KEY CHECK(id ~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'),
 event_id text NOT NULL,device_id text NOT NULL,
 user_id text NOT NULL REFERENCES app.users(id),owner_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 token_sha256 text NOT NULL CHECK(token_sha256 ~ '^[a-f0-9]{64}$'),
 event_sha256 text NOT NULL CHECK(event_sha256 ~ '^[a-f0-9]{64}$'),
 project_id text NOT NULL CHECK(project_id ~ '^[a-z][a-z0-9-]{4,28}[a-z0-9]$'),
 android_package text NOT NULL CHECK(android_package IN('app.cool.mobile','app.cool.mobile.dev')),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','claimed','sending','accepted','retry','rejected','suppressed','unknown')),
 attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 4),
 available_at bigint NOT NULL,lease_token text,lease_until bigint,
 attempt_log jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(attempt_log)='array' AND jsonb_array_length(attempt_log)=attempt_count AND octet_length(attempt_log::text)<=8192),
 provider_message_id text CHECK(provider_message_id IS NULL OR length(provider_message_id)<=320),
 last_error text CHECK(last_error IS NULL OR last_error IN('provider_auth_unavailable','invalid_registration','provider_throttled','provider_unavailable','provider_auth_rejected',
  'provider_request_rejected','retry_after_unreviewed','delivery_unconfirmed','authority_changed','invalid_push_payload','retry_budget_exhausted','claim_expired_before_send')),
 last_http_status integer CHECK(last_http_status IS NULL OR last_http_status BETWEEN 100 AND 599),
 created_at bigint NOT NULL,updated_at bigint NOT NULL,
 UNIQUE(event_id,device_id),
 CHECK((state IN('claimed','sending') AND lease_token IS NOT NULL AND lease_until IS NOT NULL) OR(state NOT IN('claimed','sending') AND lease_token IS NULL AND lease_until IS NULL)),
 CHECK((state='accepted' AND provider_message_id IS NOT NULL) OR(state<>'accepted' AND provider_message_id IS NULL))
);
-- Deliberately no foreign key to the existing erasable event/device records:
-- their approved erasure must not cascade-delete retained delivery uncertainty.
-- Missing source records suppress future dispatch through the predicate below.
CREATE INDEX notification_deliveries_ready ON app.notification_deliveries(state,available_at,id);
CREATE INDEX notification_deliveries_subject ON app.notification_deliveries(user_id,created_at,id);

CREATE FUNCTION private.notification_delivery_eligible(p_event_id text,p_device_id text,p_user_id text,p_session_id text,p_token_sha256 text,p_event_sha256 text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(
  SELECT 1 FROM app.notification_events e JOIN app.notification_devices d ON d.id=p_device_id AND d.user_id=e.user_id
  JOIN app.users u ON u.id=e.user_id JOIN app.auth_sessions s ON s.id=d.owner_session_id AND s.user_id=u.id
  JOIN private.auth_principal_links l ON l.user_id=u.id
  JOIN auth.sessions managed ON managed.id::text=s.id AND managed.user_id=l.auth_user_id
  JOIN auth.users managed_user ON managed_user.id=managed.user_id
  JOIN app.memberships membership ON membership.user_id=u.id AND membership.collection_id=e.data_json::jsonb->>'collection_id'
  JOIN app.collections collection ON collection.id=membership.collection_id
  LEFT JOIN app.notification_preferences preference ON preference.user_id=u.id
  WHERE e.id=p_event_id AND e.user_id=p_user_id AND e.event_type='contribution' AND e.status='pending'
   AND encode(sha256(convert_to(jsonb_build_array(e.id,e.user_id,e.event_type,e.created_at,e.data_json)::text,'UTF8')),'hex')=p_event_sha256
   AND d.active=1 AND d.platform='android' AND d.provider='fcm' AND d.owner_session_id=p_session_id AND d.token_hash=p_token_sha256
   AND u.access_status='active' AND u.member_type='app' AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>app.unixepoch()
   AND (to_jsonb(managed_user)->>'deleted_at') IS NULL
   AND ((to_jsonb(managed_user)->>'banned_until') IS NULL OR(to_jsonb(managed_user)->>'banned_until')::timestamptz<=now())
   AND ((to_jsonb(managed)->>'not_after') IS NULL OR(to_jsonb(managed)->>'not_after')::timestamptz>now())
   AND membership.active=1 AND collection.status='active'
   AND coalesce(preference.push_enabled,1)=1 AND coalesce(preference.payment_updates,1)=1
   AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers barrier WHERE barrier.subject_id=u.id)
 )
$$;

CREATE FUNCTION private.notification_delivery_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'notification_delivery_retained' USING ERRCODE='42501';END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.state<>'pending' OR NEW.attempt_count<>0 OR NEW.attempt_log<>'[]'::jsonb OR NEW.last_error IS NOT NULL OR NEW.last_http_status IS NOT NULL
   OR NOT private.notification_delivery_eligible(NEW.event_id,NEW.device_id,NEW.user_id,NEW.owner_session_id,NEW.token_sha256,NEW.event_sha256)
  THEN RAISE EXCEPTION 'notification_delivery_source_changed' USING ERRCODE='42501';END IF;
  RETURN NEW;
 END IF;
 IF ROW(NEW.id,NEW.event_id,NEW.device_id,NEW.user_id,NEW.owner_session_id,NEW.token_sha256,NEW.event_sha256,NEW.project_id,NEW.android_package,NEW.created_at)
  IS DISTINCT FROM ROW(OLD.id,OLD.event_id,OLD.device_id,OLD.user_id,OLD.owner_session_id,OLD.token_sha256,OLD.event_sha256,OLD.project_id,OLD.android_package,OLD.created_at)
  OR OLD.state IN('accepted','rejected','suppressed','unknown')
 THEN RAISE EXCEPTION 'notification_delivery_identity_or_terminal_state_changed' USING ERRCODE='42501';END IF;
 IF NEW.state IS DISTINCT FROM OLD.state AND NOT(
  (OLD.state IN('pending','retry') AND NEW.state='claimed' AND NEW.attempt_count=OLD.attempt_count+1)
  OR(OLD.state='claimed' AND NEW.state IN('sending','retry','rejected','suppressed') AND NEW.attempt_count=OLD.attempt_count)
  OR(OLD.state='sending' AND NEW.state IN('accepted','retry','rejected','unknown') AND NEW.attempt_count=OLD.attempt_count)
 ) THEN RAISE EXCEPTION 'notification_delivery_transition_invalid' USING ERRCODE='42501';END IF;
 IF NEW.attempt_count=OLD.attempt_count+1 THEN
  IF NEW.state<>'claimed' OR NEW.attempt_log-OLD.attempt_count IS DISTINCT FROM OLD.attempt_log THEN RAISE EXCEPTION 'notification_delivery_attempt_history_changed' USING ERRCODE='42501';END IF;
 ELSIF NEW.attempt_count<>OLD.attempt_count OR NEW.attempt_log-(NEW.attempt_count-1) IS DISTINCT FROM OLD.attempt_log-(OLD.attempt_count-1) THEN
  RAISE EXCEPTION 'notification_delivery_attempt_history_changed' USING ERRCODE='42501';
 END IF;
 IF NEW.state='sending' AND NOT private.notification_delivery_eligible(NEW.event_id,NEW.device_id,NEW.user_id,NEW.owner_session_id,NEW.token_sha256,NEW.event_sha256)
 THEN RAISE EXCEPTION 'notification_delivery_authority_changed' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER notification_delivery_identity BEFORE INSERT OR UPDATE OR DELETE ON app.notification_deliveries
 FOR EACH ROW EXECUTE FUNCTION private.notification_delivery_guard();
ALTER TABLE app.notification_deliveries ENABLE ALWAYS TRIGGER notification_delivery_identity;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON app.notification_deliveries
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE app.notification_deliveries ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
ALTER TABLE app.notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notification_deliveries FORCE ROW LEVEL SECURITY;
CREATE POLICY notification_delivery_runtime ON app.notification_deliveries TO collect_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON app.notification_deliveries FROM PUBLIC;
REVOKE ALL ON FUNCTION private.notification_delivery_eligible(text,text,text,text,text,text),private.notification_delivery_guard() FROM PUBLIC;
DO $$DECLARE r text;BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   EXECUTE format('REVOKE ALL ON app.notification_deliveries FROM %I',r);
   EXECUTE format('REVOKE ALL ON FUNCTION private.notification_delivery_eligible(text,text,text,text,text,text),private.notification_delivery_guard() FROM %I',r);
  END IF;
 END LOOP;
END$$;
GRANT SELECT,INSERT,UPDATE ON app.notification_deliveries TO collect_runtime;
GRANT EXECUTE ON FUNCTION private.notification_delivery_eligible(text,text,text,text,text,text),private.notification_delivery_guard() TO collect_runtime;
COMMIT;
