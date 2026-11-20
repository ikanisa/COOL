-- Reused only by the disposable SQL qualification contracts. These synthetic
-- tokens/ciphertexts are public fixtures, not working provider credentials.
CREATE FUNCTION pg_temp.h_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Gateway handoff qualification: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.h_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN
 IF SQLSTATE=expected THEN RETURN;END IF;
 RAISE EXCEPTION 'Handoff SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;RAISE EXCEPTION 'Expected handoff SQLSTATE %',expected;END;$fn$;
CREATE FUNCTION pg_temp.h_raw(label text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
 SELECT encode(sha256(convert_to('qualification.handoff.v1.'||label,'UTF8')),'hex')
$fn$;
CREATE FUNCTION pg_temp.h_fingerprint(label text,request uuid) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
 SELECT encode(sha256(convert_to('burimunsi.gateway.retire.v1:'||encode(sha256(convert_to(pg_temp.h_raw(label),'UTF8')),'hex')||':'||request::text,'UTF8')),'hex')
$fn$;
CREATE FUNCTION pg_temp.h_owner() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 PERFORM set_config('burimunsi.pin_token','',true),set_config('burimunsi.pin_installation','',true),
  set_config('burimunsi.pin_device','',true),set_config('burimunsi.pin_profile','',true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
  'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
END;$fn$;
CREATE FUNCTION pg_temp.h_login(label text,installation uuid,device text,account uuid DEFAULT 'f7000000-0000-4000-8000-000000000001')
 RETURNS jsonb LANGUAGE sql AS $fn$
 -- A realistic server-issued past timestamp avoids assuming a strictly
 -- monotonic wall clock between creation and immediate set-context. SQL32's
 -- unchanged +/-5s creation bound and strict future-session denial still apply.
 WITH issued AS MATERIALIZED(SELECT floor(extract(epoch FROM clock_timestamp())*1000)::bigint-1000 AS created_ms)
 SELECT private.burimunsi_pin_create_session('buri-qualification-group',account,installation,'internal_receiver',
 encode(sha256(convert_to(pg_temp.h_raw(device),'UTF8')),'hex'),1,gen_random_uuid(),
 encode(sha256(convert_to(pg_temp.h_raw(label),'UTF8')),'hex'),issued.created_ms,issued.created_ms+1800000,1)
 FROM issued
$fn$;
CREATE FUNCTION pg_temp.h_set(label text,installation uuid,device text) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT private.burimunsi_set_pin_context(pg_temp.h_raw(label),installation,pg_temp.h_raw(device),'internal_receiver')
$fn$;
CREATE FUNCTION pg_temp.h_directory() RETURNS jsonb LANGUAGE plpgsql AS $fn$
BEGIN PERFORM pg_temp.h_owner();RETURN private.burimunsi_setup_directory('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group');END;$fn$;
CREATE FUNCTION pg_temp.h_apply(command jsonb,delivery jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $fn$
BEGIN PERFORM pg_temp.h_owner();RETURN private.burimunsi_setup_apply('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001',command,
 encode(sha256(convert_to(command::text,'UTF8')),'hex'),delivery);END;$fn$;
CREATE FUNCTION pg_temp.h_lookup(request uuid,delivery boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql AS $fn$
BEGIN PERFORM pg_temp.h_owner();RETURN private.burimunsi_setup_lookup('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',request,delivery);END;$fn$;
CREATE TEMP TABLE h_state(name text PRIMARY KEY,value jsonb NOT NULL) ON COMMIT PRESERVE ROWS;
GRANT SELECT,INSERT,UPDATE ON h_state TO collect_runtime;
CREATE FUNCTION pg_temp.h_get(name text) RETURNS jsonb LANGUAGE sql AS $fn$ SELECT value FROM pg_temp.h_state s WHERE s.name=$1 $fn$;
CREATE FUNCTION pg_temp.h_delivery(command jsonb,code_label text,binding text,pairing text) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT jsonb_build_object('bindingId',binding,'pairingId',pairing,'codeHash',encode(sha256(convert_to(pg_temp.h_raw(code_label),'UTF8')),'hex'),
 'ciphertext',repeat('QUALIFICATION-ONLY-',12),'binding',jsonb_build_object('profileSha',repeat('1',64),
 'actorId','f3000000-0000-4000-8000-000000000001','sessionId','f2000000-0000-4000-8000-000000000001',
 'collectionId',command->>'collectionId','requestId',command->>'requestId','receivingAccountId',command->>'receivingAccountId',
 'expectedScopeVersion',(command->>'expectedScopeVersion')::bigint,'bindingId',binding,'pairingId',pairing,
 'installationId',command->>'installationId','custodianAccountId',command->>'custodianAccountId','grantId',command->>'grantId',
 'grantVersion',(command->>'expectedGrantVersion')::bigint,'subscriptionId',(command->>'subscriptionId')::bigint)
 ||CASE WHEN command->>'operation'='prepare_replacement' THEN jsonb_build_object(
 'expectedBindingId',command->>'expectedBindingId','expectedBindingVersion',(command->>'expectedBindingVersion')::bigint,
 'expectedReceiverKeyId',command->>'expectedReceiverKeyId') ELSE '{}'::jsonb END)
$fn$;
CREATE FUNCTION pg_temp.h_capture(p_id text,p_credential text,p_completeness text,p_mode text,p_receiver text DEFAULT repeat('c',64))
 RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE plain text;sealed text;plain_sha text;body_sha text;cipher_sha text;scope jsonb;custom jsonb;fingerprint text;
BEGIN
 INSERT INTO private.storage_namespace(singleton,origin,bucket) VALUES(true,'https://qualification-storage.invalid','qualification-handoff') ON CONFLICT(singleton) DO NOTHING;
 plain:=jsonb_build_object('raw_sender','QUALIFICATION SMS','raw_body','QUALIFICATION SOURCE '||p_id,
  'completeness',p_completeness,'source_mode',p_mode)::text;
 sealed:=jsonb_build_object('v',1,'kid','qualification-only','note','NOT ENCRYPTED PROVIDER BYTES','source',p_id)::text;
 plain_sha:=encode(sha256(convert_to(plain,'UTF8')),'hex');body_sha:=encode(sha256(convert_to('QUALIFICATION SOURCE '||p_id,'UTF8')),'hex');
 cipher_sha:=encode(sha256(convert_to(sealed,'UTF8')),'hex');fingerprint:=encode(sha256(convert_to('qualification:'||p_id,'UTF8')),'hex');
 scope:=jsonb_build_object('ownerId','f3000000-0000-4000-8000-000000000001','purpose','sms_receipt','entityId',p_id);
 custom:=jsonb_build_object('sha256',plain_sha,'key_id','qualification-only','source_fingerprint',fingerprint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
 VALUES('sms/'||p_id,fingerprint,scope,'sms:'||p_id||':'||plain_sha,'qualification-only',plain_sha,sealed);
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
 VALUES('qualification:'||p_id,'sms/'||p_id,fingerprint,cipher_sha,octet_length(sealed),scope,'{"contentType":"application/octet-stream"}',custom,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
 VALUES('sms/'||p_id,'qualification:'||p_id,fingerprint,cipher_sha,octet_length(sealed),scope,'{"contentType":"application/octet-stream"}',custom);
 INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,
  object_key,object_sha256,size_bytes,received_at_device,created_at)
 VALUES(p_id,'f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001',p_id,
  body_sha,p_receiver,'sms/'||p_id,plain_sha,octet_length(plain),'2026-11-09 09:00:00',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_gateway_captures(raw_sms_id,credential_id,identity_sha256,service_centre_at,captured_at,
  inbox_received_at,subscription_id,completeness,source_mode,created_at)
 VALUES(p_id,p_credential,fingerprint,NULL,app.strftime('%Y-%m-%dT%H:%M:%fZ'),NULL,NULL,p_completeness,p_mode,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
END;$fn$;
CREATE FUNCTION pg_temp.h_transaction(p_source text,p_id text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE attempt text:=p_id||'-parse';source_hash text;
BEGIN
 SELECT body_sha256 INTO STRICT source_hash FROM app.sms_receipts WHERE id=p_source;
 INSERT INTO app.momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at)
 VALUES(p_source,'handoff-old-binding',1,'buri-qualification-wallet','live','completed',app.unixepoch(),app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,
 profile_version,profile_json,source_body_sha256,validation_json,outcome,created_at)
 VALUES(attempt,p_source,1,'qualification-only','qualification-only','qualification-only','qualification-only',
 'qualification-only','{}',source_hash,'[]','accepted',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,
 transaction_datetime_raw,transaction_timezone,transaction_time_source,parse_attempt_id,mode,created_at,updated_at)
 VALUES(p_id,'buri-qualification-wallet','mtn_momo',p_id,'incoming_receipt',100,'RWF',0,'2026-11-10 09:00:00','Africa/Kigali','provider_sms',
 attempt,'live',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO private.burimunsi_transaction_scopes(transaction_id,collection_id,receiving_account_id,source_binding_id,source_binding_version,policy_version,created_at)
 VALUES(p_id,'buri-qualification-group','buri-qualification-wallet','handoff-old-binding',1,'qualification-only',1);
 INSERT INTO app.momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at)
 VALUES(p_id,p_source,attempt,'accepted',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
END;$fn$;
CREATE FUNCTION pg_temp.h_seed_financial_storage(k text,owner_id text,entity text,plain_sha text,purpose text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE scope_json jsonb:=jsonb_build_object('ownerId',owner_id,'entityId',entity,'purpose',purpose);metadata jsonb:=jsonb_build_object('sha256',plain_sha,'source_fingerprint',repeat('d',64));
BEGIN
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES(k,repeat('d',64),scope_json,'synthetic-only','fixture',plain_sha,'synthetic-encrypted-envelope');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state) VALUES('fixture:'||k,k,repeat('e',64),repeat('f',64),30,scope_json,'{}',metadata,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata) VALUES(k,'fixture:'||k,repeat('e',64),repeat('f',64),30,scope_json,'{}',metadata);
END$$;

-- Initial disabled scope, genuine automatic registration and no custody claim.
SELECT pg_temp.h_owner();
UPDATE app.collections SET receiver_network='mtn_momo',receiver_momo_number='00000' WHERE id='buri-qualification-group';
UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT pg_temp.h_login('old-before','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_login('new-before','fd330000-0000-4000-8000-000000000002','new-device');
SELECT pg_temp.h_login('sibling-before','fd330000-0000-4000-8000-000000000001','old-device','f7000000-0000-4000-8000-000000000002');
DO $candidate$
DECLARE directory jsonb;row jsonb;command jsonb;
BEGIN
 directory:=pg_temp.h_directory();
 PERFORM pg_temp.h_check(jsonb_array_length(directory->'installations')=2,'only genuine approved native admin candidates');
 FOR row IN SELECT value FROM jsonb_array_elements(directory->'installations') LOOP
  PERFORM pg_temp.h_check(row->>'custodyAssigned'='false' AND row->>'custodianAccountId'='f7000000-0000-4000-8000-000000000001','unassigned candidate is informational');
 END LOOP;
 SELECT jsonb_build_object('operation','activate','collectionId','buri-qualification-group','requestId','fd331000-0000-4000-8000-000000000001',
 'expectedScopeVersion',1,'receivingAccountId','buri-qualification-wallet','reason','QUALIFICATION initial activation',
 'installationId',d.installation_id,'grantId',d.id,'custodianAccountId','f7000000-0000-4000-8000-000000000001',
 'expectedGrantVersion',d.version,'subscriptionId',7) INTO command FROM private.burimunsi_device_grants d WHERE installation_id='fd330000-0000-4000-8000-000000000001';
 INSERT INTO pg_temp.h_state VALUES('activate',pg_temp.h_apply(command,pg_temp.h_delivery(command,'initial-code','handoff-old-binding','handoff-old-pairing')));
 PERFORM pg_temp.h_check(pg_temp.h_get('activate')->>'scopeVersion'='2','initial activate increments scope');
 PERFORM pg_temp.h_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(pg_temp.h_raw('old-before'),
 'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),'internal_receiver')),'activation does not silently rebase native auth');
END;$candidate$;
SELECT pg_temp.h_login('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_login('new-current','fd330000-0000-4000-8000-000000000002','new-device');
SELECT pg_temp.h_login('sibling-current','fd330000-0000-4000-8000-000000000001','old-device','f7000000-0000-4000-8000-000000000002');
SELECT pg_temp.h_set('new-current','fd330000-0000-4000-8000-000000000002','new-device');
SELECT pg_temp.h_check(NOT private.burimunsi_gateway_pair_target(pg_temp.h_raw('initial-code'),'fd330000-0000-4000-8000-000000000002'),'code cannot pair a different installation');
SELECT pg_temp.h_owner();
SELECT pg_temp.h_check(NOT private.burimunsi_gateway_pair_target(pg_temp.h_raw('initial-code'),'fd330000-0000-4000-8000-000000000001'),'web proof alone cannot pair native target');
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_check(private.burimunsi_gateway_pair_target(pg_temp.h_raw('initial-code'),'fd330000-0000-4000-8000-000000000001'),'exact fresh native initial pair target');
SELECT pg_temp.h_check((SELECT count(*) FROM pg_temp.h_native_pair(encode(sha256(convert_to(pg_temp.h_raw('initial-code'),'UTF8')),'hex'),
 'buri-qualification-group','fd330000-0000-4000-8000-000000000001'))=0,'actual adapter SELECT requires target custody');
SELECT pg_temp.h_check((SELECT result->'result'->>'claimed' FROM pg_temp.h_native_custody('buri-qualification-group',api.current_session_id(),
 'fd330000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000001') AS returned(result))='true','actual adapter claims only after target guard');
SELECT pg_temp.h_check((SELECT count(*) FROM pg_temp.h_native_pair(encode(sha256(convert_to(pg_temp.h_raw('initial-code'),'UTF8')),'hex'),
 'buri-qualification-group','fd330000-0000-4000-8000-000000000001'))=1,'actual exported adapter Pair SQL selects NULL-custody target after narrow claim');
-- Synthetic stand-in for the JS canonical credential transaction, after actual
-- SQL target admission. Its ciphertext is unusable and never sent to a device.
RESET ROLE;
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('handoff-old-key','handoff-old-binding','handoff-old-pairing','fd330000-0000-4000-8000-000000000001',
 pg_temp.h_raw('old-gateway-key'),'QUALIFICATION NOT A REAL GATEWAY CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE app.momo_gateway_pairings SET claimed_installation_id='fd330000-0000-4000-8000-000000000001' WHERE id='handoff-old-pairing';
SET LOCAL ROLE collect_runtime;
DO $prepare$
DECLARE command jsonb;result jsonb;before jsonb;directory jsonb;
BEGIN
 before:=(SELECT jsonb_build_object('version',s.version,'binding',s.active_binding_id,'status',b.status,'revoked',c.revoked_at)
 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id JOIN app.momo_gateway_credentials c ON c.binding_id=b.id WHERE s.collection_id='buri-qualification-group');
 SELECT jsonb_build_object('operation','prepare_replacement','collectionId','buri-qualification-group',
 'requestId','fd331000-0000-4000-8000-000000000002','expectedScopeVersion',2,'receivingAccountId','buri-qualification-wallet',
 'reason','QUALIFICATION target bound replacement','installationId',d.installation_id,'grantId',d.id,
 'custodianAccountId','f7000000-0000-4000-8000-000000000001','expectedGrantVersion',d.version,'subscriptionId',8,
 'expectedBindingId','handoff-old-binding','expectedBindingVersion',1,'expectedReceiverKeyId','handoff-old-key') INTO command
 FROM private.burimunsi_device_grants d WHERE installation_id='fd330000-0000-4000-8000-000000000002';
 INSERT INTO pg_temp.h_state VALUES('prepare-command',command),('prepare-delivery',pg_temp.h_delivery(command,'replacement-code','handoff-new-binding','handoff-new-pairing'));
 result:=pg_temp.h_apply(command,pg_temp.h_get('prepare-delivery'));
 INSERT INTO pg_temp.h_state VALUES('prepared',result);
 PERFORM pg_temp.h_check((SELECT count(*) FROM jsonb_object_keys(result))=21 AND result->>'scopeVersion'='2' AND result->>'retirementRequired'='true','immutable21 prepared receipt retains scope');
 PERFORM pg_temp.h_check(before=(SELECT jsonb_build_object('version',s.version,'binding',s.active_binding_id,'status',b.status,'revoked',c.revoked_at)
 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id JOIN app.momo_gateway_credentials c ON c.binding_id=b.id WHERE s.collection_id='buri-qualification-group'),'prepare does not retire capture');
 PERFORM pg_temp.h_check(pg_temp.h_apply(command,pg_temp.h_get('prepare-delivery'))=result,'original prepare result retained');
 directory:=pg_temp.h_directory();
 PERFORM pg_temp.h_check(directory->'scopes'->0->'pendingReplacement'->>'phase'='prepared' AND directory->'scopes'->0->>'receiverKeyId'='handoff-old-key','prepared directory frozen tuple');
 PERFORM pg_temp.h_check(pg_temp.h_lookup('fd331000-0000-4000-8000-000000000002',true)->>'phase'='prepared','same challenge delivery before retirement');
END;$prepare$;
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
