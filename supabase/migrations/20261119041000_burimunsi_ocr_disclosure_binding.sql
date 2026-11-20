-- Extend the existing receipt class. Retain prior rows, source deduplication,
-- retention inventory, and the trigger that freezes every non-result field.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_command_receipts'::regclass
   AND tgname='burimunsi_smart_import_guard' AND tgenabled='A' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'burimunsi_ocr_disclosure_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

ALTER TABLE private.burimunsi_command_receipts DROP CONSTRAINT burimunsi_smart_import_shape;
ALTER TABLE private.burimunsi_command_receipts ADD CONSTRAINT burimunsi_smart_import_shape CHECK (
 operation<>'burimunsi.smart_import.v1' OR (
 jsonb_typeof(response)='object' AND response ?& ARRAY['v','state','reservationId','sourceSha256','mimeType',
  'policySha256','decoderBuildSha256','ciphertext','previewSha256']::text[]
 AND (
  (response->'v'='1'::jsonb AND
   response-ARRAY['v','state','reservationId','sourceSha256','mimeType','policySha256','decoderBuildSha256','ciphertext','previewSha256']::text[]='{}'::jsonb)
  OR (response->'v'='2'::jsonb AND response ?& ARRAY['importFlowId','ocrDisclosureVersion']
   AND response-ARRAY['v','state','reservationId','sourceSha256','mimeType','policySha256','decoderBuildSha256','ciphertext','previewSha256',
     'importFlowId','ocrDisclosureVersion']::text[]='{}'::jsonb
   AND response->>'importFlowId' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
   AND response->>'ocrDisclosureVersion'='burimunsi-ocr-disclosure-v1'
   AND response->>'mimeType'<>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
 )
 AND response->>'state' IN ('reserved','decode','extract','completed')
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
COMMIT;
