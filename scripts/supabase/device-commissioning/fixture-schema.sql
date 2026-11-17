-- TEST FIXTURE ONLY. This is not a Supabase migration or a production API.
-- A production design must independently establish authentication, fencing,
-- custody, retention, receipt authenticity and recovery before integration.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
DO $guard$
BEGIN
 IF session_user<>'fixture_bootstrap' OR current_user<>'fixture_bootstrap'
  OR current_setting('cluster_name')<>'collect_commissioning_synthetic_only'
  OR current_setting('listen_addresses')<>'' OR inet_server_addr() IS NOT NULL
  OR current_database() !~ '^collect_commissioning_fixture_[a-z0-9]+$'
  OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_commissioning_fixture_runtime') THEN
  RAISE EXCEPTION 'fixture_install_refused' USING ERRCODE='55000';
 END IF;
END;$guard$;

CREATE SCHEMA commissioning_fixture;
REVOKE ALL ON SCHEMA commissioning_fixture FROM PUBLIC;
CREATE TABLE commissioning_fixture.receipts(
 transition_id uuid PRIMARY KEY,
 installation_sha256 text NOT NULL,
 queue_generation bigint NOT NULL,
 target_device_key_sha256 text NOT NULL,
 binding jsonb NOT NULL,
 receipt jsonb NOT NULL,
 expires_epoch bigint NOT NULL,
 UNIQUE(installation_sha256,queue_generation),
 UNIQUE(target_device_key_sha256)
);
CREATE TABLE commissioning_fixture.consumptions(
 transition_id uuid PRIMARY KEY REFERENCES commissioning_fixture.receipts(transition_id),
 consume_id uuid UNIQUE NOT NULL,
 request jsonb NOT NULL,
 acknowledgement jsonb NOT NULL
);
ALTER TABLE commissioning_fixture.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE commissioning_fixture.consumptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA commissioning_fixture FROM PUBLIC,collect_commissioning_fixture_runtime;

CREATE FUNCTION commissioning_fixture.fixture_only() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
BEGIN
 IF current_setting('cluster_name')<>'collect_commissioning_synthetic_only'
  OR current_setting('listen_addresses')<>'' OR inet_server_addr() IS NOT NULL
  OR current_setting('transaction_isolation')<>'read committed'
  OR current_database() !~ '^collect_commissioning_fixture_[a-z0-9]+$' THEN
  RAISE EXCEPTION 'fixture_runtime_refused' USING ERRCODE='55000';
 END IF;
END;$f$;

CREATE FUNCTION commissioning_fixture.validate_binding(p jsonb) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
DECLARE k text; supplied text[];
BEGIN
 PERFORM commissioning_fixture.fixture_only();
 IF p IS NULL OR jsonb_typeof(p)<>'object' OR octet_length(p::text)>8192 THEN
  RAISE EXCEPTION 'fixture_binding_invalid' USING ERRCODE='22023';END IF;
 SELECT array_agg(key ORDER BY key) INTO supplied FROM jsonb_object_keys(p) AS keys(key);
 IF supplied IS DISTINCT FROM ARRAY['account_group_mapping_sha256','application','approved_operator_sha256','expires_epoch','format',
  'installation_sha256','queue_generation','queue_revision','queue_watermark','reconciliation_sha256','role',
  'sealed_queue_sha256','source_account_sha256','source_api_sha256','source_auth_sha256','source_fence_sha256',
  'source_gateway_sha256','target_api_sha256','target_auth_sha256','target_device_key_sha256','target_fence_sha256','target_gateway_sha256',
  'target_primary_account_sha256','target_project','transition_id']::text[]
  OR EXISTS(SELECT 1 FROM jsonb_each(p) e WHERE jsonb_typeof(e.value)<>'string')
  OR p->>'format'<>'collect.fixture.commissioning-binding.v1'
  OR p->>'target_project'<>'synthetic-project-only'
  OR NOT ((p->>'application'='rw.ikanisa.burimunsi.gateway' AND p->>'role'='receiver')
   OR (p->>'application'='rw.ikanisa.burimunsi.staff' AND p->>'role'='staff'))
  OR p->>'transition_id' !~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
  OR p->>'queue_generation' !~ '^[1-9][0-9]{0,14}$'
  OR p->>'queue_revision' !~ '^(0|[1-9][0-9]{0,14})$'
  OR p->>'queue_watermark' !~ '^(0|[1-9][0-9]{0,14})$'
  OR p->>'expires_epoch' !~ '^[1-9][0-9]{0,11}$' THEN
  RAISE EXCEPTION 'fixture_binding_invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY ARRAY['account_group_mapping_sha256','approved_operator_sha256','installation_sha256',
  'reconciliation_sha256','sealed_queue_sha256','source_account_sha256','source_api_sha256','source_auth_sha256',
  'source_fence_sha256','source_gateway_sha256','target_api_sha256','target_auth_sha256','target_device_key_sha256','target_fence_sha256',
  'target_gateway_sha256','target_primary_account_sha256'] LOOP
  IF p->>k !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'fixture_binding_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
