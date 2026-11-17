-- Onboarding preview dispatch custody. Install only under the existing fenced
-- migration path. No users, groups, credentials, uploads or previews are seeded.
-- The existing private command-receipt class is already in the blocked retention
-- inventory; this namespace stores only source hashes and encrypted previews.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regclass('private.burimunsi_command_receipts') IS NULL
  OR to_regclass('private.burimunsi_smart_import_fingerprint') IS NOT NULL
  OR to_regprocedure('private.burimunsi_smart_import_guard()') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid='private.burimunsi_command_receipts'::regclass
       AND c.relrowsecurity AND c.relforcerowsecurity)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='private.burimunsi_command_receipts'::regclass
       AND t.tgname='collect_fence_statement_v1' AND t.tgenabled='A' AND NOT t.tgisinternal)
  OR EXISTS(SELECT 1 FROM private.burimunsi_command_receipts WHERE operation='burimunsi.smart_import.v1')
 THEN RAISE EXCEPTION 'burimunsi_smart_import_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

CREATE UNIQUE INDEX burimunsi_smart_import_fingerprint
 ON private.burimunsi_command_receipts(collection_id,actor_id,fingerprint)
 WHERE operation='burimunsi.smart_import.v1';

ALTER TABLE private.burimunsi_command_receipts ADD CONSTRAINT burimunsi_smart_import_shape CHECK (
 operation<>'burimunsi.smart_import.v1' OR (
 jsonb_typeof(response)='object' AND response ?& ARRAY['v','state','reservationId','sourceSha256','mimeType',
  'policySha256','decoderBuildSha256','ciphertext','previewSha256']::text[]
 AND response-ARRAY['v','state','reservationId','sourceSha256','mimeType','policySha256','decoderBuildSha256','ciphertext','previewSha256']::text[]='{}'::jsonb
 AND response->'v'='1'::jsonb AND response->>'state' IN ('reserved','decode','extract','completed')
 AND response->>'reservationId' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
 AND response->>'sourceSha256' ~ '^[a-f0-9]{64}$' AND response->>'policySha256' ~ '^[a-f0-9]{64}$'
 AND response->>'decoderBuildSha256' ~ '^[a-f0-9]{64}$'
 AND fingerprint=encode(sha256(convert_to('burimunsi.smart_import.v1'||E'\n'||collection_id||E'\n'||actor_id::text||E'\n'||(response->>'sourceSha256'),'UTF8')),'hex')
 AND response->>'mimeType' IN ('image/png','image/jpeg','image/webp','application/pdf',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
 AND CASE WHEN response->>'state'='completed' THEN
   jsonb_typeof(response->'ciphertext')='string' AND octet_length(response->>'ciphertext') BETWEEN 1 AND 3000000
   AND response->>'ciphertext' ~ '^\{"v":1,"kid":"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}","iv":"[A-Za-z0-9+/]{16}","data":"[A-Za-z0-9+/]+={0,2}"\}$'
   AND jsonb_typeof(response->'previewSha256')='string' AND response->>'previewSha256' ~ '^[a-f0-9]{64}$'
  ELSE jsonb_typeof(response->'ciphertext')='null' AND jsonb_typeof(response->'previewSha256')='null' END
 ) IS TRUE);

CREATE FUNCTION private.burimunsi_smart_import_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $guard$
DECLARE metadata_keys text[]:=ARRAY['state','ciphertext','previewSha256'];
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.operation='burimunsi.smart_import.v1' AND NEW.response->>'state'<>'reserved' THEN
   RAISE EXCEPTION 'smart_import_invalid_transition' USING ERRCODE='23514';END IF;
  RETURN NEW;
 END IF;
 IF OLD.operation<>'burimunsi.smart_import.v1' THEN
  IF NEW.operation='burimunsi.smart_import.v1' THEN RAISE EXCEPTION 'smart_import_invalid_transition' USING ERRCODE='23514';END IF;
  RETURN NEW;
 END IF;
 IF (NEW.collection_id,NEW.actor_id,NEW.request_id,NEW.session_id,NEW.operation,NEW.fingerprint,NEW.created_at)
    IS DISTINCT FROM (OLD.collection_id,OLD.actor_id,OLD.request_id,OLD.session_id,OLD.operation,OLD.fingerprint,OLD.created_at)
  OR (NEW.response-metadata_keys) IS DISTINCT FROM (OLD.response-metadata_keys)
  OR NOT ((OLD.response->>'state'='reserved' AND NEW.response->>'state'='decode')
   OR (OLD.response->>'state'='decode' AND NEW.response->>'state'='extract' AND OLD.response->>'mimeType'<>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
   OR (OLD.response->>'state'='decode' AND NEW.response->>'state'='completed' AND OLD.response->>'mimeType'='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
   OR (OLD.response->>'state'='extract' AND NEW.response->>'state'='completed' AND OLD.response->>'mimeType'<>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'))
 THEN RAISE EXCEPTION 'smart_import_invalid_transition' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$guard$;
REVOKE ALL ON FUNCTION private.burimunsi_smart_import_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_smart_import_guard() TO collect_runtime;
CREATE TRIGGER burimunsi_smart_import_guard BEFORE INSERT OR UPDATE ON private.burimunsi_command_receipts
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_smart_import_guard();
ALTER TABLE private.burimunsi_command_receipts ENABLE ALWAYS TRIGGER burimunsi_smart_import_guard;
COMMIT;
