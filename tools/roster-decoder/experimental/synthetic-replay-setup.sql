-- SYNTHETIC PROTOTYPE ONLY. Apply solely to an isolated scratch PostgreSQL.
-- No production role, schema or live record is created by this fixture.
CREATE TABLE private.synthetic_roster_replays(
 nonce uuid PRIMARY KEY,request_id uuid NOT NULL,reservation_id uuid NOT NULL,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 decoder_sha256 text NOT NULL CHECK(decoder_sha256 ~ '^[a-f0-9]{64}$'),issued_at bigint NOT NULL,
 UNIQUE(request_id,reservation_id));
REVOKE ALL ON private.synthetic_roster_replays FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE FUNCTION private.synthetic_roster_claim(p_nonce uuid,p_request uuid,p_reservation uuid,p_source text,p_build text,p_issued bigint)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE n bigint;affected integer;
BEGIN
 IF p_nonce IS NULL OR p_request IS NULL OR p_reservation IS NULL OR p_source IS NULL OR p_build IS NULL OR p_source !~ '^[a-f0-9]{64}$' OR p_build !~ '^[a-f0-9]{64}$'
  OR p_issued IS NULL OR abs(extract(epoch FROM clock_timestamp())::bigint-p_issued)>30 THEN RETURN false;END IF;
 PERFORM pg_advisory_xact_lock(7346372,2);
 SELECT count(*) INTO n FROM private.burimunsi_command_receipts c
  WHERE c.operation='burimunsi.smart_import.v1' AND c.request_id=p_request
   AND c.response->>'reservationId'=p_reservation::text AND c.response->>'sourceSha256'=p_source
   AND c.response->>'decoderBuildSha256'=p_build AND c.response->>'state'='decode';
 IF n<>1 OR (SELECT count(*) FROM private.synthetic_roster_replays)>=5000 THEN RETURN false;END IF;
 INSERT INTO private.synthetic_roster_replays(nonce,request_id,reservation_id,source_sha256,decoder_sha256,issued_at)
 VALUES(p_nonce,p_request,p_reservation,p_source,p_build,p_issued) ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS affected=ROW_COUNT;RETURN affected=1;
END;$fn$;
REVOKE ALL ON FUNCTION private.synthetic_roster_claim(uuid,uuid,uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
