-- LAST disposable qualification fixture. Synthetic setup/retirement commits
-- first; an independent real RR READ ONLY transaction recovers its exact ACK.
-- This exercises a committed-outcome read, not a lost external network ACK.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','buri-qualification-group',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true);
__NATIVE_PAIR_INPUTS__
__HANDOFF_SUPPORT__
COMMIT;
-- Harness runs actual native/Owner transactions on two distinct connections,
-- observes Owner waiting on the exact setup lock, and never replays either.
__HANDOFF_RACE__
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('request.jwt.claims','{}',true);
DO $readonly$ DECLARE result jsonb;BEGIN
 PERFORM pg_temp.h_check(current_setting('transaction_read_only')='on' AND current_setting('transaction_isolation')='repeatable read','actual primary RR READ ONLY');
 result:=private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'));
 PERFORM pg_temp.h_check(result->>'kind'='gateway_retirement_outcome' AND result->>'state'='retired'
 AND result->'ack'=jsonb_build_object('retired',true,'handoffId','fd331000-0000-4000-8000-000000000002',
 'requestId','fd332000-0000-4000-8000-000000000001','reauthenticationRequired',true),'committed retirement exact limited acknowledgement');
 PERFORM pg_temp.h_check((SELECT count(*) FROM jsonb_object_keys(result))=10 AND NOT(result ?| ARRAY['capabilities','binding','gateway_token','pairingCode']), 'limited response has no ordinary authority or target secret');
 PERFORM pg_temp.h_check(api.current_principal_id() IS NULL AND api.current_session_id() IS NULL
 AND NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_context()),'outcome never composes normal actor');
 PERFORM pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('new-current'),'fd330000-0000-4000-8000-000000000002',pg_temp.h_raw('new-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'same principal sibling installation cannot recover old receipt');
 PERFORM pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(encode(sha256(convert_to(pg_temp.h_raw('old-current'),'UTF8')),'hex'),
 'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),'internal_receiver','fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'stored token hash is not raw bearer');
 PERFORM pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000099',repeat('f',64)) IS NULL,'no receipt cannot recover using retired scope');
END;$readonly$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','buri-qualification-group',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true);
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
UPDATE private.burimunsi_sessions SET revoked=true WHERE installation_id IN('fd330000-0000-4000-8000-000000000001','fd330000-0000-4000-8000-000000000002');
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE installation_id IN('fd330000-0000-4000-8000-000000000001','fd330000-0000-4000-8000-000000000002');
COMMIT;
