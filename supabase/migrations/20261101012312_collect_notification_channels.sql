-- Explicit, dormant notification channels. No provider call or activation.
BEGIN;
ALTER TABLE app.notification_preferences ADD COLUMN email_enabled bigint NOT NULL DEFAULT 0 CHECK(email_enabled IN(0,1));
ALTER TABLE app.notification_preferences ADD COLUMN payment_reminders bigint NOT NULL DEFAULT 1 CHECK(payment_reminders IN(0,1));
ALTER TABLE app.notification_preferences ADD COLUMN security_notices bigint NOT NULL DEFAULT 1 CHECK(security_notices IN(0,1));

CREATE TABLE app.assisted_sms_dispatches(
 attempt_id text PRIMARY KEY REFERENCES app.assisted_sms_send_starts(id),
 grant_sha256 text NOT NULL CHECK(grant_sha256 ~ '^[a-f0-9]{64}$'),
 expires_seconds bigint NOT NULL,
 application_id text NOT NULL CHECK(length(application_id) BETWEEN 1 AND 100),
 provider_message_id text NOT NULL UNIQUE CHECK(length(provider_message_id)<=200),
 not_after text NOT NULL,
 state text NOT NULL DEFAULT 'ready' CHECK(state IN('ready','sending','accepted','failed','unknown','suppressed')),
 provider_state text, evidence_sha256 text CHECK(evidence_sha256 IS NULL OR evidence_sha256 ~ '^[a-f0-9]{64}$'),
 started_seconds bigint, updated_seconds bigint NOT NULL DEFAULT app.unixepoch(),
 CHECK((state='ready' AND started_seconds IS NULL) OR state<>'ready')
);
CREATE FUNCTION private.assisted_sms_dispatch_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'sms_dispatch_retained' USING ERRCODE='42501'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.state<>'ready' OR NEW.started_seconds IS NOT NULL OR NEW.expires_seconds<=app.unixepoch()
   OR NOT EXISTS(SELECT 1 FROM app.assisted_sms_send_starts s JOIN app.assisted_sms_confirmations c ON c.id=s.confirmation_id
    WHERE s.id=NEW.attempt_id AND NEW.expires_seconds<=c.expires_seconds)
  THEN RAISE EXCEPTION 'sms_dispatch_invalid_grant' USING ERRCODE='42501'; END IF;
 ELSE
  IF ROW(NEW.attempt_id,NEW.grant_sha256,NEW.expires_seconds,NEW.application_id,NEW.provider_message_id,NEW.not_after)
   IS DISTINCT FROM ROW(OLD.attempt_id,OLD.grant_sha256,OLD.expires_seconds,OLD.application_id,OLD.provider_message_id,OLD.not_after)
   OR NOT ((OLD.state='ready' AND NEW.state IN('sending','suppressed'))
      OR (OLD.state='sending' AND NEW.state IN('accepted','failed','unknown'))
      OR (OLD.state IN('accepted','unknown') AND NEW.state IN('accepted','failed','unknown')))
   OR (OLD.started_seconds IS NOT NULL AND NEW.started_seconds IS DISTINCT FROM OLD.started_seconds)
  THEN RAISE EXCEPTION 'sms_dispatch_identity_or_transition_changed' USING ERRCODE='42501'; END IF;
  IF NEW.state='sending' AND (NEW.started_seconds<>app.unixepoch() OR NEW.expires_seconds<=app.unixepoch())
   THEN RAISE EXCEPTION 'sms_dispatch_grant_expired' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER assisted_sms_dispatch_identity BEFORE INSERT OR UPDATE OR DELETE ON app.assisted_sms_dispatches
 FOR EACH ROW EXECUTE FUNCTION private.assisted_sms_dispatch_guard();
ALTER TABLE app.assisted_sms_dispatches ENABLE ALWAYS TRIGGER assisted_sms_dispatch_identity;