END;$f$;

CREATE FUNCTION commissioning_fixture.issue(p jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
DECLARE prior commissioning_fixture.receipts%ROWTYPE; now_epoch bigint; result jsonb; tid uuid;
BEGIN
 PERFORM commissioning_fixture.validate_binding(p);tid:=(p->>'transition_id')::uuid;
 -- Serialize identical transition IDs. Unique constraints cover competing IDs
 -- for the same installation generation or target device-key digest.
 PERFORM pg_advisory_xact_lock(hashtextextended(tid::text,0));
 SELECT * INTO prior FROM commissioning_fixture.receipts WHERE transition_id=tid;
 IF FOUND THEN
  IF prior.binding IS DISTINCT FROM p THEN RAISE EXCEPTION 'fixture_transition_conflict' USING ERRCODE='23505';END IF;
  RETURN prior.receipt;
 END IF;
 now_epoch:=floor(extract(epoch FROM clock_timestamp()))::bigint;
 IF (p->>'expires_epoch')::bigint<=now_epoch OR (p->>'expires_epoch')::bigint>now_epoch+900 THEN
  RAISE EXCEPTION 'fixture_expiry_invalid' USING ERRCODE='22023';END IF;
 result:=jsonb_build_object('format','collect.fixture.commissioning-receipt.v1',
  'receipt_id',gen_random_uuid()::text,'binding',p);
 BEGIN
  INSERT INTO commissioning_fixture.receipts(transition_id,installation_sha256,queue_generation,target_device_key_sha256,binding,receipt,expires_epoch)
   VALUES(tid,p->>'installation_sha256',(p->>'queue_generation')::bigint,p->>'target_device_key_sha256',p,result,(p->>'expires_epoch')::bigint);
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'fixture_transition_conflict' USING ERRCODE='23505';END;
 RETURN result;
END;$f$;

CREATE FUNCTION commissioning_fixture.consume(p jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
DECLARE prior commissioning_fixture.consumptions%ROWTYPE;r commissioning_fixture.receipts%ROWTYPE;
 supplied text[];tid uuid;ack jsonb;
BEGIN
 PERFORM commissioning_fixture.fixture_only();
 IF p IS NULL OR jsonb_typeof(p)<>'object' OR octet_length(p::text)>2048 THEN
  RAISE EXCEPTION 'fixture_consumption_invalid' USING ERRCODE='22023';END IF;
 SELECT array_agg(key ORDER BY key) INTO supplied FROM jsonb_object_keys(p) AS keys(key);
 IF supplied IS DISTINCT FROM ARRAY['consume_id','installation_sha256','receipt_id','target_device_key_sha256','transition_id']::text[]
  OR EXISTS(SELECT 1 FROM jsonb_each(p) e WHERE jsonb_typeof(e.value)<>'string')
  OR p->>'transition_id' !~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
  OR p->>'consume_id' !~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
  OR p->>'receipt_id' !~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
  OR p->>'installation_sha256' !~ '^[a-f0-9]{64}$' OR p->>'target_device_key_sha256' !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'fixture_consumption_invalid' USING ERRCODE='22023';END IF;
 tid:=(p->>'transition_id')::uuid;
 SELECT * INTO r FROM commissioning_fixture.receipts WHERE transition_id=tid FOR UPDATE;
 IF NOT FOUND OR r.receipt->>'receipt_id' IS DISTINCT FROM p->>'receipt_id'
  OR r.installation_sha256 IS DISTINCT FROM p->>'installation_sha256'
  OR r.target_device_key_sha256 IS DISTINCT FROM p->>'target_device_key_sha256' THEN
  RAISE EXCEPTION 'fixture_consumption_refused' USING ERRCODE='42501';END IF;
 SELECT * INTO prior FROM commissioning_fixture.consumptions WHERE transition_id=tid;
 IF FOUND THEN
  IF prior.request IS DISTINCT FROM p THEN RAISE EXCEPTION 'fixture_consumption_conflict' USING ERRCODE='23505';END IF;
  RETURN prior.acknowledgement;
 END IF;
 IF r.expires_epoch<=floor(extract(epoch FROM clock_timestamp()))::bigint THEN
  RAISE EXCEPTION 'fixture_receipt_expired' USING ERRCODE='55000';END IF;
 ack:=jsonb_build_object('format','collect.fixture.commissioning-consumption.v1','transition_id',tid::text,
  'consume_id',p->>'consume_id','receipt_id',p->>'receipt_id','state','consumed');
 BEGIN
  INSERT INTO commissioning_fixture.consumptions(transition_id,consume_id,request,acknowledgement)
   VALUES(tid,(p->>'consume_id')::uuid,p,ack);
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'fixture_consumption_conflict' USING ERRCODE='23505';END;
 RETURN ack;
END;$f$;

CREATE FUNCTION commissioning_fixture.status(p jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
DECLARE r commissioning_fixture.receipts%ROWTYPE;c commissioning_fixture.consumptions%ROWTYPE;
BEGIN
 PERFORM commissioning_fixture.validate_binding(p);
 SELECT * INTO r FROM commissioning_fixture.receipts WHERE transition_id=(p->>'transition_id')::uuid;
 IF NOT FOUND THEN RETURN jsonb_build_object('state','absent_at_snapshot');END IF;
 IF r.binding IS DISTINCT FROM p THEN RAISE EXCEPTION 'fixture_transition_conflict' USING ERRCODE='23505';END IF;
 SELECT * INTO c FROM commissioning_fixture.consumptions WHERE transition_id=r.transition_id;
 RETURN jsonb_build_object('state','found','receipt',r.receipt,'consumption',c.acknowledgement);
END;$f$;

CREATE FUNCTION commissioning_fixture.no_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
BEGIN RAISE EXCEPTION 'fixture_receipt_immutable' USING ERRCODE='55000';END;$f$;
CREATE TRIGGER receipt_no_change BEFORE UPDATE OR DELETE OR TRUNCATE ON commissioning_fixture.receipts
 FOR EACH STATEMENT EXECUTE FUNCTION commissioning_fixture.no_change();
CREATE TRIGGER consumption_no_change BEFORE UPDATE OR DELETE OR TRUNCATE ON commissioning_fixture.consumptions
 FOR EACH STATEMENT EXECUTE FUNCTION commissioning_fixture.no_change();
-- With the default constraint mode, recheck expiry at commit. A caller can set
-- deferred constraints immediate, so this is not a stand-alone guarantee about
-- transaction timing. An upstream trusted transaction boundary is still needed.
-- Exact replay of already committed rows inserts nothing.
CREATE FUNCTION commissioning_fixture.check_commit_expiry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $f$
DECLARE expiry bigint;
BEGIN
 IF TG_TABLE_NAME='receipts' THEN expiry:=NEW.expires_epoch;
 ELSE SELECT expires_epoch INTO expiry FROM commissioning_fixture.receipts WHERE transition_id=NEW.transition_id;END IF;
 IF expiry IS NULL OR expiry<=floor(extract(epoch FROM clock_timestamp()))::bigint THEN
  RAISE EXCEPTION 'fixture_receipt_expired' USING ERRCODE='55000';END IF;
 RETURN NEW;
END;$f$;
CREATE CONSTRAINT TRIGGER receipt_commit_expiry AFTER INSERT ON commissioning_fixture.receipts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION commissioning_fixture.check_commit_expiry();
CREATE CONSTRAINT TRIGGER consumption_commit_expiry AFTER INSERT ON commissioning_fixture.consumptions
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION commissioning_fixture.check_commit_expiry();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA commissioning_fixture FROM PUBLIC,collect_commissioning_fixture_runtime;
GRANT USAGE ON SCHEMA commissioning_fixture TO collect_commissioning_fixture_runtime;
GRANT EXECUTE ON FUNCTION commissioning_fixture.issue(jsonb),commissioning_fixture.consume(jsonb),commissioning_fixture.status(jsonb)
 TO collect_commissioning_fixture_runtime;
COMMIT;
