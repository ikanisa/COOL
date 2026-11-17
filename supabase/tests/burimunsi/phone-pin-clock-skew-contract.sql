-- SYNTHETIC ONLY: future and past edge clocks never issue a not-yet-valid PIN session.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
DO $contract$
DECLARE server_now bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;client_now bigint;created jsonb;actor record;denied boolean;
BEGIN
 -- A permitted clock lead returns an immediately usable session, with no TTL extension.
 client_now:=server_now+4000;
 created:=private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fe900000-0000-4000-8000-000000000091','internal_receiver',encode(sha256(convert_to(repeat('2',64),'UTF8')),'hex'),
  1,gen_random_uuid(),encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'),client_now,client_now+1800000,1);
 SELECT * INTO actor FROM private.burimunsi_pin_session_context(repeat('1',64),
  'fe900000-0000-4000-8000-000000000091',repeat('2',64),'internal_receiver');
 IF NOT FOUND OR actor.created_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint
  OR actor.created_at>client_now OR actor.expires_at-actor.created_at<>1800000
  OR actor.expires_at IS DISTINCT FROM (created->>'expiresAt')::bigint OR (created->>'expiresAt')::bigint>client_now+1800000
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_sessions s JOIN private.burimunsi_pin_session_links l ON l.native_session_id=s.id
   WHERE s.id=actor.native_session_id AND s.created_at=l.created_at AND s.created_at=actor.created_at) THEN
  RAISE EXCEPTION 'future clock was not normalized or expanded the session';END IF;
 PERFORM private.burimunsi_set_pin_context(repeat('1',64),'fe900000-0000-4000-8000-000000000091',repeat('2',64),'internal_receiver');
 -- A permitted lag keeps the earlier edge timestamp and exact TTL.
 client_now:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint-4000;
 created:=private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fe900000-0000-4000-8000-000000000092','internal_receiver',encode(sha256(convert_to(repeat('4',64),'UTF8')),'hex'),
  1,gen_random_uuid(),encode(sha256(convert_to(repeat('3',64),'UTF8')),'hex'),client_now,client_now+1800000,1);
 SELECT * INTO actor FROM private.burimunsi_pin_session_context(repeat('3',64),
  'fe900000-0000-4000-8000-000000000092',repeat('4',64),'internal_receiver');
 IF NOT FOUND OR actor.created_at<>client_now OR actor.expires_at<>client_now+1800000
  OR (created->>'expiresAt')::bigint<>actor.expires_at
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_sessions s JOIN private.burimunsi_pin_session_links l ON l.native_session_id=s.id
   WHERE s.id=actor.native_session_id AND s.created_at=l.created_at AND s.created_at=actor.created_at)
  THEN RAISE EXCEPTION 'past clock session mismatch';END IF;
 -- A short positive TTL is not expanded when the edge is ahead.
 client_now:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+4000;
 created:=private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fe900000-0000-4000-8000-000000000095','internal_receiver',encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  1,gen_random_uuid(),encode(sha256(convert_to(repeat('b',64),'UTF8')),'hex'),client_now,client_now+15000,1);
 SELECT * INTO actor FROM private.burimunsi_pin_session_context(repeat('b',64),
  'fe900000-0000-4000-8000-000000000095',repeat('a',64),'internal_receiver');
 IF NOT FOUND OR actor.expires_at-actor.created_at<>15000 OR actor.expires_at<>(created->>'expiresAt')::bigint
  OR actor.expires_at>client_now+15000
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_sessions s JOIN private.burimunsi_pin_session_links l ON l.native_session_id=s.id
   WHERE s.id=actor.native_session_id AND s.created_at=l.created_at AND s.created_at=actor.created_at)
  THEN RAISE EXCEPTION 'short TTL was expanded or unusable';END IF;
 -- Excessive skew and impossible lifetime must not mint a usable session.
 denied:=false;client_now:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+60000;
 BEGIN PERFORM private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fe900000-0000-4000-8000-000000000093','internal_receiver',encode(sha256(convert_to(repeat('6',64),'UTF8')),'hex'),
  1,gen_random_uuid(),encode(sha256(convert_to(repeat('5',64),'UTF8')),'hex'),client_now,client_now+1800000,1);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'excessive skew accepted';END IF;
 denied:=false;client_now:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+4000;
 BEGIN PERFORM private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fe900000-0000-4000-8000-000000000094','internal_receiver',encode(sha256(convert_to(repeat('8',64),'UTF8')),'hex'),
  1,gen_random_uuid(),encode(sha256(convert_to(repeat('7',64),'UTF8')),'hex'),client_now,client_now-1,1);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'negative lifetime accepted';END IF;
 denied:=false;client_now:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+4000;
 BEGIN PERFORM private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fe900000-0000-4000-8000-000000000096','internal_receiver',encode(sha256(convert_to(repeat('c',64),'UTF8')),'hex'),
  1,gen_random_uuid(),encode(sha256(convert_to(repeat('d',64),'UTF8')),'hex'),client_now,client_now+28800001,1);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'maximum TTL exceeded';END IF;
END;$contract$;
ROLLBACK;