-- Retain only hashes and outcome evidence. Event erasure cannot erase unknown
-- transport outcomes; absence of the source always suppresses a future send.
CREATE TABLE app.notification_email_deliveries(
 id text PRIMARY KEY, event_id text NOT NULL UNIQUE, user_id text NOT NULL REFERENCES app.users(id),
 recipient_sha256 text NOT NULL CHECK(recipient_sha256 ~ '^[a-f0-9]{64}$'),
 event_sha256 text NOT NULL CHECK(event_sha256 ~ '^[a-f0-9]{64}$'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','sending','accepted','suppressed','unknown')),
 attempt_id text, started_seconds bigint, provider_message_id text,
 created_seconds bigint NOT NULL DEFAULT app.unixepoch(), updated_seconds bigint NOT NULL DEFAULT app.unixepoch(),
 CHECK((state='pending' AND attempt_id IS NULL AND started_seconds IS NULL) OR state<>'pending'),
 CHECK((state='accepted' AND provider_message_id IS NOT NULL) OR(state<>'accepted' AND provider_message_id IS NULL))
);
CREATE INDEX notification_email_pending ON app.notification_email_deliveries(state,created_seconds,id);
CREATE INDEX notification_email_subject ON app.notification_email_deliveries(user_id,created_seconds,id);
CREATE FUNCTION private.notification_email_eligible(p_event text,p_user text,p_recipient_hash text,p_event_hash text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM app.notification_events e JOIN app.users u ON u.id=e.user_id
  JOIN private.auth_principal_links link ON link.user_id=u.id JOIN auth.users account ON account.id=link.auth_user_id
  JOIN app.notification_preferences preference ON preference.user_id=u.id
  JOIN app.memberships membership ON membership.user_id=u.id AND membership.collection_id=e.data_json::jsonb->>'collection_id'
  JOIN app.collections collection ON collection.id=membership.collection_id
  WHERE e.id=p_event AND e.user_id=p_user AND e.event_type='contribution' AND u.access_status='active' AND u.member_type='app'
   AND account.email_confirmed_at IS NOT NULL AND lower(account.email)=lower(u.email)
   AND encode(sha256(convert_to(lower(account.email),'UTF8')),'hex')=p_recipient_hash
   AND encode(sha256(convert_to(jsonb_build_array(e.id,e.user_id,e.event_type,e.created_at,e.data_json)::text,'UTF8')),'hex')=p_event_hash
   AND preference.email_enabled=1 AND preference.payment_updates=1
   AND membership.active=1 AND collection.status='active'
   AND (to_jsonb(account)->>'deleted_at') IS NULL
   AND ((to_jsonb(account)->>'banned_until') IS NULL OR(to_jsonb(account)->>'banned_until')::timestamptz<=now())
   AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers b WHERE b.subject_id=u.id))
$$;
CREATE FUNCTION private.notification_email_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'notification_email_retained' USING ERRCODE='42501'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.state<>'pending' OR NOT private.notification_email_eligible(NEW.event_id,NEW.user_id,NEW.recipient_sha256,NEW.event_sha256)
   THEN RAISE EXCEPTION 'notification_email_source_changed' USING ERRCODE='42501'; END IF;
 ELSE
  IF ROW(NEW.id,NEW.event_id,NEW.user_id,NEW.recipient_sha256,NEW.event_sha256,NEW.created_seconds)
   IS DISTINCT FROM ROW(OLD.id,OLD.event_id,OLD.user_id,OLD.recipient_sha256,OLD.event_sha256,OLD.created_seconds)
   OR NOT((OLD.state='pending' AND NEW.state IN('sending','suppressed')) OR(OLD.state='sending' AND NEW.state IN('accepted','unknown')))
   OR (OLD.attempt_id IS NOT NULL AND ROW(NEW.attempt_id,NEW.started_seconds) IS DISTINCT FROM ROW(OLD.attempt_id,OLD.started_seconds))
   THEN RAISE EXCEPTION 'notification_email_identity_or_transition_changed' USING ERRCODE='42501'; END IF;
  IF NEW.state='sending' AND (NEW.attempt_id IS NULL OR NEW.started_seconds<>app.unixepoch()
    OR NOT private.notification_email_eligible(NEW.event_id,NEW.user_id,NEW.recipient_sha256,NEW.event_sha256))
   THEN RAISE EXCEPTION 'notification_email_authority_changed' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER notification_email_identity BEFORE INSERT OR UPDATE OR DELETE ON app.notification_email_deliveries
 FOR EACH ROW EXECUTE FUNCTION private.notification_email_guard();
ALTER TABLE app.notification_email_deliveries ENABLE ALWAYS TRIGGER notification_email_identity;

DO $$DECLARE t text; r text; BEGIN
 FOREACH t IN ARRAY ARRAY['assisted_sms_dispatches','notification_email_deliveries'] LOOP
  EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE app.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY notification_channel_runtime ON app.%I TO collect_runtime USING(true) WITH CHECK(true)',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON app.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE app.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
  EXECUTE format('REVOKE ALL ON app.%I FROM PUBLIC',t);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON app.%I FROM %I',t,r); END IF;
  END LOOP;
  EXECUTE format('GRANT SELECT,INSERT,UPDATE ON app.%I TO collect_runtime',t);
 END LOOP;
