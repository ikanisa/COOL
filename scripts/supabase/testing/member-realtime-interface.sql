-- ROOT-ONLY synthetic interface for a NEW unique loopback collect_member_realtime_*_test DB.
-- NOT A MIGRATION. Never execute on hosted/project DB or an existing fixture DB.
-- Root must first guard URL/database identity and preserve the new DB. Creates
-- managed-shape doubles only inside that local synthetic DB, not managed DDL.
DO $$DECLARE r record;BEGIN IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN;END IF; SELECT rolcanlogin,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolbypassrls,rolreplication INTO STRICT r FROM pg_catalog.pg_roles WHERE rolname='service_role';IF r.rolcanlogin OR r.rolsuper OR NOT r.rolinherit OR r.rolcreaterole OR r.rolcreatedb OR r.rolbypassrls OR r.rolreplication THEN RAISE EXCEPTION 'EXACT_SERVICE_ROLE_FIXTURE_REQUIRED';END IF;END$$;
CREATE SCHEMA realtime;
CREATE TABLE realtime.messages(
 topic text NOT NULL,extension text NOT NULL,payload jsonb,event text,private boolean,
 updated_at timestamp NOT NULL DEFAULT now(),inserted_at timestamp NOT NULL DEFAULT now(),
 id uuid NOT NULL,binary_payload bytea,skip_broadcast boolean NOT NULL DEFAULT false,
 PRIMARY KEY(id,inserted_at)
) PARTITION BY RANGE(inserted_at);
-- Deliberately no partition: first publisher scenario must prove send's silent
-- failure is not ACK. Root creates a synthetic partition only in a later step.
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA realtime TO anon,authenticated,postgres;
GRANT SELECT,INSERT,UPDATE ON realtime.messages TO anon,authenticated,postgres;
CREATE FUNCTION realtime.topic() RETURNS text LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('realtime.topic',true),'')::text$$;
CREATE FUNCTION realtime.send(payload jsonb,event text,topic text,private boolean DEFAULT true) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF current_setting('collect.synthetic_send_mode',true)='silent' THEN RETURN;END IF;
 IF current_setting('collect.synthetic_send_mode',true)='raise' THEN RAISE EXCEPTION 'synthetic send failure';END IF;
 BEGIN
  PERFORM set_config('realtime.topic',topic,true);
  INSERT INTO realtime.messages(id,payload,event,topic,private,extension)VALUES(gen_random_uuid(),payload,event,topic,private,'broadcast');
 EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Synthetic send unconfirmed';
 END;
END$$;
-- This fixture owner is collect_test, whose definer bypass is NOT the restricted
-- postgres fixture role. Root records actual owner/rolsuper/rolbypassrls and
-- explicitly maps this publishing double to hosted postgres BYPASS=true. Never
-- ALTER the existing restricted postgres fixture or add production grants.
