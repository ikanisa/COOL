-- Immutable capture routing. A wallet's current group is not historical proof.
-- Existing unassociated captures are deliberately not guessed or backfilled.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regclass('private.burimunsi_operator_approvals') IS NULL
  OR to_regclass('private.burimunsi_sms_source_scopes') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_source_scope_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE TABLE private.burimunsi_sms_source_scopes (
 source_id text PRIMARY KEY REFERENCES app.sms_receipts(id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
 owner_user_id text NOT NULL REFERENCES app.users(id),
 source_body_sha256 text NOT NULL CHECK(source_body_sha256 ~ '^[a-f0-9]{64}$'),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[a-f0-9]{64}$'),
 binding_id text,
 binding_version bigint,
 credential_id text REFERENCES app.momo_gateway_credentials(id),
 installation_id uuid,
 custodian_account_id uuid,
 grant_id uuid,
 grant_version bigint,
 provenance text NOT NULL CHECK(provenance IN('gateway_capture','owner_adoption')),
 proof_id text NOT NULL CHECK(length(proof_id) BETWEEN 1 AND 200),
 proof_sha256 text NOT NULL CHECK(proof_sha256 ~ '^[a-f0-9]{64}$'),
 associated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(binding_id,binding_version,receiving_account_id)
  REFERENCES app.momo_gateway_bindings(id,version,receiving_account_id),
 FOREIGN KEY(custodian_account_id,collection_id)
  REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id)
  REFERENCES private.burimunsi_device_grants(id,collection_id),
 CHECK((binding_id IS NULL AND binding_version IS NULL AND credential_id IS NULL AND installation_id IS NULL)
    OR (binding_id IS NOT NULL AND binding_version>0 AND credential_id IS NOT NULL AND installation_id IS NOT NULL)),
 CHECK((custodian_account_id IS NULL AND grant_id IS NULL AND grant_version IS NULL)
    OR (custodian_account_id IS NOT NULL AND grant_id IS NOT NULL AND grant_version>0)),
 CHECK(provenance<>'gateway_capture' OR (binding_id IS NOT NULL AND grant_id IS NOT NULL))
);
CREATE INDEX burimunsi_sms_source_collection ON private.burimunsi_sms_source_scopes(collection_id,source_id);
ALTER TABLE private.burimunsi_sms_source_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_sms_source_scopes FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_sms_source_scopes FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT SELECT ON private.burimunsi_sms_source_scopes TO collect_runtime;
CREATE POLICY burimunsi_source_runtime ON private.burimunsi_sms_source_scopes FOR SELECT TO collect_runtime
 USING(collection_id=current_setting('burimunsi.collection_id',true));
CREATE POLICY burimunsi_source_owner ON private.burimunsi_sms_source_scopes TO postgres
 USING(collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
CREATE FUNCTION private.burimunsi_source_scope_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 RAISE EXCEPTION 'burimunsi_source_scope_immutable' USING ERRCODE='23514';
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_source_scope_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_source_scope_immutable BEFORE UPDATE OR DELETE ON private.burimunsi_sms_source_scopes
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_source_scope_immutable();
ALTER TABLE private.burimunsi_sms_source_scopes ENABLE ALWAYS TRIGGER burimunsi_source_scope_immutable;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_sms_source_scopes
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_sms_source_scopes ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

-- The trigger derives a group from the exact canonical credential/binding.
-- This SELECT policy applies only to the installation owner, including a normal
-- NOBYPASSRLS owner. Runtime cannot assume that role or execute the trigger as a
-- function. Its ordinary collection-scoped policy and privileges stay intact.
CREATE POLICY burimunsi_capture_scope_lookup ON private.burimunsi_scopes FOR SELECT TO postgres
 USING(active_binding_id=current_setting('burimunsi.capture_binding_id',true));
CREATE FUNCTION private.burimunsi_scope_new_capture() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE
 old_group text:=current_setting('burimunsi.collection_id',true);
 old_binding text:=current_setting('burimunsi.capture_binding_id',true);
 lineage record;
 selected_group text;
 device record;
 proof jsonb;
BEGIN
 -- Same ordering as every existing Collect capture/authority writer.
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT r.id,r.owner_user_id,r.body_sha256,r.object_sha256,r.receiver_hash,
  k.id AS credential_id,k.binding_id,k.installation_id,
  b.version AS binding_version,b.receiving_account_id
 INTO lineage FROM app.sms_receipts r
 JOIN app.momo_gateway_credentials k ON k.id=NEW.credential_id AND k.revoked_at IS NULL
 JOIN app.momo_gateway_bindings b ON b.id=k.binding_id AND b.owner_user_id=r.owner_user_id AND b.status='active'
 JOIN app.momo_receiving_accounts w ON w.id=b.receiving_account_id AND w.receiver_hash=r.receiver_hash AND w.status='active'
 WHERE r.id=NEW.raw_sms_id;
 IF NOT FOUND THEN RETURN NEW; END IF;
 PERFORM set_config('burimunsi.capture_binding_id',lineage.binding_id,true);
 SELECT s.collection_id INTO selected_group FROM private.burimunsi_scopes s
 WHERE s.active_binding_id=lineage.binding_id AND s.receiving_account_id=lineage.receiving_account_id
  AND s.enabled AND s.binding_version=lineage.binding_version;
 IF selected_group IS NULL THEN
  PERFORM set_config('burimunsi.capture_binding_id',coalesce(old_binding,''),true);
  RETURN NEW;
 END IF;
 PERFORM set_config('burimunsi.collection_id',selected_group,true);
 SELECT d.id,d.version,d.custodian_account_id INTO device
 FROM private.burimunsi_device_grants d
 JOIN private.burimunsi_accounts a ON a.id=d.custodian_account_id AND a.collection_id=d.collection_id
 JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=d.collection_id
 WHERE d.collection_id=selected_group AND d.installation_id::text=lineage.installation_id
  AND d.profile='internal_receiver' AND d.active AND a.active AND NOT a.removed AND a.role='admin'
  AND a.principal_user_id=lineage.owner_user_id
  AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities);
 IF FOUND THEN
  proof:=jsonb_build_object('capture',to_jsonb(NEW),'group',selected_group,'source',to_jsonb(lineage),'device',to_jsonb(device));
  INSERT INTO private.burimunsi_sms_source_scopes(source_id,collection_id,receiving_account_id,owner_user_id,
   source_body_sha256,object_sha256,binding_id,binding_version,credential_id,installation_id,
   custodian_account_id,grant_id,grant_version,provenance,proof_id,proof_sha256)
  VALUES(lineage.id,selected_group,lineage.receiving_account_id,lineage.owner_user_id,
   lineage.body_sha256,lineage.object_sha256,lineage.binding_id,lineage.binding_version,lineage.credential_id,lineage.installation_id::uuid,
   device.custodian_account_id,device.id,device.version,'gateway_capture',NEW.raw_sms_id,
   encode(sha256(convert_to(proof::text,'UTF8')),'hex'));
 END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.capture_binding_id',coalesce(old_binding,''),true);
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_scope_new_capture() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_scope_new_capture AFTER INSERT ON app.momo_gateway_captures
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_scope_new_capture();
ALTER TABLE app.momo_gateway_captures ENABLE ALWAYS TRIGGER burimunsi_scope_new_capture;
COMMIT;