END$$;
-- Durable scheduler envelope. This shared record contains no recipient or
-- message body; it retains one dispatch even when the original batch is empty.
CREATE TABLE app.notification_email_job_dispatches(
 id text PRIMARY KEY CHECK(id ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'),
 admission_sha256 text NOT NULL CHECK(admission_sha256 ~ '^[a-f0-9]{64}$'),
 admission_json text NOT NULL CHECK(octet_length(admission_json)<=2048 AND encode(sha256(convert_to(admission_json,'UTF8')),'hex')=admission_sha256),
 state text NOT NULL DEFAULT 'claimed' CHECK(state IN('claimed','completed','unknown')),
 result_json text CHECK(result_json IS NULL OR octet_length(result_json)<=1024),
 created_seconds bigint NOT NULL DEFAULT app.unixepoch(),updated_seconds bigint NOT NULL DEFAULT app.unixepoch(),
 CHECK((state='completed' AND result_json IS NOT NULL)OR(state<>'completed' AND result_json IS NULL))
);
CREATE INDEX notification_email_dispatch_pending ON app.notification_email_job_dispatches(state,created_seconds,id);
CREATE FUNCTION private.notification_email_job_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a jsonb;r jsonb;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'notification_email_dispatch_retained' USING ERRCODE='42501';END IF;
 IF TG_OP='INSERT' THEN
  a:=NEW.admission_json::jsonb;
  IF NEW.state<>'claimed' OR jsonb_typeof(a)IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'notification_email_dispatch_invalid';END IF;
  IF (SELECT array_agg(k ORDER BY k)FROM jsonb_object_keys(a)k)IS DISTINCT FROM ARRAY['admitted_from','approval_sha256','batch_limit','contract','source_sha256']::text[]
   OR a->>'contract' IS DISTINCT FROM 'collect.contribution-email.v1' OR a->'batch_limit' IS DISTINCT FROM '1'::jsonb
   OR jsonb_typeof(a->'source_sha256')IS DISTINCT FROM 'string' OR jsonb_typeof(a->'approval_sha256')IS DISTINCT FROM 'string'
   OR NOT coalesce(a->>'source_sha256'~'^[a-f0-9]{64}$',false) OR NOT coalesce(a->>'approval_sha256'~'^[a-f0-9]{64}$',false)
   OR jsonb_typeof(a->'admitted_from')IS DISTINCT FROM 'number' OR NOT coalesce(a->>'admitted_from'~'^[1-9][0-9]{0,9}$',false)
   OR(a->>'admitted_from')::bigint>=4102444800 THEN RAISE EXCEPTION 'notification_email_dispatch_invalid';END IF;
 ELSE
  IF ROW(NEW.id,NEW.admission_sha256,NEW.admission_json,NEW.created_seconds)IS DISTINCT FROM ROW(OLD.id,OLD.admission_sha256,OLD.admission_json,OLD.created_seconds)
   OR OLD.state<>'claimed' OR NEW.state NOT IN('completed','unknown') THEN RAISE EXCEPTION 'notification_email_dispatch_identity_changed' USING ERRCODE='42501';END IF;
 END IF;
 IF NEW.state='completed' THEN
  r:=NEW.result_json::jsonb;
  IF jsonb_typeof(r)IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'notification_email_dispatch_result_invalid';END IF;
  IF (SELECT array_agg(k ORDER BY k)FROM jsonb_object_keys(r)k)IS DISTINCT FROM ARRAY['processed','results','status']::text[]
   OR r->>'status' IS DISTINCT FROM 'complete' OR r->'processed' NOT IN('0'::jsonb,'1'::jsonb)
   OR jsonb_typeof(r->'results')IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'notification_email_dispatch_result_invalid';END IF;
  IF to_jsonb(jsonb_array_length(r->'results'))IS DISTINCT FROM r->'processed'
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'results')item WHERE item IS DISTINCT FROM jsonb_build_object('state',item->>'state','delivery_confirmed',false)
    OR item->>'state' IS NULL OR item->>'state' NOT IN('accepted','suppressed','unknown')) THEN RAISE EXCEPTION 'notification_email_dispatch_result_invalid';END IF;
 END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER notification_email_job_identity BEFORE INSERT OR UPDATE OR DELETE ON app.notification_email_job_dispatches
 FOR EACH ROW EXECUTE FUNCTION private.notification_email_job_guard();
ALTER TABLE app.notification_email_job_dispatches ENABLE ALWAYS TRIGGER notification_email_job_identity;
ALTER TABLE app.notification_email_job_dispatches ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notification_email_job_dispatches FORCE ROW LEVEL SECURITY;
CREATE POLICY notification_channel_runtime ON app.notification_email_job_dispatches TO collect_runtime USING(true) WITH CHECK(true);
-- The owner fence inventory may count shared journal obligations without
-- receiving a runtime role or bypassing FORCE RLS on recipient tables.
CREATE POLICY notification_email_dispatch_owner_read ON app.notification_email_job_dispatches FOR SELECT TO postgres USING(true);
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON app.notification_email_job_dispatches
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE app.notification_email_job_dispatches ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
REVOKE ALL ON app.notification_email_job_dispatches FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT SELECT,INSERT,UPDATE ON app.notification_email_job_dispatches TO collect_runtime;
REVOKE ALL ON FUNCTION private.notification_email_job_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.notification_email_job_guard() TO collect_runtime;
-- End durable scheduler envelope.
REVOKE ALL ON FUNCTION private.assisted_sms_dispatch_guard(),private.notification_email_guard(),private.notification_email_eligible(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.assisted_sms_dispatch_guard(),private.notification_email_guard(),private.notification_email_eligible(text,text,text,text) TO collect_runtime;
COMMIT;
