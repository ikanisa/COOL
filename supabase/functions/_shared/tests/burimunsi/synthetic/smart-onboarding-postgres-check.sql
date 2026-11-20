-- Synthetic fixture assertions only. All names, IDs and payloads below are fake.
SET ROLE collect_runtime;
SELECT set_config('burimunsi.collection_id','group-1',false);
DO $test$
DECLARE a uuid:='11111111-1111-4111-8111-111111111111';
 s uuid:='22222222-2222-4222-8222-222222222222';
 r uuid:='33333333-3333-4333-8333-333333333333';
 q uuid:='44444444-4444-4444-8444-444444444444';
 source text:=repeat('a',64); fp text; body jsonb; affected integer;
 sealed text:='{"v":1,"kid":"synthetic","iv":"AAAAAAAAAAAAAAAA","data":"AAAAAAAAAAAAAAAAAAAAAA=="}';
BEGIN
 fp:=encode(sha256(convert_to('burimunsi.smart_import.v1'||E'\n'||'group-1'||E'\n'||a::text||E'\n'||source,'UTF8')),'hex');
 body:=jsonb_build_object('v',1,'state','reserved','reservationId',q::text,'sourceSha256',source,
  'mimeType','image/png','policySha256',repeat('b',64),'decoderBuildSha256',repeat('c',64),
  'ciphertext',NULL,'previewSha256',NULL);
 INSERT INTO private.burimunsi_command_receipts VALUES('group-1',a,r,s,'burimunsi.smart_import.v1',fp,body,1);
 INSERT INTO private.burimunsi_command_receipts VALUES('group-1',a,'55555555-5555-4555-8555-555555555555',s,
  'burimunsi.smart_import.v1',fp,body,2) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS affected=ROW_COUNT;IF affected<>0 THEN RAISE EXCEPTION 'duplicate reservation was inserted';END IF;
 INSERT INTO private.burimunsi_command_receipts VALUES('group-1',a,'66666666-6666-4666-8666-666666666666',s,
  'other.operation',fp,'{}'::jsonb,3);
 INSERT INTO private.burimunsi_command_receipts VALUES('group-1',a,'99999999-9999-4999-8999-999999999999',s,
  'other.operation',fp,'"other scalar receipt"'::jsonb,3);
 BEGIN
  INSERT INTO private.burimunsi_command_receipts VALUES('group-1',a,'77777777-7777-4777-8777-777777777777',s,
   'burimunsi.smart_import.v1',repeat('f',64),body,4);
  RAISE EXCEPTION 'incorrect fingerprint accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 BEGIN
  INSERT INTO private.burimunsi_command_receipts VALUES('group-1',a,'77777777-7777-4777-8777-777777777777',s,
   'burimunsi.smart_import.v1',fp,jsonb_set(body,'{sourceSha256}','null'::jsonb),4);
  RAISE EXCEPTION 'null source digest accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 BEGIN
  UPDATE private.burimunsi_command_receipts SET response=jsonb_set(response,'{state}','"completed"'::jsonb) WHERE request_id=r;
  RAISE EXCEPTION 'skipped phases accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 UPDATE private.burimunsi_command_receipts SET response=jsonb_set(response,'{state}','"decode"'::jsonb) WHERE request_id=r;
 BEGIN
  UPDATE private.burimunsi_command_receipts SET response=jsonb_set(response,'{sourceSha256}',to_jsonb(repeat('d',64))) WHERE request_id=r;
  RAISE EXCEPTION 'identity mutation accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 UPDATE private.burimunsi_command_receipts SET response=jsonb_set(response,'{state}','"extract"'::jsonb) WHERE request_id=r;
 BEGIN
  UPDATE private.burimunsi_command_receipts SET response=response||jsonb_build_object('state','completed','ciphertext','plain member data','previewSha256',repeat('d',64)) WHERE request_id=r;
  RAISE EXCEPTION 'plaintext envelope accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 UPDATE private.burimunsi_command_receipts SET response=response||jsonb_build_object('state','completed','ciphertext',sealed,'previewSha256',repeat('d',64)) WHERE request_id=r;
 BEGIN
  UPDATE private.burimunsi_command_receipts SET response=response WHERE request_id=r;
  RAISE EXCEPTION 'completed outcome was mutable';
 EXCEPTION WHEN check_violation THEN NULL;END;
 BEGIN
  INSERT INTO private.burimunsi_command_receipts VALUES('group-2',a,'88888888-8888-4888-8888-888888888888',s,
   'other.operation',fp,'{}'::jsonb,5);
  RAISE EXCEPTION 'cross-group insert accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF (SELECT count(*) FROM private.burimunsi_command_receipts WHERE collection_id='group-2')<>0 THEN
  RAISE EXCEPTION 'cross-group row visible';END IF;
END;$test$;
RESET ROLE;
SELECT 'synthetic_smart_onboarding_postgres_passed' AS result;
