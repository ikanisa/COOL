-- Generated from the exact source bodies in source_manifest.json. Do not hand-edit.
BEGIN;
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS api;
REVOKE ALL ON SCHEMA app,private,api FROM PUBLIC;
SET LOCAL search_path=app,pg_catalog;
-- Narrow SQLite compatibility required by the retained domain contracts.
-- JSON remains TEXT during the behavior-preserving migration; no implicit
-- frontend access is granted to app or private.
CREATE FUNCTION app.unixepoch() RETURNS bigint LANGUAGE sql STABLE AS $$SELECT floor(extract(epoch FROM transaction_timestamp()))::bigint$$;
CREATE FUNCTION app.unixepoch(value text) RETURNS bigint LANGUAGE sql STABLE AS $$SELECT floor(extract(epoch FROM CASE WHEN value='now' THEN transaction_timestamp() ELSE value::timestamptz END))::bigint$$;
CREATE FUNCTION app.julianday(value text) RETURNS numeric LANGUAGE sql STABLE AS $$SELECT extract(epoch FROM CASE WHEN value='now' THEN transaction_timestamp() ELSE value::timestamptz END)/86400+2440587.5$$;
CREATE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN PERFORM value::jsonb; RETURN true; EXCEPTION WHEN invalid_text_representation THEN RETURN false; END$$;
CREATE FUNCTION app.json_path(value text) RETURNS text[] LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE result text[]:=ARRAY[]::text[];position integer:=2;started integer;character text;part text;closed boolean;
BEGIN
 IF left(value,1)<>'$' THEN RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
 WHILE position<=length(value) LOOP
  character:=substr(value,position,1);
  IF character='.' THEN
   position:=position+1;started:=position;
   IF substr(value,position,1)='"' THEN
    position:=position+1;closed:=false;
    WHILE position<=length(value) LOOP
     IF substr(value,position,1)=chr(92) THEN position:=position+2;
     ELSIF substr(value,position,1)='"' THEN position:=position+1;closed:=true;EXIT;
     ELSE position:=position+1;END IF;
    END LOOP;
    IF NOT closed THEN RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
    part:=substr(value,started,position-started)::jsonb #>> '{}';
   ELSE
    WHILE position<=length(value) AND substr(value,position,1) NOT IN('.','[') LOOP position:=position+1;END LOOP;
    part:=substr(value,started,position-started);
    IF part='' OR position>length(value)+1 THEN RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
   END IF;
  ELSIF character='[' THEN
   position:=position+1;started:=position;
   WHILE position<=length(value) AND substr(value,position,1)~'^[0-9]$' LOOP position:=position+1;END LOOP;
   part:=substr(value,started,position-started);
   IF part='' OR substr(value,position,1)<>']' THEN RAISE EXCEPTION 'unsupported_json_path' USING ERRCODE='22023';END IF;
   position:=position+1;
  ELSE RAISE EXCEPTION 'invalid_json_path' USING ERRCODE='22023';END IF;
  result:=array_append(result,part);
 END LOOP;
 RETURN result;
END$$;
CREATE FUNCTION app.json_extract(document text, path text) RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE jsonb_typeof(document::jsonb #> app.json_path(path)) WHEN 'null' THEN NULL WHEN 'boolean' THEN CASE WHEN document::jsonb #>> app.json_path(path)='true' THEN '1' ELSE '0' END ELSE document::jsonb #>> app.json_path(path) END$$;
-- SQLite compares nonnumeric JSON TEXT above every numeric storage class.
-- PostgreSQL numeric NaN has the same ordering versus finite numeric literals.
CREATE FUNCTION app.json_numeric(document text,path text) RETURNS numeric LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE jsonb_typeof(document::jsonb #> app.json_path(path)) WHEN 'number' THEN (document::jsonb #>> app.json_path(path))::numeric WHEN 'boolean' THEN CASE WHEN document::jsonb #>> app.json_path(path)='true' THEN 1 ELSE 0 END WHEN 'null' THEN NULL ELSE CASE WHEN document::jsonb #> app.json_path(path) IS NULL THEN NULL ELSE 'NaN'::numeric END END$$;
CREATE FUNCTION app.json_type(document text, path text DEFAULT '$') RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE jsonb_typeof(document::jsonb #> app.json_path(path)) WHEN 'string' THEN 'text' WHEN 'number' THEN CASE WHEN (document::jsonb #>> app.json_path(path)) ~ '^-?[0-9]+$' THEN 'integer' ELSE 'real' END WHEN 'boolean' THEN document::jsonb #>> app.json_path(path) ELSE jsonb_typeof(document::jsonb #> app.json_path(path)) END$$;
CREATE FUNCTION app.json_array_length(document text, path text DEFAULT '$') RETURNS bigint LANGUAGE sql IMMUTABLE STRICT AS $$SELECT CASE WHEN document::jsonb #> app.json_path(path) IS NULL THEN NULL WHEN jsonb_typeof(document::jsonb #> app.json_path(path))='array' THEN jsonb_array_length(document::jsonb #> app.json_path(path)) ELSE 0 END::bigint$$;
CREATE FUNCTION app.json_each(document text, path text DEFAULT '$') RETURNS TABLE(key text,value text,type text) LANGUAGE sql IMMUTABLE STRICT AS $$
 WITH selected AS (SELECT document::jsonb #> app.json_path(path) AS body), elements AS (
 SELECT e.key,e.value FROM selected CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(body)='object' THEN body ELSE '{}'::jsonb END) e
 UNION ALL SELECT (e.ordinality-1)::text,e.value FROM selected CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(body)='array' THEN body ELSE '[]'::jsonb END) WITH ORDINALITY e(value,ordinality))
 SELECT key,CASE jsonb_typeof(value) WHEN 'string' THEN value #>> '{}' WHEN 'null' THEN NULL WHEN 'boolean' THEN CASE WHEN value='true'::jsonb THEN '1' ELSE '0' END ELSE value::text END,CASE jsonb_typeof(value) WHEN 'string' THEN 'text' ELSE jsonb_typeof(value) END FROM elements
$$;
CREATE FUNCTION app.strftime(pattern text,value text DEFAULT 'now',modifier text DEFAULT NULL) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE stamp timestamptz; translated text;
BEGIN
 stamp:=CASE WHEN value='now' THEN transaction_timestamp() ELSE value::timestamptz END;
 IF modifier IS NOT NULL THEN
  IF modifier !~ '^-?[0-9]+ (second|seconds|minute|minutes|hour|hours|day|days)$' THEN RAISE EXCEPTION 'unsupported_datetime_modifier'; END IF;
  stamp:=stamp+modifier::interval;
 END IF;
 IF pattern='%s' THEN RETURN floor(extract(epoch FROM stamp))::bigint::text; END IF;
 IF pattern='%Y-%m-%dT%H:%M:%fZ' THEN translated:='YYYY-MM-DD"T"HH24:MI:SS.MS"Z"';
 ELSIF pattern='%Y-%m-%dT%H:%M:%SZ' THEN translated:='YYYY-MM-DD"T"HH24:MI:SS"Z"';
 ELSIF pattern='%Y-%m-%d' THEN translated:='YYYY-MM-DD';
 ELSE RAISE EXCEPTION 'unsupported_datetime_format'; END IF;
 RETURN to_char(stamp AT TIME ZONE 'UTC',translated);
END$$;
CREATE FUNCTION app.printf(pattern text,value bigint) RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN IF pattern='%06d' THEN RETURN lpad(value::text,6,'0'); END IF; RAISE EXCEPTION 'unsupported_printf_format'; END$$;
CREATE FUNCTION app.changes() RETURNS bigint LANGUAGE sql STABLE AS $$SELECT coalesce(nullif(current_setting('collect.last_changes',true),''),'0')::bigint$$;
CREATE TABLE users ( id TEXT PRIMARY KEY , phone TEXT UNIQUE , email TEXT UNIQUE , full_name TEXT NOT NULL DEFAULT '' , public_id TEXT NOT NULL UNIQUE , country_code TEXT NOT NULL DEFAULT 'RW' , currency_code TEXT NOT NULL DEFAULT 'RWF' , momo_provider TEXT NOT NULL DEFAULT '' , momo_number TEXT NOT NULL DEFAULT '' , momo_pay_code TEXT NOT NULL DEFAULT '' , access_status TEXT NOT NULL DEFAULT 'active' CHECK ( access_status IN ( 'active' , 'suspended' , 'deleted' ) ) , created_at TEXT NOT NULL , updated_at TEXT NOT NULL , member_type TEXT NOT NULL DEFAULT 'app' CHECK ( member_type IN ( 'app' , 'direct' , 'operator' ) ) , revision BIGINT NOT NULL DEFAULT 1 CHECK ( revision >= 1 ) );
CREATE TABLE admin_grants ( user_id TEXT NOT NULL , permission TEXT NOT NULL , granted_by TEXT , granted_at TEXT NOT NULL , PRIMARY KEY ( user_id , permission ) );
CREATE TABLE admin_role_assignments ( user_id TEXT NOT NULL , role TEXT NOT NULL CHECK ( role IN ( 'platform_owner' , 'operator' , 'reviewer' , 'auditor' ) ) , granted_by TEXT , granted_at TEXT NOT NULL , PRIMARY KEY ( user_id , role ) );
CREATE TABLE collections ( id TEXT PRIMARY KEY , slug TEXT NOT NULL UNIQUE , creator_user_id TEXT NOT NULL , title TEXT NOT NULL , description TEXT NOT NULL DEFAULT '' , collection_type TEXT NOT NULL , country_code TEXT NOT NULL DEFAULT 'RW' CHECK ( country_code = 'RW' ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , status TEXT NOT NULL DEFAULT 'active' CHECK ( status IN ( 'active' , 'archived' , 'suspended' ) ) , visibility_status TEXT NOT NULL DEFAULT 'private' CHECK ( visibility_status IN ( 'private' , 'public_pending' , 'public_approved' ) ) , is_platform_sponsored BIGINT NOT NULL DEFAULT 0 CHECK ( is_platform_sponsored IN ( 0 , 1 ) ) , receiver_momo_number TEXT , receiver_network TEXT , receiver_display_label TEXT , share_code_hash TEXT UNIQUE , share_code_ciphertext TEXT , share_code_version BIGINT NOT NULL DEFAULT 1 , revision BIGINT NOT NULL DEFAULT 1 , data_json TEXT NOT NULL DEFAULT '{}' CHECK ( json_valid ( data_json ) ) , created_at TEXT NOT NULL , updated_at TEXT NOT NULL );
CREATE TABLE memberships ( id TEXT PRIMARY KEY , collection_id TEXT NOT NULL , user_id TEXT NOT NULL , role TEXT NOT NULL DEFAULT 'member' CHECK ( role IN ( 'owner' , 'admin' , 'member' ) ) , active BIGINT NOT NULL DEFAULT 1 CHECK ( active IN ( 0 , 1 ) ) , joined_at TEXT NOT NULL , revision BIGINT NOT NULL DEFAULT 1 CHECK ( revision >= 1 ) , UNIQUE ( collection_id , user_id ) );
CREATE TABLE payment_intents ( id TEXT PRIMARY KEY , collection_id TEXT NOT NULL , member_id TEXT NOT NULL , amount_minor BIGINT NOT NULL CHECK ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK ( rail = 'rwanda_momo' ) , status TEXT NOT NULL DEFAULT 'pending' CHECK ( status IN ( 'pending' , 'expired' , 'cancelled' , 'matched' , 'ambiguous' ) ) , receiver_momo_number TEXT NOT NULL , receiver_network TEXT NOT NULL , receiver_label TEXT NOT NULL DEFAULT '' , originating_session_id TEXT NOT NULL , created_at TEXT NOT NULL , expires_at TEXT NOT NULL , request_id TEXT NOT NULL , request_sha256 TEXT NOT NULL , UNIQUE ( member_id , request_id ) );
CREATE TABLE payment_evidence ( id TEXT PRIMARY KEY , collection_id TEXT , owner_user_id TEXT NOT NULL , object_key TEXT NOT NULL UNIQUE , object_sha256 TEXT NOT NULL CHECK ( length ( object_sha256 ) = 64 ) , size_bytes BIGINT NOT NULL CHECK ( size_bytes > 0 ) , content_type TEXT NOT NULL , authenticity TEXT NOT NULL CHECK ( authenticity IN ( 'operator_recorded' , 'provider_authenticated' ) ) , external_reference TEXT , receiver_momo_number TEXT , amount_minor BIGINT CHECK ( amount_minor IS NULL OR ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , observed_at TEXT NOT NULL , created_at TEXT NOT NULL , retained_until TEXT , legal_hold BIGINT NOT NULL DEFAULT 0 CHECK ( legal_hold IN ( 0 , 1 ) ) , receiver_network TEXT , receiver_display_label TEXT , UNIQUE ( owner_user_id , external_reference ) );
CREATE TABLE payments ( id TEXT PRIMARY KEY , collection_id TEXT NOT NULL , member_id TEXT , evidence_id TEXT NOT NULL , intent_id TEXT , amount_minor BIGINT NOT NULL CHECK ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK ( rail = 'rwanda_momo' ) , status TEXT NOT NULL CHECK ( status IN ( 'recorded' , 'reconciled' , 'confirmed' , 'corrected' , 'reversed' , 'ambiguous' ) ) , payer_display_name TEXT NOT NULL DEFAULT '' , created_at TEXT NOT NULL , revision BIGINT NOT NULL DEFAULT 1 , UNIQUE ( evidence_id ) );
CREATE TABLE ledger_entries ( id TEXT PRIMARY KEY , payment_id TEXT NOT NULL , collection_id TEXT NOT NULL , member_id TEXT , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , amount_minor BIGINT NOT NULL CHECK ( amount_minor != 0 AND abs ( amount_minor ) <= 9007199254740991 ) , kind TEXT NOT NULL CHECK ( kind IN ( 'contribution' , 'reversal' , 'correction' ) ) , reverses_entry_id TEXT UNIQUE , evidence_id TEXT NOT NULL , actor_user_id TEXT NOT NULL , request_id TEXT NOT NULL UNIQUE , posted_at TEXT NOT NULL , CHECK ( ( kind = 'contribution' AND amount_minor > 0 AND reverses_entry_id IS NULL ) OR ( kind != 'contribution' AND reverses_entry_id IS NOT NULL ) ) );
CREATE TABLE reconciliations ( id TEXT PRIMARY KEY , payment_id TEXT NOT NULL , proposed_member_id TEXT NOT NULL , proposed_by TEXT NOT NULL , proposed_session_id TEXT NOT NULL , expected_payment_revision BIGINT NOT NULL , status TEXT NOT NULL CHECK ( status IN ( 'proposed' , 'approved' , 'rejected' , 'cancelled' ) ) , evidence_id TEXT NOT NULL , approved_by TEXT , request_id TEXT NOT NULL UNIQUE , request_sha256 TEXT NOT NULL , created_at TEXT NOT NULL , approved_at TEXT );
CREATE TABLE notification_preferences ( user_id TEXT PRIMARY KEY , push_enabled BIGINT NOT NULL DEFAULT 1 , payment_updates BIGINT NOT NULL DEFAULT 1 , group_updates BIGINT NOT NULL DEFAULT 1 , revision BIGINT NOT NULL DEFAULT 1 , updated_at TEXT NOT NULL );
CREATE TABLE notification_devices ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , token_hash TEXT NOT NULL UNIQUE , owner_session_id TEXT NOT NULL , provider TEXT NOT NULL , token_ciphertext TEXT NOT NULL , platform TEXT NOT NULL CHECK ( platform IN ( 'android' , 'ios' , 'web' ) ) , active BIGINT NOT NULL DEFAULT 1 , created_at TEXT NOT NULL , updated_at TEXT NOT NULL );
CREATE TABLE notification_events ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , event_type TEXT NOT NULL , title TEXT NOT NULL , body TEXT NOT NULL , data_json TEXT NOT NULL DEFAULT '{}' CHECK ( json_valid ( data_json ) ) , status TEXT NOT NULL DEFAULT 'pending' CHECK ( status IN ( 'pending' , 'sent' , 'failed' , 'read' ) ) , created_at TEXT NOT NULL , read_at TEXT );
CREATE TABLE support_requests ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , collection_id TEXT , kind TEXT NOT NULL , message TEXT NOT NULL , status TEXT NOT NULL DEFAULT 'received' , created_at TEXT NOT NULL );
CREATE TABLE runtime_config ( key TEXT PRIMARY KEY , value_json TEXT NOT NULL CHECK ( json_valid ( value_json ) ) , revision BIGINT NOT NULL DEFAULT 1 , updated_by TEXT , updated_at TEXT NOT NULL );
CREATE TABLE audit_log ( id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY , actor_user_id TEXT , actor_session_id TEXT , action TEXT NOT NULL , entity_type TEXT NOT NULL , entity_id TEXT , request_id TEXT , details_json TEXT NOT NULL CHECK ( json_valid ( details_json ) ) , created_at TEXT NOT NULL );
CREATE TABLE request_receipts ( user_id TEXT NOT NULL , request_id TEXT NOT NULL , operation TEXT NOT NULL , session_id TEXT NOT NULL , body_sha256 TEXT NOT NULL CHECK ( length ( body_sha256 ) = 64 ) , response_json TEXT NOT NULL CHECK ( json_valid ( response_json ) ) , created_at TEXT NOT NULL , PRIMARY KEY ( user_id , request_id ) );
CREATE TABLE deletion_requests ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , submission_id TEXT NOT NULL , reason TEXT , status TEXT NOT NULL DEFAULT 'received' CHECK ( status IN ( 'received' , 'under_review' , 'scheduled' , 'erasing' , 'completed' , 'rejected' , 'on_hold' , 'failed' ) ) , revision BIGINT NOT NULL DEFAULT 1 , created_at TEXT NOT NULL , updated_at TEXT NOT NULL , UNIQUE ( user_id , submission_id ) );
CREATE TABLE deletion_reviews ( id TEXT PRIMARY KEY , request_id TEXT NOT NULL , actor_user_id TEXT NOT NULL , expected_revision BIGINT NOT NULL , outcome TEXT NOT NULL , details_json TEXT NOT NULL CHECK ( json_valid ( details_json ) ) , created_at TEXT NOT NULL );
CREATE TABLE privacy_holds ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , category TEXT NOT NULL , reason_code TEXT NOT NULL , active BIGINT NOT NULL DEFAULT 1 , created_at TEXT NOT NULL , released_at TEXT );
CREATE TABLE upload_objects ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , collection_id TEXT , object_key TEXT NOT NULL UNIQUE , sha256 TEXT NOT NULL , size_bytes BIGINT NOT NULL , content_type TEXT NOT NULL , purpose TEXT NOT NULL , status TEXT NOT NULL DEFAULT 'retained' , created_at TEXT NOT NULL , deleted_at TEXT );
CREATE TABLE auth_otp_challenges ( id TEXT PRIMARY KEY , identity_hash TEXT NOT NULL CHECK ( length ( identity_hash ) = 64 ) , identity_type TEXT NOT NULL CHECK ( identity_type IN ( 'phone' , 'email' ) ) , identity_value TEXT NOT NULL , surface TEXT NOT NULL CHECK ( surface IN ( 'member' , 'admin' ) ) , registration_allowed BIGINT NOT NULL CHECK ( registration_allowed IN ( 0 , 1 ) ) , code_hash TEXT NOT NULL CHECK ( length ( code_hash ) = 64 ) , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , attempts BIGINT NOT NULL DEFAULT 0 CHECK ( attempts BETWEEN 0 AND 5 ) , status TEXT NOT NULL CHECK ( status IN ( 'dispatching' , 'accepted' , 'delivery_unknown' , 'superseded' , 'consumed' ) ) , consumed_at BIGINT , consumed_operation_id TEXT UNIQUE , identity_key_id TEXT NOT NULL DEFAULT 'legacy-token-hash-v1' CHECK ( length ( identity_key_id ) BETWEEN 1 AND 128 AND ( substr ( identity_key_id , 1 , 1 ) ~ '^[A-Za-z0-9]$' ) AND ( identity_key_id !~ '^.*[^A-Za-z0-9._:-].*$' ) ) , CHECK ( ( status = 'consumed' AND consumed_at IS NOT NULL AND consumed_operation_id IS NOT NULL ) OR ( status != 'consumed' AND consumed_at IS NULL AND consumed_operation_id IS NULL ) ) );
CREATE TABLE auth_rate_buckets ( bucket_key TEXT PRIMARY KEY , used BIGINT NOT NULL CHECK ( used >= 0 ) , window_ends_at BIGINT NOT NULL );
CREATE TABLE auth_otp_throttles ( identity_hash TEXT PRIMARY KEY , last_requested_at BIGINT NOT NULL , identity_key_id TEXT NOT NULL DEFAULT 'legacy-token-hash-v1' CHECK ( length ( identity_key_id ) BETWEEN 1 AND 128 AND ( substr ( identity_key_id , 1 , 1 ) ~ '^[A-Za-z0-9]$' ) AND ( identity_key_id !~ '^.*[^A-Za-z0-9._:-].*$' ) ) );
CREATE TABLE auth_rate_claims ( request_id TEXT PRIMARY KEY , identity_hash TEXT NOT NULL , identity_bucket TEXT NOT NULL , ip_bucket TEXT NOT NULL , global_bucket TEXT NOT NULL , requested_at BIGINT NOT NULL , hourly_window_ends_at BIGINT NOT NULL , daily_window_ends_at BIGINT NOT NULL , identity_limit BIGINT NOT NULL CHECK ( identity_limit BETWEEN 1 AND 100 ) , ip_limit BIGINT NOT NULL CHECK ( ip_limit BETWEEN 1 AND 1000 ) , global_limit BIGINT NOT NULL CHECK ( global_limit BETWEEN 1 AND 100000 ) , cooldown_seconds BIGINT NOT NULL CHECK ( cooldown_seconds BETWEEN 60 AND 3600 ) , identity_key_id TEXT NOT NULL DEFAULT 'legacy-token-hash-v1' CHECK ( length ( identity_key_id ) BETWEEN 1 AND 128 AND ( substr ( identity_key_id , 1 , 1 ) ~ '^[A-Za-z0-9]$' ) AND ( identity_key_id !~ '^.*[^A-Za-z0-9._:-].*$' ) ) , identity_aliases_json TEXT NOT NULL DEFAULT '[]' CHECK ( json_valid ( identity_aliases_json ) AND json_type ( identity_aliases_json ) = 'array' ) );
CREATE TABLE auth_sessions ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , surface TEXT NOT NULL CHECK ( surface IN ( 'member' , 'admin' ) ) , auth_at BIGINT NOT NULL , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , revoked_at BIGINT , revocation_reason TEXT , assurance_level BIGINT NOT NULL DEFAULT 1 CHECK ( assurance_level IN ( 1 , 2 ) ) , mfa_at BIGINT , mfa_factor_id TEXT , CHECK ( ( assurance_level = 1 AND mfa_at IS NULL AND mfa_factor_id IS NULL ) OR ( assurance_level = 2 AND mfa_at >= auth_at AND mfa_factor_id IS NOT NULL ) ) , CHECK ( ( revoked_at IS NULL AND revocation_reason IS NULL ) OR ( revoked_at IS NOT NULL AND revocation_reason IS NOT NULL ) ) );
CREATE TABLE auth_mfa_factors ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , friendly_name TEXT NOT NULL , secret_ciphertext TEXT NOT NULL CHECK ( json_valid ( secret_ciphertext ) ) , status TEXT NOT NULL CHECK ( status IN ( 'pending' , 'verified' , 'revoked' ) ) , created_at BIGINT NOT NULL , enrollment_session_id TEXT NOT NULL , verified_at BIGINT , last_totp_counter BIGINT CHECK ( last_totp_counter >= 0 ) , revoked_at BIGINT , CHECK ( ( status = 'pending' AND verified_at IS NULL AND last_totp_counter IS NULL AND revoked_at IS NULL ) OR ( status = 'verified' AND verified_at IS NOT NULL AND last_totp_counter IS NOT NULL AND revoked_at IS NULL ) OR ( status = 'revoked' AND revoked_at IS NOT NULL ) ) );
CREATE TABLE auth_mfa_challenges ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , session_id TEXT NOT NULL , factor_id TEXT NOT NULL , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , attempts BIGINT NOT NULL DEFAULT 0 CHECK ( attempts BETWEEN 0 AND 5 ) , consumed_at BIGINT , consumed_operation_id TEXT UNIQUE , CHECK ( ( consumed_at IS NULL AND consumed_operation_id IS NULL ) OR ( consumed_at IS NOT NULL AND consumed_operation_id IS NOT NULL ) ) );
CREATE TABLE auth_mfa_budgets ( user_id TEXT NOT NULL , window_start BIGINT NOT NULL , kind TEXT NOT NULL CHECK ( kind IN ( 'challenge' , 'verification' ) ) , used BIGINT NOT NULL CHECK ( used >= 1 AND used <= 10 ) , PRIMARY KEY ( user_id , window_start , kind ) );
CREATE TABLE auth_mfa_claims ( operation_id TEXT PRIMARY KEY , challenge_id TEXT NOT NULL UNIQUE , factor_id TEXT NOT NULL , user_id TEXT NOT NULL , session_id TEXT NOT NULL , totp_counter BIGINT NOT NULL CHECK ( totp_counter >= 0 ) , verified_at BIGINT NOT NULL , UNIQUE ( factor_id , totp_counter ) );
CREATE TABLE auth_mfa_revocations ( operation_id TEXT PRIMARY KEY , factor_id TEXT NOT NULL UNIQUE , user_id TEXT NOT NULL , session_id TEXT NOT NULL , revoked_at BIGINT NOT NULL );
CREATE TABLE auth_refresh_tokens ( token_hash TEXT PRIMARY KEY CHECK ( length ( token_hash ) = 64 ) , session_id TEXT NOT NULL , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , used_at BIGINT , replaced_by_hash TEXT , CHECK ( ( used_at IS NULL AND replaced_by_hash IS NULL ) OR ( used_at IS NOT NULL AND length ( replaced_by_hash ) = 64 ) ) );
CREATE TABLE auth_otp_verifications ( operation_id TEXT PRIMARY KEY , challenge_id TEXT NOT NULL UNIQUE , user_id TEXT NOT NULL , session_id TEXT NOT NULL UNIQUE , verified_at BIGINT NOT NULL );
CREATE TABLE mutation_guards ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , session_id TEXT NOT NULL , now_seconds BIGINT NOT NULL , collection_id TEXT , required_group_role TEXT , permission TEXT , fresh_seconds BIGINT , expected_collection_revision BIGINT , payment_id TEXT , expected_payment_revision BIGINT , minimum_assurance BIGINT , expected_mfa_at BIGINT , expected_preference_revision BIGINT , invite_collection_id TEXT , expected_share_hash TEXT , expected_share_version BIGINT , recipient_user_id TEXT , recipient_collection_id TEXT , target_collection_id TEXT , expected_target_collection_revision BIGINT );
CREATE TABLE privacy_submissions ( submission_id TEXT PRIMARY KEY , request_id TEXT NOT NULL , user_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , input_sha256 TEXT NOT NULL CHECK ( length ( input_sha256 ) = 64 ) , created_at TEXT NOT NULL );
CREATE TABLE privacy_review_heads ( request_id TEXT PRIMARY KEY , revision BIGINT NOT NULL DEFAULT 0 CHECK ( revision BETWEEN 0 AND 1000000000 ) , fence BIGINT NOT NULL DEFAULT 0 CHECK ( fence BETWEEN 0 AND 1000000000 ) , state TEXT NOT NULL DEFAULT 'awaiting_review' CHECK ( state IN ( 'awaiting_review' , 'claim_active' , 'blocked' ) ) , latest_claim_id TEXT , last_outcome_id TEXT , created_at TEXT NOT NULL , updated_at TEXT NOT NULL , CHECK ( ( state = 'awaiting_review' AND revision = 0 AND fence = 0 AND latest_claim_id IS NULL AND last_outcome_id IS NULL ) OR ( state = 'claim_active' AND revision > 0 AND fence > 0 AND latest_claim_id IS NOT NULL AND last_outcome_id IS NULL ) OR ( state = 'blocked' AND revision >= 2 AND fence > 0 AND latest_claim_id IS NOT NULL AND last_outcome_id IS NOT NULL ) ) );
CREATE TABLE privacy_review_claims ( claim_id TEXT PRIMARY KEY , claim_request_id TEXT NOT NULL UNIQUE , request_id TEXT NOT NULL , actor_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , expected_revision BIGINT NOT NULL CHECK ( expected_revision BETWEEN 0 AND 999999998 ) , revision BIGINT NOT NULL CHECK ( revision = expected_revision + 1 ) , fence BIGINT NOT NULL CHECK ( fence BETWEEN 1 AND 1000000000 ) , lease_seconds BIGINT NOT NULL CHECK ( lease_seconds BETWEEN 1 AND 120 ) , claimed_at TEXT NOT NULL , expires_at TEXT NOT NULL CHECK ( expires_at > claimed_at ) );
CREATE TABLE privacy_review_outcomes ( outcome_request_id TEXT PRIMARY KEY , request_id TEXT NOT NULL , claim_id TEXT NOT NULL UNIQUE , actor_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , fence BIGINT NOT NULL CHECK ( fence > 0 ) , revision BIGINT NOT NULL CHECK ( revision BETWEEN 2 AND 1000000000 ) , outcome_code TEXT NOT NULL CHECK ( outcome_code = 'policy_authority_unavailable' ) , recorded_at TEXT NOT NULL );
CREATE TABLE native_consents ( id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY , user_id TEXT NOT NULL , session_id TEXT NOT NULL , receiver_hash TEXT NOT NULL CHECK ( length ( receiver_hash ) = 64 ) , enabled BIGINT NOT NULL CHECK ( enabled IN ( 0 , 1 ) ) , created_seconds BIGINT NOT NULL , build_channel TEXT NOT NULL , request_id TEXT NOT NULL UNIQUE );
CREATE TABLE native_reservations ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , session_id TEXT NOT NULL , nonce TEXT NOT NULL , action TEXT NOT NULL CHECK ( action IN ( 'group.create' , 'sms.ingest' ) ) , request_hash TEXT NOT NULL CHECK ( length ( request_hash ) = 64 ) , token_sha256 TEXT NOT NULL UNIQUE CHECK ( length ( token_sha256 ) = 64 ) , receiver_hash TEXT NOT NULL CHECK ( length ( receiver_hash ) = 64 ) , verified_phone TEXT NOT NULL , payload_sha256 TEXT NOT NULL CHECK ( length ( payload_sha256 ) = 64 ) , payload_ciphertext TEXT NOT NULL , policy_sha256 TEXT NOT NULL CHECK ( length ( policy_sha256 ) = 64 ) , approval_id TEXT NOT NULL , approval_evidence_sha256 TEXT NOT NULL , project_id TEXT NOT NULL , created_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL , actor_hour_limit BIGINT NOT NULL CHECK ( actor_hour_limit BETWEEN 1 AND 100 ) , project_day_limit BIGINT NOT NULL CHECK ( project_day_limit BETWEEN 1 AND 10000 ) , state TEXT NOT NULL DEFAULT 'reserved' CHECK ( state IN ( 'reserved' , 'oauth_started' , 'decode_started' , 'completed' , 'rejected' , 'ambiguous' ) ) , UNIQUE ( user_id , nonce ) );
CREATE TABLE native_phases ( reservation_id TEXT NOT NULL , phase TEXT NOT NULL CHECK ( phase IN ( 'oauth' , 'decode' ) ) , started_seconds BIGINT NOT NULL , PRIMARY KEY ( reservation_id , phase ) );
CREATE TABLE native_capabilities ( id TEXT PRIMARY KEY , token_sha256 TEXT NOT NULL UNIQUE CHECK ( length ( token_sha256 ) = 64 ) , reservation_id TEXT NOT NULL UNIQUE , user_id TEXT NOT NULL , session_id TEXT NOT NULL , action TEXT NOT NULL , receiver_hash TEXT NOT NULL , verified_phone TEXT NOT NULL , payload_sha256 TEXT NOT NULL , created_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL CHECK ( expires_seconds > created_seconds AND expires_seconds <= created_seconds + 180 ) , verdict_sha256 TEXT NOT NULL CHECK ( length ( verdict_sha256 ) = 64 ) );
CREATE TABLE native_completions ( reservation_id TEXT PRIMARY KEY , capability_id TEXT NOT NULL UNIQUE , result_ciphertext TEXT NOT NULL , provider_response_sha256 TEXT NOT NULL , completed_seconds BIGINT NOT NULL , decode_duration_ms BIGINT NOT NULL CHECK ( decode_duration_ms BETWEEN 0 AND 20000 ) );
CREATE TABLE native_capability_claims ( id TEXT PRIMARY KEY , capability_id TEXT NOT NULL UNIQUE , user_id TEXT NOT NULL , session_id TEXT NOT NULL , action TEXT NOT NULL , payload_sha256 TEXT NOT NULL , receiver_hash TEXT NOT NULL , claimed_seconds BIGINT NOT NULL );
CREATE TABLE roster_imports ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , session_id TEXT NOT NULL , request_id TEXT NOT NULL , collection_id TEXT , request_sha256 TEXT NOT NULL , source_sha256 TEXT NOT NULL , object_sha256 TEXT NOT NULL , source_object_key TEXT NOT NULL UNIQUE , source_size BIGINT NOT NULL CHECK ( source_size BETWEEN 1 AND 5242880 ) , source_kind TEXT NOT NULL , source_receipt_json TEXT NOT NULL CHECK ( json_valid ( source_receipt_json ) ) , state TEXT NOT NULL CHECK ( state IN ( 'reserved' , 'retained' , 'processing' , 'preview_ready' , 'committed' , 'failed' , 'ambiguous' ) ) , latest_revision_id TEXT , source_ciphertext TEXT NOT NULL , created_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL , error_code TEXT , UNIQUE ( user_id , request_id ) );
CREATE TABLE roster_processing_records ( id TEXT PRIMARY KEY , import_id TEXT NOT NULL UNIQUE , actor_user_id TEXT NOT NULL , session_id TEXT NOT NULL , source_sha256 TEXT NOT NULL , source_object_sha256 TEXT NOT NULL , policy_sha256 TEXT NOT NULL , approval_id TEXT NOT NULL , approval_evidence_sha256 TEXT NOT NULL , processor_policy_json TEXT NOT NULL CHECK ( json_valid ( processor_policy_json ) ) , project_id TEXT NOT NULL , organization_id TEXT NOT NULL , provider TEXT NOT NULL , model TEXT NOT NULL , processing_region_evidence_ref TEXT NOT NULL , retention_evidence_ref TEXT NOT NULL , decoder_build_sha256 TEXT NOT NULL , decoder_lineage_json TEXT NOT NULL CHECK ( json_valid ( decoder_lineage_json ) ) , created_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL );
CREATE TABLE roster_dispatch_phases ( processing_id TEXT NOT NULL , phase TEXT NOT NULL CHECK ( phase IN ( 'decode' , 'extract' ) ) , started_seconds BIGINT NOT NULL , PRIMARY KEY ( processing_id , phase ) );
CREATE TABLE roster_revisions ( id TEXT PRIMARY KEY , import_id TEXT NOT NULL , request_id TEXT NOT NULL , parent_revision_id TEXT , revision_number BIGINT NOT NULL CHECK ( revision_number BETWEEN 1 AND 20 ) , rows_sha256 TEXT NOT NULL , preview_ciphertext TEXT NOT NULL , human_reviewed BIGINT NOT NULL CHECK ( human_reviewed IN ( 0 , 1 ) ) , review_reason TEXT , created_seconds BIGINT NOT NULL , UNIQUE ( import_id , request_id ) , UNIQUE ( import_id , revision_number ) );
CREATE TABLE roster_members ( id TEXT PRIMARY KEY , collection_id TEXT NOT NULL , source_import_id TEXT NOT NULL , source_revision_id TEXT NOT NULL , member_name TEXT NOT NULL , momo_name TEXT NOT NULL , momo_number TEXT NOT NULL , linked_user_id TEXT , created_at TEXT NOT NULL , UNIQUE ( collection_id , momo_number ) );
CREATE TABLE roster_commit_guards ( id TEXT PRIMARY KEY , import_id TEXT NOT NULL , revision_id TEXT , actor_user_id TEXT NOT NULL , session_id TEXT NOT NULL , now_seconds BIGINT NOT NULL , expected_state TEXT NOT NULL , expected_latest_revision TEXT , permission TEXT NOT NULL DEFAULT 'roster.import' , collection_id TEXT , expected_collection_revision BIGINT );
CREATE TABLE roster_intents ( id TEXT PRIMARY KEY , import_id TEXT NOT NULL , user_id TEXT NOT NULL , session_id TEXT NOT NULL , kind TEXT NOT NULL CHECK ( kind IN ( 'review' , 'commit' ) ) , request_id TEXT NOT NULL , body_sha256 TEXT NOT NULL , payload_ciphertext TEXT NOT NULL , created_seconds BIGINT NOT NULL , UNIQUE ( import_id , request_id ) );
CREATE TABLE admin_users ( id TEXT PRIMARY KEY , email TEXT NOT NULL UNIQUE  , role TEXT NOT NULL CHECK ( role IN ( 'owner' , 'admin' , 'staff' ) ) , status TEXT NOT NULL CHECK ( status IN ( 'invited' , 'active' , 'revoked' ) ) , display_name TEXT NOT NULL DEFAULT '' , password_hash TEXT , auth_version BIGINT NOT NULL DEFAULT 1 CHECK ( auth_version >= 1 ) , challenge_version BIGINT NOT NULL DEFAULT 0 CHECK ( challenge_version >= 0 ) , created_at BIGINT NOT NULL , invited_at BIGINT , accepted_at BIGINT , updated_at BIGINT NOT NULL , CHECK ( ( role = 'owner' AND email = 'info@ikanisa.com' ) OR ( role != 'owner' AND email != 'info@ikanisa.com' ) ) , CHECK ( status != 'active' OR password_hash IS NOT NULL ) );
CREATE TABLE admin_sessions ( token_hash TEXT PRIMARY KEY CHECK ( length ( token_hash ) = 64 ) , public_id TEXT NOT NULL UNIQUE , user_id TEXT NOT NULL , auth_version BIGINT NOT NULL , auth_session_id TEXT NOT NULL UNIQUE , origin TEXT NOT NULL CHECK ( origin LIKE 'https://%' ) , issued_assurance_level BIGINT NOT NULL DEFAULT 1 CHECK ( issued_assurance_level IN ( 1 , 2 ) ) , issued_mfa_at BIGINT , issued_mfa_factor_id TEXT , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , CHECK ( ( issued_assurance_level = 1 AND issued_mfa_at IS NULL AND issued_mfa_factor_id IS NULL ) OR ( issued_assurance_level = 2 AND issued_mfa_at IS NOT NULL AND issued_mfa_factor_id IS NOT NULL ) ) );
CREATE TABLE admin_challenges ( token_hash TEXT PRIMARY KEY CHECK ( length ( token_hash ) = 64 ) , user_id TEXT NOT NULL , kind TEXT NOT NULL CHECK ( kind IN ( 'invite' , 'reset' ) ) , auth_version BIGINT NOT NULL , challenge_version BIGINT NOT NULL , delivery_status TEXT NOT NULL DEFAULT 'pending' CHECK ( delivery_status IN ( 'pending' , 'accepted' , 'failed' ) ) , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL , used_at BIGINT );
CREATE TABLE admin_email_events ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , kind TEXT NOT NULL , status TEXT NOT NULL CHECK ( status IN ( 'pending' , 'accepted' , 'failed' ) ) , provider_message_id TEXT , created_at BIGINT NOT NULL , updated_at BIGINT NOT NULL );
CREATE TABLE admin_rate_limits ( key_hash TEXT NOT NULL , bucket BIGINT NOT NULL , count BIGINT NOT NULL CHECK ( count >= 1 ) , expires_at BIGINT NOT NULL , PRIMARY KEY ( key_hash , bucket ) );
CREATE TABLE admin_account_audit ( id TEXT PRIMARY KEY , actor_id TEXT , subject_id TEXT , action TEXT NOT NULL , occurred_at BIGINT NOT NULL );
CREATE TABLE admin_principal_links ( admin_user_id TEXT PRIMARY KEY , user_id TEXT NOT NULL UNIQUE , approved_by TEXT NOT NULL , approved_at TEXT NOT NULL );
CREATE TABLE admin_account_role_capabilities ( role TEXT NOT NULL CHECK ( role IN ( 'owner' , 'admin' , 'staff' ) ) , permission TEXT NOT NULL , PRIMARY KEY ( role , permission ) );
CREATE TABLE admin_account_guards ( id TEXT PRIMARY KEY , passed BIGINT NOT NULL CONSTRAINT admin_account_authority CHECK ( passed = 1 ) );
CREATE TABLE admin_bridge_guards ( id TEXT PRIMARY KEY , passed BIGINT NOT NULL CONSTRAINT admin_bridge_state CHECK ( passed = 1 ) );
CREATE TABLE admin_bridge_requests ( admin_user_id TEXT NOT NULL , idempotency_key TEXT NOT NULL , request_id TEXT NOT NULL UNIQUE , session_id TEXT NOT NULL , operation TEXT NOT NULL , body_sha256 TEXT NOT NULL , created_at TEXT NOT NULL , PRIMARY KEY ( admin_user_id , idempotency_key ) );
CREATE TABLE admin_bridge_reconciliation_snapshots ( reconciliation_id TEXT PRIMARY KEY , collection_id TEXT NOT NULL , collection_revision BIGINT NOT NULL , member_id TEXT NOT NULL , member_revision BIGINT NOT NULL , membership_id TEXT NOT NULL , membership_revision BIGINT NOT NULL , payment_identity_json TEXT NOT NULL CHECK ( json_valid ( payment_identity_json ) ) , receiver_number TEXT , receiver_network TEXT , receiver_label TEXT , created_at TEXT NOT NULL );
CREATE TABLE admin_owner_bootstrap_claims ( operation_id TEXT PRIMARY KEY , admin_user_id TEXT NOT NULL UNIQUE , principal_user_id TEXT NOT NULL UNIQUE , password_hash TEXT NOT NULL , display_name TEXT NOT NULL , approval_reference TEXT NOT NULL , created_at TEXT NOT NULL , created_seconds BIGINT NOT NULL );
CREATE TABLE sms_receipts ( id TEXT PRIMARY KEY NOT NULL , owner_user_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , client_envelope_id TEXT NOT NULL , body_sha256 TEXT NOT NULL CHECK ( length ( body_sha256 ) = 64 ) , receiver_hash TEXT NOT NULL CHECK ( length ( receiver_hash ) = 64 ) , object_key TEXT NOT NULL UNIQUE , object_sha256 TEXT NOT NULL CHECK ( length ( object_sha256 ) = 64 ) , size_bytes BIGINT NOT NULL CHECK ( size_bytes BETWEEN 1 AND 131072 ) , received_at_device TEXT , status TEXT NOT NULL DEFAULT 'received' CHECK ( status IN ( 'received' , 'under_review' , 'rejected' , 'linked' ) ) , evidence_level TEXT NOT NULL DEFAULT 'client_received' CHECK ( evidence_level = 'client_received' ) , created_at TEXT NOT NULL , UNIQUE ( owner_user_id , client_envelope_id ) );
CREATE TABLE admin_operator_notes ( id TEXT PRIMARY KEY , entity_type TEXT NOT NULL CHECK ( entity_type IN ( 'collection' , 'profile' ) ) , entity_id TEXT NOT NULL , body_ciphertext TEXT NOT NULL , body_sha256 TEXT NOT NULL CHECK ( length ( body_sha256 ) = 64 ) , created_by TEXT NOT NULL , session_id TEXT NOT NULL , created_at TEXT NOT NULL );
CREATE TABLE privacy_retention_plans ( id TEXT PRIMARY KEY , operation_id TEXT NOT NULL UNIQUE , request_id TEXT NOT NULL , subject_id TEXT NOT NULL , actor_id TEXT NOT NULL , session_id TEXT NOT NULL , input_sha256 TEXT NOT NULL CHECK ( length ( input_sha256 ) = 64 ) , policy_sha256 TEXT NOT NULL CHECK ( length ( policy_sha256 ) = 64 ) , policy_json TEXT NOT NULL CHECK ( json_valid ( policy_json ) ) , policy_config_revision BIGINT NOT NULL , source_id TEXT NOT NULL CHECK ( length ( source_id ) = 64 ) , schema_sha256 TEXT NOT NULL CHECK ( length ( schema_sha256 ) = 64 ) , scope_json TEXT NOT NULL CHECK ( json_valid ( scope_json ) ) , scope_sha256 TEXT NOT NULL CHECK ( length ( scope_sha256 ) = 64 ) , ledger_sha256 TEXT NOT NULL CHECK ( length ( ledger_sha256 ) = 64 ) , review_revision BIGINT NOT NULL , state TEXT NOT NULL DEFAULT 'planned' CHECK ( state IN ( 'planned' , 'processing' , 'blocked' , 'disposition_verified' ) ) , revision BIGINT NOT NULL DEFAULT 0 CHECK ( revision >= 0 ) , created_seconds BIGINT NOT NULL );
CREATE TABLE privacy_retention_tasks ( id TEXT PRIMARY KEY , plan_id TEXT NOT NULL , class_name TEXT NOT NULL , action TEXT NOT NULL CHECK ( action IN ( 'retain' , 'erase' , 'quarantine' , 'blocked' ) ) , expected_json TEXT NOT NULL CHECK ( json_valid ( expected_json ) ) , state TEXT NOT NULL DEFAULT 'pending' CHECK ( state IN ( 'pending' , 'claimed' , 'blocked' , 'verified' ) ) , revision BIGINT NOT NULL DEFAULT 0 CHECK ( revision >= 0 ) , fence BIGINT NOT NULL DEFAULT 0 CHECK ( fence >= 0 ) , claim_id TEXT , post_images_json TEXT CHECK ( post_images_json IS NULL OR json_valid ( post_images_json ) ) , outcome_json TEXT CHECK ( outcome_json IS NULL OR json_valid ( outcome_json ) ) , UNIQUE ( plan_id , class_name ) );
CREATE TABLE privacy_retention_claims ( id TEXT PRIMARY KEY , operation_id TEXT NOT NULL UNIQUE , task_id TEXT NOT NULL , actor_id TEXT NOT NULL , session_id TEXT NOT NULL , input_sha256 TEXT NOT NULL CHECK ( length ( input_sha256 ) = 64 ) , expected_revision BIGINT NOT NULL , fence BIGINT NOT NULL CHECK ( fence > 0 ) , claimed_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL , CHECK ( expires_seconds > claimed_seconds AND expires_seconds <= claimed_seconds + 120 ) );
CREATE TABLE privacy_retention_outcomes ( operation_id TEXT PRIMARY KEY , task_id TEXT NOT NULL , claim_id TEXT NOT NULL , fence BIGINT NOT NULL , input_sha256 TEXT NOT NULL CHECK ( length ( input_sha256 ) = 64 ) , outcome_json TEXT NOT NULL CHECK ( json_valid ( outcome_json ) ) , observed_seconds BIGINT NOT NULL );
CREATE TABLE privacy_retention_effects ( operation_id TEXT PRIMARY KEY , task_id TEXT NOT NULL , claim_id TEXT NOT NULL , fence BIGINT NOT NULL , source_sha256 TEXT NOT NULL CHECK ( length ( source_sha256 ) = 64 ) , object_key TEXT NOT NULL , object_version TEXT NOT NULL , started_seconds BIGINT NOT NULL , UNIQUE ( task_id , object_key ) );
CREATE TABLE privacy_retention_guards ( id TEXT PRIMARY KEY , plan_id TEXT NOT NULL , class_name TEXT NOT NULL , passed BIGINT NOT NULL CHECK ( passed = 1 ) );
CREATE TABLE privacy_retention_barriers ( subject_id TEXT PRIMARY KEY , plan_id TEXT NOT NULL UNIQUE , source_id TEXT NOT NULL CHECK ( length ( source_id ) = 64 ) , policy_sha256 TEXT NOT NULL CHECK ( length ( policy_sha256 ) = 64 ) , activated_seconds BIGINT NOT NULL );
CREATE TABLE auth_identity_rate_aliases ( request_id TEXT NOT NULL , identity_key_id TEXT NOT NULL CHECK ( length ( identity_key_id ) BETWEEN 1 AND 128 AND ( substr ( identity_key_id , 1 , 1 ) ~ '^[A-Za-z0-9]$' ) AND ( identity_key_id !~ '^.*[^A-Za-z0-9._:-].*$' ) ) , identity_hash TEXT NOT NULL CHECK ( length ( identity_hash ) = 64 AND ( identity_hash !~ '^.*[^0-9a-f].*$' ) ) , requested_at BIGINT NOT NULL , hourly_window_ends_at BIGINT NOT NULL , PRIMARY KEY ( request_id , identity_key_id ) , UNIQUE ( request_id , identity_hash ) );
CREATE TABLE assisted_sms_policies ( collection_id TEXT PRIMARY KEY , enabled BIGINT NOT NULL DEFAULT 0 CHECK ( enabled IN ( 0 , 1 ) ) , revision BIGINT NOT NULL CHECK ( revision > 0 ) , template_key TEXT NOT NULL CHECK ( template_key = 'collect.recorded_contribution.v1' ) , approval_reference_sha256 TEXT NOT NULL CHECK ( length ( approval_reference_sha256 ) = 64 AND ( approval_reference_sha256 !~ '^.*[^0-9a-f].*$' ) ) , updated_at TEXT NOT NULL );
CREATE TABLE assisted_sms_authorizations ( collection_id TEXT NOT NULL , recipient_user_id TEXT NOT NULL , enabled BIGINT NOT NULL DEFAULT 0 CHECK ( enabled IN ( 0 , 1 ) ) , consent_revision BIGINT NOT NULL CHECK ( consent_revision > 0 ) , destination_revision BIGINT NOT NULL CHECK ( destination_revision > 0 ) , destination_ciphertext TEXT NOT NULL CHECK ( json_valid ( destination_ciphertext ) ) , destination_sha256 TEXT NOT NULL CHECK ( length ( destination_sha256 ) = 64 AND ( destination_sha256 !~ '^.*[^0-9a-f].*$' ) ) , phone_verification_challenge_id TEXT CHECK ( phone_verification_challenge_id IS NULL OR length ( phone_verification_challenge_id ) = 36 ) , authorization_receipt_sha256 TEXT NOT NULL CHECK ( length ( authorization_receipt_sha256 ) = 64 AND ( authorization_receipt_sha256 !~ '^.*[^0-9a-f].*$' ) ) , updated_at TEXT NOT NULL , PRIMARY KEY ( collection_id , recipient_user_id ) );
CREATE TABLE assisted_sms_jobs ( id TEXT PRIMARY KEY , payment_id TEXT NOT NULL UNIQUE , entry_id TEXT NOT NULL UNIQUE , collection_id TEXT NOT NULL , recipient_user_id TEXT NOT NULL , payment_revision BIGINT NOT NULL CHECK ( payment_revision > 0 ) , amount_minor BIGINT NOT NULL CHECK ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) , destination_revision BIGINT NOT NULL CHECK ( destination_revision > 0 ) , destination_sha256 TEXT NOT NULL CHECK ( length ( destination_sha256 ) = 64 ) , destination_ciphertext TEXT NOT NULL CHECK ( json_valid ( destination_ciphertext ) ) , consent_revision BIGINT NOT NULL CHECK ( consent_revision > 0 ) , policy_revision BIGINT NOT NULL CHECK ( policy_revision > 0 ) , policy_approval_sha256 TEXT NOT NULL CHECK ( length ( policy_approval_sha256 ) = 64 ) , authorization_receipt_sha256 TEXT NOT NULL CHECK ( length ( authorization_receipt_sha256 ) = 64 ) , template_key TEXT NOT NULL CHECK ( template_key = 'collect.recorded_contribution.v1' ) , body_ciphertext TEXT NOT NULL CHECK ( json_valid ( body_ciphertext ) ) , body_sha256 TEXT NOT NULL CHECK ( length ( body_sha256 ) = 64 ) , state TEXT NOT NULL DEFAULT 'queued' CHECK ( state IN ( 'queued' , 'claimed' , 'send_started' , 'observed_sent' , 'failed_no_send' , 'uncertain' ) ) , fence BIGINT NOT NULL DEFAULT 0 CHECK ( fence >= 0 ) , active_claim_id TEXT , created_at TEXT NOT NULL );
CREATE TABLE assisted_sms_claims ( id TEXT PRIMARY KEY , request_id TEXT NOT NULL UNIQUE , job_id TEXT NOT NULL , actor_admin_id TEXT NOT NULL , actor_user_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , public_session_id TEXT NOT NULL , actor_role TEXT NOT NULL , actor_auth_version BIGINT NOT NULL , actor_mfa_at BIGINT NOT NULL , origin TEXT NOT NULL , worker_id TEXT NOT NULL , previous_fence BIGINT NOT NULL CHECK ( previous_fence >= 0 ) , fence BIGINT NOT NULL CHECK ( fence = previous_fence + 1 ) , created_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL CHECK ( expires_seconds > created_seconds ) , UNIQUE ( job_id , fence ) );
CREATE TABLE assisted_sms_confirmations ( id TEXT PRIMARY KEY , request_id TEXT NOT NULL UNIQUE , job_id TEXT NOT NULL , claim_id TEXT NOT NULL UNIQUE , fence BIGINT NOT NULL , actor_admin_id TEXT NOT NULL , actor_user_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , public_session_id TEXT NOT NULL , body_sha256 TEXT NOT NULL , destination_sha256 TEXT NOT NULL , destination_revision BIGINT NOT NULL , confirmed_seconds BIGINT NOT NULL , expires_seconds BIGINT NOT NULL CHECK ( expires_seconds > confirmed_seconds ) );
CREATE TABLE assisted_sms_send_starts ( id TEXT PRIMARY KEY , request_id TEXT NOT NULL UNIQUE , job_id TEXT NOT NULL UNIQUE , confirmation_id TEXT NOT NULL UNIQUE , claim_id TEXT NOT NULL , fence BIGINT NOT NULL , actor_admin_id TEXT NOT NULL , actor_user_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , public_session_id TEXT NOT NULL , body_sha256 TEXT NOT NULL , destination_sha256 TEXT NOT NULL , destination_revision BIGINT NOT NULL , started_seconds BIGINT NOT NULL );
CREATE TABLE assisted_sms_outcomes ( id TEXT PRIMARY KEY , request_id TEXT NOT NULL UNIQUE , attempt_id TEXT NOT NULL UNIQUE , observer_admin_id TEXT NOT NULL , observer_user_id TEXT NOT NULL , observer_session_id TEXT NOT NULL , observer_public_session_id TEXT NOT NULL , observation TEXT NOT NULL CHECK ( observation IN ( 'observed_sent' , 'failed_no_send' , 'uncertain' ) ) , evidence_reference_sha256 TEXT NOT NULL CHECK ( length ( evidence_reference_sha256 ) = 64 AND ( evidence_reference_sha256 !~ '^.*[^0-9a-f].*$' ) ) , observed_seconds BIGINT NOT NULL );
CREATE TABLE momo_receiving_accounts ( id TEXT PRIMARY KEY , provider TEXT NOT NULL CHECK ( provider IN ( 'mtn_momo' , 'airtel_money' ) ) , public_code TEXT NOT NULL , recipient_name TEXT NOT NULL , receiver_hash TEXT NOT NULL CHECK ( length ( receiver_hash ) = 64 ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , timezone TEXT NOT NULL , status TEXT NOT NULL DEFAULT 'active' CHECK ( status IN ( 'active' , 'suspended' ) ) , profile_status TEXT NOT NULL DEFAULT 'unverified' CHECK ( profile_status IN ( 'unverified' , 'approved' ) ) , profile_version TEXT NOT NULL DEFAULT 'unverified' , profile_json TEXT NOT NULL DEFAULT '{}' CHECK ( json_valid ( profile_json ) ) , created_at TEXT NOT NULL , UNIQUE ( provider , receiver_hash ) );
CREATE TABLE momo_gateway_bindings ( id TEXT PRIMARY KEY , owner_user_id TEXT NOT NULL , receiving_account_id TEXT NOT NULL , version BIGINT NOT NULL DEFAULT 1 CHECK ( version > 0 ) , status TEXT NOT NULL DEFAULT 'active' CHECK ( status IN ( 'active' , 'revoked' ) ) , subscription_evidence TEXT , created_at TEXT NOT NULL , revoked_at TEXT , UNIQUE ( id , version , receiving_account_id ) );
CREATE TABLE momo_processing_jobs ( raw_sms_id TEXT PRIMARY KEY , binding_id TEXT , binding_version BIGINT , receiving_account_id TEXT , mode TEXT NOT NULL CHECK ( mode IN ( 'live' , 'historical' ) ) , state TEXT NOT NULL CHECK ( state IN ( 'pending' , 'processing' , 'retry' , 'completed' , 'needs_review' , 'source_unresolved' ) ) , attempt_count BIGINT NOT NULL DEFAULT 0 CHECK ( attempt_count >= 0 ) , max_attempts BIGINT NOT NULL DEFAULT 4 CHECK ( max_attempts >= 4 ) , available_at BIGINT NOT NULL , lease_token TEXT , lease_until BIGINT , last_error TEXT , created_at TEXT NOT NULL , updated_at TEXT NOT NULL , CHECK ( ( binding_id IS NULL AND binding_version IS NULL AND ( receiving_account_id IS NULL OR mode = 'historical' ) ) OR ( binding_id IS NOT NULL AND binding_version IS NOT NULL AND receiving_account_id IS NOT NULL ) ) );
CREATE TABLE momo_parse_attempts ( id TEXT PRIMARY KEY , raw_sms_id TEXT NOT NULL , attempt_number BIGINT NOT NULL , model_id TEXT NOT NULL , schema_version TEXT NOT NULL , prompt_version TEXT NOT NULL , parser_version TEXT NOT NULL , profile_version TEXT NOT NULL , profile_json TEXT NOT NULL CHECK ( json_valid ( profile_json ) ) , source_body_sha256 TEXT NOT NULL , output_json TEXT CHECK ( output_json IS NULL OR json_valid ( output_json ) ) , validation_json TEXT NOT NULL CHECK ( json_valid ( validation_json ) ) , outcome TEXT NOT NULL CHECK ( outcome IN ( 'accepted' , 'duplicate' , 'conflict' , 'non_payment' , 'needs_review' , 'retry' , 'superseded' ) ) , created_at TEXT NOT NULL , UNIQUE ( raw_sms_id , attempt_number ) );
CREATE TABLE momo_transactions ( id TEXT PRIMARY KEY , receiving_account_id TEXT NOT NULL , provider TEXT NOT NULL , provider_transaction_id TEXT NOT NULL , event_kind TEXT NOT NULL CHECK ( event_kind IN ( 'incoming_receipt' , 'reversal' ) ) , original_transaction_id TEXT , amount_minor BIGINT NOT NULL CHECK ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) , currency TEXT NOT NULL CHECK ( currency = 'RWF' ) , currency_scale BIGINT NOT NULL CHECK ( currency_scale = 0 ) , payer_name TEXT , payer_identifier TEXT , payer_last3 TEXT CHECK ( payer_last3 IS NULL OR ( length ( payer_last3 ) = 3 AND ( payer_last3 !~ '^.*[^0-9].*$' ) ) ) , transaction_at TEXT , transaction_datetime_raw TEXT , transaction_timezone TEXT NOT NULL , transaction_time_source TEXT NOT NULL , fee_minor BIGINT CHECK ( fee_minor IS NULL OR fee_minor >= 0 ) , wallet_balance_after_minor BIGINT CHECK ( wallet_balance_after_minor IS NULL OR wallet_balance_after_minor >= 0 ) , parse_attempt_id TEXT NOT NULL , mode TEXT NOT NULL CHECK ( mode IN ( 'live' , 'historical' ) ) , allocation_state TEXT NOT NULL DEFAULT 'unallocated' CHECK ( allocation_state IN ( 'unallocated' , 'linked' , 'needs_review' ) ) , has_conflict BIGINT NOT NULL DEFAULT 0 CHECK ( has_conflict IN ( 0 , 1 ) ) , version BIGINT NOT NULL DEFAULT 1 , created_at TEXT NOT NULL , updated_at TEXT NOT NULL , UNIQUE ( provider , receiving_account_id , event_kind , provider_transaction_id ) );
CREATE TABLE momo_transaction_sources ( transaction_id TEXT NOT NULL , raw_sms_id TEXT NOT NULL , parse_attempt_id TEXT NOT NULL , relation TEXT NOT NULL CHECK ( relation IN ( 'accepted' , 'duplicate' , 'conflict' ) ) , created_at TEXT NOT NULL , PRIMARY KEY ( transaction_id , raw_sms_id , parse_attempt_id ) );
CREATE TABLE momo_processing_guards ( id TEXT PRIMARY KEY , passed BIGINT NOT NULL CONSTRAINT momo_processing_state CHECK ( passed = 1 ) );
CREATE TABLE momo_gateway_pairings ( id TEXT PRIMARY KEY , binding_id TEXT NOT NULL , code_sha256 TEXT NOT NULL UNIQUE , originating_session_id TEXT NOT NULL , expires_at BIGINT NOT NULL , claimed_installation_id TEXT , created_at TEXT NOT NULL );
CREATE TABLE momo_gateway_credentials ( id TEXT PRIMARY KEY , binding_id TEXT NOT NULL UNIQUE , pairing_id TEXT NOT NULL UNIQUE , installation_id TEXT NOT NULL , token_sha256 TEXT NOT NULL UNIQUE , token_ciphertext TEXT NOT NULL , last_contact_at TEXT , last_sms_at TEXT , pending_count BIGINT NOT NULL DEFAULT 0 CHECK ( pending_count >= 0 ) , oldest_pending_at TEXT , revoked_at TEXT , created_at TEXT NOT NULL );
CREATE TABLE momo_gateway_captures ( raw_sms_id TEXT PRIMARY KEY , credential_id TEXT NOT NULL , identity_sha256 TEXT NOT NULL , service_centre_at TEXT , captured_at TEXT NOT NULL , inbox_received_at TEXT , subscription_id BIGINT , completeness TEXT NOT NULL CHECK ( completeness IN ( 'complete' , 'incomplete' , 'inconsistent' ) ) , source_mode TEXT NOT NULL CHECK ( source_mode IN ( 'live' , 'catch_up' ) ) , created_at TEXT NOT NULL );
CREATE TABLE momo_source_resolutions ( id TEXT PRIMARY KEY , raw_sms_id TEXT NOT NULL UNIQUE , receiving_account_id TEXT NOT NULL , source_body_sha256 TEXT NOT NULL , reviewed_by TEXT NOT NULL , evidence_reference TEXT NOT NULL , reason TEXT NOT NULL , created_at TEXT NOT NULL );
CREATE TABLE momo_financial_links ( transaction_id TEXT PRIMARY KEY , payment_id TEXT NOT NULL UNIQUE , beneficiary_member_id TEXT NOT NULL , linked_by TEXT NOT NULL , reason TEXT NOT NULL , historical_existing BIGINT NOT NULL DEFAULT 0 CHECK ( historical_existing IN ( 0 , 1 ) ) , created_at TEXT NOT NULL );
CREATE TABLE contribution_posting_snapshots ( ledger_entry_id TEXT PRIMARY KEY , payment_id TEXT NOT NULL UNIQUE , member_balance_after_minor BIGINT NOT NULL CHECK ( member_balance_after_minor >= 0 AND member_balance_after_minor <= 9007199254740991 ) , group_balance_after_minor BIGINT NOT NULL CHECK ( group_balance_after_minor >= 0 AND group_balance_after_minor <= 9007199254740991 ) , posted_at TEXT NOT NULL );
CREATE TABLE auth_google_flows ( id TEXT PRIMARY KEY , state_hash TEXT NOT NULL UNIQUE CHECK ( length ( state_hash ) = 64 ) , nonce TEXT NOT NULL , provider_verifier TEXT NOT NULL CHECK ( json_valid ( provider_verifier ) ) , client_challenge TEXT NOT NULL CHECK ( length ( client_challenge ) = 43 ) , client_state TEXT NOT NULL , return_origin TEXT , registration_allowed BIGINT NOT NULL CHECK ( registration_allowed IN ( 0 , 1 ) ) , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , status TEXT NOT NULL CHECK ( status IN ( 'pending' , 'exchanging' , 'ready' , 'consumed' , 'failed' ) ) , google_subject TEXT , email TEXT , handoff_hash TEXT UNIQUE , consumed_operation_id TEXT UNIQUE );
CREATE TABLE auth_google_identities ( subject TEXT PRIMARY KEY , user_id TEXT NOT NULL UNIQUE , created_at TEXT NOT NULL );
CREATE TABLE admin_email_otp_challenges ( id TEXT PRIMARY KEY , user_id TEXT NOT NULL , principal_user_id TEXT NOT NULL , origin TEXT NOT NULL CHECK ( origin LIKE 'https://%' ) , role TEXT NOT NULL CHECK ( role IN ( 'owner' , 'admin' , 'staff' ) ) , auth_version BIGINT NOT NULL , challenge_version BIGINT NOT NULL , account_status TEXT NOT NULL CHECK ( account_status IN ( 'invited' , 'active' ) ) , code_hash TEXT NOT NULL CHECK ( length ( code_hash ) = 64 ) , created_at BIGINT NOT NULL , expires_at BIGINT NOT NULL CHECK ( expires_at > created_at ) , attempts BIGINT NOT NULL DEFAULT 0 CHECK ( attempts BETWEEN 0 AND 5 ) , delivery_status TEXT NOT NULL DEFAULT 'pending' CHECK ( delivery_status IN ( 'pending' , 'accepted' , 'unknown' , 'failed' , 'superseded' ) ) , used_at BIGINT , consumed_session_id TEXT UNIQUE , CHECK ( ( used_at IS NULL AND consumed_session_id IS NULL ) OR ( used_at IS NOT NULL AND consumed_session_id IS NOT NULL ) ) );
ALTER TABLE app.admin_grants ADD CONSTRAINT fk_admin_grants_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_role_assignments ADD CONSTRAINT fk_admin_role_assignments_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.collections ADD CONSTRAINT fk_collections_0 FOREIGN KEY (creator_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.memberships ADD CONSTRAINT fk_memberships_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.memberships ADD CONSTRAINT fk_memberships_1 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payment_intents ADD CONSTRAINT fk_payment_intents_0 FOREIGN KEY (member_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payment_intents ADD CONSTRAINT fk_payment_intents_1 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payment_evidence ADD CONSTRAINT fk_payment_evidence_0 FOREIGN KEY (owner_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payment_evidence ADD CONSTRAINT fk_payment_evidence_1 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payments ADD CONSTRAINT fk_payments_0 FOREIGN KEY (intent_id) REFERENCES app.payment_intents(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payments ADD CONSTRAINT fk_payments_1 FOREIGN KEY (evidence_id) REFERENCES app.payment_evidence(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payments ADD CONSTRAINT fk_payments_2 FOREIGN KEY (member_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.payments ADD CONSTRAINT fk_payments_3 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.ledger_entries ADD CONSTRAINT fk_ledger_entries_0 FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.ledger_entries ADD CONSTRAINT fk_ledger_entries_1 FOREIGN KEY (evidence_id) REFERENCES app.payment_evidence(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.ledger_entries ADD CONSTRAINT fk_ledger_entries_2 FOREIGN KEY (reverses_entry_id) REFERENCES app.ledger_entries(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.ledger_entries ADD CONSTRAINT fk_ledger_entries_3 FOREIGN KEY (member_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.ledger_entries ADD CONSTRAINT fk_ledger_entries_4 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.ledger_entries ADD CONSTRAINT fk_ledger_entries_5 FOREIGN KEY (payment_id) REFERENCES app.payments(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.reconciliations ADD CONSTRAINT fk_reconciliations_0 FOREIGN KEY (approved_by) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.reconciliations ADD CONSTRAINT fk_reconciliations_1 FOREIGN KEY (evidence_id) REFERENCES app.payment_evidence(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.reconciliations ADD CONSTRAINT fk_reconciliations_2 FOREIGN KEY (proposed_by) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.reconciliations ADD CONSTRAINT fk_reconciliations_3 FOREIGN KEY (proposed_member_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.reconciliations ADD CONSTRAINT fk_reconciliations_4 FOREIGN KEY (payment_id) REFERENCES app.payments(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.notification_preferences ADD CONSTRAINT fk_notification_preferences_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.notification_devices ADD CONSTRAINT fk_notification_devices_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.notification_events ADD CONSTRAINT fk_notification_events_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.support_requests ADD CONSTRAINT fk_support_requests_0 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.support_requests ADD CONSTRAINT fk_support_requests_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.runtime_config ADD CONSTRAINT fk_runtime_config_0 FOREIGN KEY (updated_by) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.audit_log ADD CONSTRAINT fk_audit_log_0 FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.request_receipts ADD CONSTRAINT fk_request_receipts_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.deletion_requests ADD CONSTRAINT fk_deletion_requests_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.deletion_reviews ADD CONSTRAINT fk_deletion_reviews_0 FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.deletion_reviews ADD CONSTRAINT fk_deletion_reviews_1 FOREIGN KEY (request_id) REFERENCES app.deletion_requests(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_holds ADD CONSTRAINT fk_privacy_holds_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.upload_objects ADD CONSTRAINT fk_upload_objects_0 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.upload_objects ADD CONSTRAINT fk_upload_objects_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_sessions ADD CONSTRAINT fk_auth_sessions_0 FOREIGN KEY (mfa_factor_id) REFERENCES app.auth_mfa_factors(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_sessions ADD CONSTRAINT fk_auth_sessions_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_factors ADD CONSTRAINT fk_auth_mfa_factors_0 FOREIGN KEY (enrollment_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_factors ADD CONSTRAINT fk_auth_mfa_factors_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_challenges ADD CONSTRAINT fk_auth_mfa_challenges_0 FOREIGN KEY (factor_id) REFERENCES app.auth_mfa_factors(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_challenges ADD CONSTRAINT fk_auth_mfa_challenges_1 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_challenges ADD CONSTRAINT fk_auth_mfa_challenges_2 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_budgets ADD CONSTRAINT fk_auth_mfa_budgets_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_claims ADD CONSTRAINT fk_auth_mfa_claims_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_claims ADD CONSTRAINT fk_auth_mfa_claims_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_claims ADD CONSTRAINT fk_auth_mfa_claims_2 FOREIGN KEY (factor_id) REFERENCES app.auth_mfa_factors(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_claims ADD CONSTRAINT fk_auth_mfa_claims_3 FOREIGN KEY (challenge_id) REFERENCES app.auth_mfa_challenges(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_revocations ADD CONSTRAINT fk_auth_mfa_revocations_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_revocations ADD CONSTRAINT fk_auth_mfa_revocations_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_mfa_revocations ADD CONSTRAINT fk_auth_mfa_revocations_2 FOREIGN KEY (factor_id) REFERENCES app.auth_mfa_factors(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_refresh_tokens ADD CONSTRAINT fk_auth_refresh_tokens_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_otp_verifications ADD CONSTRAINT fk_auth_otp_verifications_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_otp_verifications ADD CONSTRAINT fk_auth_otp_verifications_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_otp_verifications ADD CONSTRAINT fk_auth_otp_verifications_2 FOREIGN KEY (challenge_id) REFERENCES app.auth_otp_challenges(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_submissions ADD CONSTRAINT fk_privacy_submissions_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_submissions ADD CONSTRAINT fk_privacy_submissions_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_submissions ADD CONSTRAINT fk_privacy_submissions_2 FOREIGN KEY (request_id) REFERENCES app.deletion_requests(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_heads ADD CONSTRAINT fk_privacy_review_heads_0 FOREIGN KEY (last_outcome_id) REFERENCES app.privacy_review_outcomes(outcome_request_id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_heads ADD CONSTRAINT fk_privacy_review_heads_1 FOREIGN KEY (latest_claim_id) REFERENCES app.privacy_review_claims(claim_id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_heads ADD CONSTRAINT fk_privacy_review_heads_2 FOREIGN KEY (request_id) REFERENCES app.deletion_requests(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_claims ADD CONSTRAINT fk_privacy_review_claims_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_claims ADD CONSTRAINT fk_privacy_review_claims_1 FOREIGN KEY (actor_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_claims ADD CONSTRAINT fk_privacy_review_claims_2 FOREIGN KEY (request_id) REFERENCES app.deletion_requests(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_outcomes ADD CONSTRAINT fk_privacy_review_outcomes_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_outcomes ADD CONSTRAINT fk_privacy_review_outcomes_1 FOREIGN KEY (actor_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_outcomes ADD CONSTRAINT fk_privacy_review_outcomes_2 FOREIGN KEY (claim_id) REFERENCES app.privacy_review_claims(claim_id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_review_outcomes ADD CONSTRAINT fk_privacy_review_outcomes_3 FOREIGN KEY (request_id) REFERENCES app.deletion_requests(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_consents ADD CONSTRAINT fk_native_consents_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_consents ADD CONSTRAINT fk_native_consents_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_reservations ADD CONSTRAINT fk_native_reservations_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_reservations ADD CONSTRAINT fk_native_reservations_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_phases ADD CONSTRAINT fk_native_phases_0 FOREIGN KEY (reservation_id) REFERENCES app.native_reservations(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_capabilities ADD CONSTRAINT fk_native_capabilities_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_capabilities ADD CONSTRAINT fk_native_capabilities_1 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_capabilities ADD CONSTRAINT fk_native_capabilities_2 FOREIGN KEY (reservation_id) REFERENCES app.native_reservations(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_completions ADD CONSTRAINT fk_native_completions_0 FOREIGN KEY (capability_id) REFERENCES app.native_capabilities(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_completions ADD CONSTRAINT fk_native_completions_1 FOREIGN KEY (reservation_id) REFERENCES app.native_reservations(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.native_capability_claims ADD CONSTRAINT fk_native_capability_claims_0 FOREIGN KEY (capability_id) REFERENCES app.native_capabilities(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_imports ADD CONSTRAINT fk_roster_imports_0 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_imports ADD CONSTRAINT fk_roster_imports_1 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_imports ADD CONSTRAINT fk_roster_imports_2 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_processing_records ADD CONSTRAINT fk_roster_processing_records_0 FOREIGN KEY (import_id) REFERENCES app.roster_imports(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_dispatch_phases ADD CONSTRAINT fk_roster_dispatch_phases_0 FOREIGN KEY (processing_id) REFERENCES app.roster_processing_records(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_revisions ADD CONSTRAINT fk_roster_revisions_0 FOREIGN KEY (parent_revision_id) REFERENCES app.roster_revisions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_revisions ADD CONSTRAINT fk_roster_revisions_1 FOREIGN KEY (import_id) REFERENCES app.roster_imports(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_members ADD CONSTRAINT fk_roster_members_0 FOREIGN KEY (linked_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_members ADD CONSTRAINT fk_roster_members_1 FOREIGN KEY (source_revision_id) REFERENCES app.roster_revisions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_members ADD CONSTRAINT fk_roster_members_2 FOREIGN KEY (source_import_id) REFERENCES app.roster_imports(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_members ADD CONSTRAINT fk_roster_members_3 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.roster_intents ADD CONSTRAINT fk_roster_intents_0 FOREIGN KEY (import_id) REFERENCES app.roster_imports(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_sessions ADD CONSTRAINT fk_admin_sessions_0 FOREIGN KEY (issued_mfa_factor_id) REFERENCES app.auth_mfa_factors(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_sessions ADD CONSTRAINT fk_admin_sessions_1 FOREIGN KEY (auth_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_sessions ADD CONSTRAINT fk_admin_sessions_2 FOREIGN KEY (user_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_challenges ADD CONSTRAINT fk_admin_challenges_0 FOREIGN KEY (user_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_email_events ADD CONSTRAINT fk_admin_email_events_0 FOREIGN KEY (user_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_principal_links ADD CONSTRAINT fk_admin_principal_links_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_principal_links ADD CONSTRAINT fk_admin_principal_links_1 FOREIGN KEY (admin_user_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_bridge_requests ADD CONSTRAINT fk_admin_bridge_requests_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_bridge_requests ADD CONSTRAINT fk_admin_bridge_requests_1 FOREIGN KEY (admin_user_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_bridge_reconciliation_snapshots ADD CONSTRAINT fk_admin_bridge_reconciliation_snapshots_0 FOREIGN KEY (membership_id) REFERENCES app.memberships(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_bridge_reconciliation_snapshots ADD CONSTRAINT fk_admin_bridge_reconciliation_snapshots_1 FOREIGN KEY (member_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_bridge_reconciliation_snapshots ADD CONSTRAINT fk_admin_bridge_reconciliation_snapshots_2 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_bridge_reconciliation_snapshots ADD CONSTRAINT fk_admin_bridge_reconciliation_snapshots_3 FOREIGN KEY (reconciliation_id) REFERENCES app.reconciliations(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.sms_receipts ADD CONSTRAINT fk_sms_receipts_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.sms_receipts ADD CONSTRAINT fk_sms_receipts_1 FOREIGN KEY (owner_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_operator_notes ADD CONSTRAINT fk_admin_operator_notes_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_operator_notes ADD CONSTRAINT fk_admin_operator_notes_1 FOREIGN KEY (created_by) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_plans ADD CONSTRAINT fk_privacy_retention_plans_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_plans ADD CONSTRAINT fk_privacy_retention_plans_1 FOREIGN KEY (actor_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_plans ADD CONSTRAINT fk_privacy_retention_plans_2 FOREIGN KEY (subject_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_plans ADD CONSTRAINT fk_privacy_retention_plans_3 FOREIGN KEY (request_id) REFERENCES app.deletion_requests(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_tasks ADD CONSTRAINT fk_privacy_retention_tasks_0 FOREIGN KEY (plan_id) REFERENCES app.privacy_retention_plans(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_claims ADD CONSTRAINT fk_privacy_retention_claims_0 FOREIGN KEY (session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_claims ADD CONSTRAINT fk_privacy_retention_claims_1 FOREIGN KEY (actor_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_claims ADD CONSTRAINT fk_privacy_retention_claims_2 FOREIGN KEY (task_id) REFERENCES app.privacy_retention_tasks(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_outcomes ADD CONSTRAINT fk_privacy_retention_outcomes_0 FOREIGN KEY (claim_id) REFERENCES app.privacy_retention_claims(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_outcomes ADD CONSTRAINT fk_privacy_retention_outcomes_1 FOREIGN KEY (task_id) REFERENCES app.privacy_retention_tasks(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_effects ADD CONSTRAINT fk_privacy_retention_effects_0 FOREIGN KEY (claim_id) REFERENCES app.privacy_retention_claims(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_effects ADD CONSTRAINT fk_privacy_retention_effects_1 FOREIGN KEY (task_id) REFERENCES app.privacy_retention_tasks(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_guards ADD CONSTRAINT fk_privacy_retention_guards_0 FOREIGN KEY (plan_id) REFERENCES app.privacy_retention_plans(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_barriers ADD CONSTRAINT fk_privacy_retention_barriers_0 FOREIGN KEY (plan_id) REFERENCES app.privacy_retention_plans(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.privacy_retention_barriers ADD CONSTRAINT fk_privacy_retention_barriers_1 FOREIGN KEY (subject_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_identity_rate_aliases ADD CONSTRAINT fk_auth_identity_rate_aliases_0 FOREIGN KEY (request_id) REFERENCES app.auth_rate_claims(request_id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_policies ADD CONSTRAINT fk_assisted_sms_policies_0 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_authorizations ADD CONSTRAINT fk_assisted_sms_authorizations_0 FOREIGN KEY (recipient_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_authorizations ADD CONSTRAINT fk_assisted_sms_authorizations_1 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_jobs ADD CONSTRAINT fk_assisted_sms_jobs_0 FOREIGN KEY (recipient_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_jobs ADD CONSTRAINT fk_assisted_sms_jobs_1 FOREIGN KEY (collection_id) REFERENCES app.collections(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_jobs ADD CONSTRAINT fk_assisted_sms_jobs_2 FOREIGN KEY (entry_id) REFERENCES app.ledger_entries(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_jobs ADD CONSTRAINT fk_assisted_sms_jobs_3 FOREIGN KEY (payment_id) REFERENCES app.payments(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_claims ADD CONSTRAINT fk_assisted_sms_claims_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_claims ADD CONSTRAINT fk_assisted_sms_claims_1 FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_claims ADD CONSTRAINT fk_assisted_sms_claims_2 FOREIGN KEY (actor_admin_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_claims ADD CONSTRAINT fk_assisted_sms_claims_3 FOREIGN KEY (job_id) REFERENCES app.assisted_sms_jobs(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_confirmations ADD CONSTRAINT fk_assisted_sms_confirmations_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_confirmations ADD CONSTRAINT fk_assisted_sms_confirmations_1 FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_confirmations ADD CONSTRAINT fk_assisted_sms_confirmations_2 FOREIGN KEY (actor_admin_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_confirmations ADD CONSTRAINT fk_assisted_sms_confirmations_3 FOREIGN KEY (claim_id) REFERENCES app.assisted_sms_claims(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_confirmations ADD CONSTRAINT fk_assisted_sms_confirmations_4 FOREIGN KEY (job_id) REFERENCES app.assisted_sms_jobs(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_send_starts ADD CONSTRAINT fk_assisted_sms_send_starts_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_send_starts ADD CONSTRAINT fk_assisted_sms_send_starts_1 FOREIGN KEY (actor_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_send_starts ADD CONSTRAINT fk_assisted_sms_send_starts_2 FOREIGN KEY (actor_admin_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_send_starts ADD CONSTRAINT fk_assisted_sms_send_starts_3 FOREIGN KEY (claim_id) REFERENCES app.assisted_sms_claims(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_send_starts ADD CONSTRAINT fk_assisted_sms_send_starts_4 FOREIGN KEY (confirmation_id) REFERENCES app.assisted_sms_confirmations(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_send_starts ADD CONSTRAINT fk_assisted_sms_send_starts_5 FOREIGN KEY (job_id) REFERENCES app.assisted_sms_jobs(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_outcomes ADD CONSTRAINT fk_assisted_sms_outcomes_0 FOREIGN KEY (observer_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_outcomes ADD CONSTRAINT fk_assisted_sms_outcomes_1 FOREIGN KEY (observer_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_outcomes ADD CONSTRAINT fk_assisted_sms_outcomes_2 FOREIGN KEY (observer_admin_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.assisted_sms_outcomes ADD CONSTRAINT fk_assisted_sms_outcomes_3 FOREIGN KEY (attempt_id) REFERENCES app.assisted_sms_send_starts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_bindings ADD CONSTRAINT fk_momo_gateway_bindings_0 FOREIGN KEY (receiving_account_id) REFERENCES app.momo_receiving_accounts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_bindings ADD CONSTRAINT fk_momo_gateway_bindings_1 FOREIGN KEY (owner_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_processing_jobs ADD CONSTRAINT fk_momo_processing_jobs_0 FOREIGN KEY (receiving_account_id) REFERENCES app.momo_receiving_accounts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_processing_jobs ADD CONSTRAINT fk_momo_processing_jobs_1 FOREIGN KEY (binding_id) REFERENCES app.momo_gateway_bindings(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_processing_jobs ADD CONSTRAINT fk_momo_processing_jobs_2 FOREIGN KEY (raw_sms_id) REFERENCES app.sms_receipts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_parse_attempts ADD CONSTRAINT fk_momo_parse_attempts_0 FOREIGN KEY (raw_sms_id) REFERENCES app.sms_receipts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_transactions ADD CONSTRAINT fk_momo_transactions_0 FOREIGN KEY (parse_attempt_id) REFERENCES app.momo_parse_attempts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_transactions ADD CONSTRAINT fk_momo_transactions_1 FOREIGN KEY (receiving_account_id) REFERENCES app.momo_receiving_accounts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_transaction_sources ADD CONSTRAINT fk_momo_transaction_sources_0 FOREIGN KEY (parse_attempt_id) REFERENCES app.momo_parse_attempts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_transaction_sources ADD CONSTRAINT fk_momo_transaction_sources_1 FOREIGN KEY (raw_sms_id) REFERENCES app.sms_receipts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_transaction_sources ADD CONSTRAINT fk_momo_transaction_sources_2 FOREIGN KEY (transaction_id) REFERENCES app.momo_transactions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_pairings ADD CONSTRAINT fk_momo_gateway_pairings_0 FOREIGN KEY (originating_session_id) REFERENCES app.auth_sessions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_pairings ADD CONSTRAINT fk_momo_gateway_pairings_1 FOREIGN KEY (binding_id) REFERENCES app.momo_gateway_bindings(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_credentials ADD CONSTRAINT fk_momo_gateway_credentials_0 FOREIGN KEY (pairing_id) REFERENCES app.momo_gateway_pairings(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_credentials ADD CONSTRAINT fk_momo_gateway_credentials_1 FOREIGN KEY (binding_id) REFERENCES app.momo_gateway_bindings(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_captures ADD CONSTRAINT fk_momo_gateway_captures_0 FOREIGN KEY (credential_id) REFERENCES app.momo_gateway_credentials(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_gateway_captures ADD CONSTRAINT fk_momo_gateway_captures_1 FOREIGN KEY (raw_sms_id) REFERENCES app.sms_receipts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_source_resolutions ADD CONSTRAINT fk_momo_source_resolutions_0 FOREIGN KEY (reviewed_by) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_source_resolutions ADD CONSTRAINT fk_momo_source_resolutions_1 FOREIGN KEY (receiving_account_id) REFERENCES app.momo_receiving_accounts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_source_resolutions ADD CONSTRAINT fk_momo_source_resolutions_2 FOREIGN KEY (raw_sms_id) REFERENCES app.sms_receipts(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_financial_links ADD CONSTRAINT fk_momo_financial_links_0 FOREIGN KEY (linked_by) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_financial_links ADD CONSTRAINT fk_momo_financial_links_1 FOREIGN KEY (beneficiary_member_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_financial_links ADD CONSTRAINT fk_momo_financial_links_2 FOREIGN KEY (payment_id) REFERENCES app.payments(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.momo_financial_links ADD CONSTRAINT fk_momo_financial_links_3 FOREIGN KEY (transaction_id) REFERENCES app.momo_transactions(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.contribution_posting_snapshots ADD CONSTRAINT fk_contribution_posting_snapshots_0 FOREIGN KEY (payment_id) REFERENCES app.payments(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.contribution_posting_snapshots ADD CONSTRAINT fk_contribution_posting_snapshots_1 FOREIGN KEY (ledger_entry_id) REFERENCES app.ledger_entries(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.auth_google_identities ADD CONSTRAINT fk_auth_google_identities_0 FOREIGN KEY (user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_email_otp_challenges ADD CONSTRAINT fk_admin_email_otp_challenges_0 FOREIGN KEY (principal_user_id) REFERENCES app.users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
ALTER TABLE app.admin_email_otp_challenges ADD CONSTRAINT fk_admin_email_otp_challenges_1 FOREIGN KEY (user_id) REFERENCES app.admin_users(id) ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY IMMEDIATE;
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','overview.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','account.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','collections.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','users.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','receivers.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','payments.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','ledger.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','collections.create');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','reconciliations.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','reconciliations.propose');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','auth.mfa.enroll');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','overview.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','account.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','collections.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','users.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','receivers.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','payments.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','ledger.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','collections.create');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','collections.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','users.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','receivers.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','payments.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','payments.write');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','payments.evidence.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','payments.reconcile');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','reconciliations.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','reconciliations.propose');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','reconciliations.review');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','ledger.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','admin_users.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','auth.mfa.enroll');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','overview.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','account.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','collections.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','users.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','receivers.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','payments.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','ledger.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','collections.create');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','collections.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','users.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','receivers.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','payments.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','payments.write');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','payments.evidence.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','payments.reconcile');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','reconciliations.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','reconciliations.propose');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','reconciliations.review');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','ledger.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','admin_users.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','admin_users.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','auth.mfa.enroll');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','privacy.review');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','roster.import');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','audit.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','system_health.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','assisted_sms.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','assisted_sms.manage');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','sms.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','sms.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('staff','sms.read');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','sms.reveal');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','sms.extract');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','sms.reveal');
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('admin','sms.extract');
CREATE INDEX membership_actor ON memberships ( user_id , active , collection_id );
CREATE UNIQUE INDEX one_active_owner ON memberships ( collection_id ) WHERE active = 1 AND role = 'owner';
CREATE INDEX intent_actor ON payment_intents ( member_id , created_at , id );
CREATE INDEX payment_collection ON payments ( collection_id , created_at , id );
CREATE INDEX ledger_actor_history ON ledger_entries ( member_id , posted_at , id );
CREATE UNIQUE INDEX one_contribution_per_payment ON ledger_entries ( payment_id ) WHERE kind = 'contribution';
CREATE INDEX notification_owner ON notification_events ( user_id , created_at , id );
CREATE INDEX audit_entity ON audit_log ( entity_type , entity_id , id );
CREATE UNIQUE INDEX one_active_deletion ON deletion_requests ( user_id ) WHERE status IN ( 'received' , 'under_review' , 'scheduled' , 'erasing' , 'on_hold' , 'failed' );
CREATE INDEX auth_otp_identity ON auth_otp_challenges ( identity_hash , surface , created_at );
CREATE INDEX auth_sessions_user ON auth_sessions ( user_id , revoked_at , expires_at );
CREATE UNIQUE INDEX one_pending_mfa_factor ON auth_mfa_factors ( user_id ) WHERE status = 'pending';
CREATE INDEX auth_refresh_session ON auth_refresh_tokens ( session_id );
CREATE INDEX privacy_submission_request ON privacy_submissions ( request_id );
CREATE INDEX privacy_claim_request ON privacy_review_claims ( request_id );
CREATE INDEX native_budget_actor ON native_reservations ( user_id , created_seconds );
CREATE INDEX native_budget_project ON native_reservations ( project_id , created_seconds );
CREATE UNIQUE INDEX admin_single_owner ON admin_users ( role ) WHERE role = 'owner';
CREATE INDEX admin_sessions_user ON admin_sessions ( user_id );
CREATE INDEX admin_sessions_expiry ON admin_sessions ( expires_at );
CREATE INDEX admin_challenges_user ON admin_challenges ( user_id );
CREATE INDEX admin_email_events_user ON admin_email_events ( user_id , created_at DESC );
CREATE INDEX admin_rate_limits_expiry ON admin_rate_limits ( expires_at );
CREATE INDEX admin_operator_notes_entity ON admin_operator_notes ( entity_type , entity_id , created_at , id );
CREATE INDEX auth_identity_alias_window ON auth_identity_rate_aliases ( identity_hash , hourly_window_ends_at , request_id );
CREATE INDEX assisted_sms_pending ON assisted_sms_jobs ( state , created_at , id );
CREATE VIEW assisted_sms_current_sessions WITH (security_invoker=true) AS SELECT a . id AS admin_id , l . user_id , s . auth_session_id , s . public_id , a . role , a . auth_version , s . issued_mfa_at AS mfa_at , s . origin , c . permission FROM admin_sessions s JOIN admin_users a ON a . id = s . user_id JOIN admin_principal_links l ON l . admin_user_id = a . id JOIN users u ON u . id = l . user_id JOIN auth_sessions ss ON ss . id = s . auth_session_id AND ss . user_id = u . id JOIN auth_mfa_factors f ON f . id = ss . mfa_factor_id AND f . user_id = u . id JOIN admin_grants g ON g . user_id = u . id JOIN admin_account_role_capabilities c ON c . permission = g . permission AND c . role = a . role WHERE a . status = 'active' AND a . auth_version = s . auth_version AND u . access_status = 'active' AND ss . surface = 'admin' AND s . expires_at > unixepoch ( ) AND ss . expires_at > unixepoch ( ) AND ss . revoked_at IS NULL AND s . issued_assurance_level = 2 AND ss . assurance_level = 2 AND f . status = 'verified' AND s . issued_mfa_at = ss . mfa_at AND s . issued_mfa_factor_id = ss . mfa_factor_id AND s . issued_mfa_at BETWEEN unixepoch ( ) - 300 AND unixepoch ( );
CREATE VIEW assisted_sms_current_jobs WITH (security_invoker=true) AS SELECT j . * FROM assisted_sms_jobs j JOIN payments p ON p . id = j . payment_id JOIN ledger_entries e ON e . id = j . entry_id AND e . payment_id = p . id JOIN collections c ON c . id = j . collection_id JOIN users u ON u . id = j . recipient_user_id JOIN memberships m ON m . collection_id = c . id AND m . user_id = u . id JOIN assisted_sms_policies policy ON policy . collection_id = c . id JOIN assisted_sms_authorizations consent ON consent . collection_id = c . id AND consent . recipient_user_id = u . id WHERE p . collection_id = c . id AND p . member_id = u . id AND p . revision = j . payment_revision AND p . status IN ( 'reconciled' , 'confirmed' ) AND p . currency = 'RWF' AND p . rail = 'rwanda_momo' AND e . kind = 'contribution' AND e . amount_minor = j . amount_minor AND p . amount_minor = j . amount_minor AND e . collection_id = c . id AND e . member_id = u . id AND e . evidence_id = p . evidence_id AND e . currency = 'RWF' AND NOT EXISTS ( SELECT 1 FROM ledger_entries inverse WHERE inverse . reverses_entry_id = e . id ) AND c . status = 'active' AND u . access_status = 'active' AND u . member_type != 'operator' AND m . active = 1 AND policy . enabled = 1 AND policy . revision = j . policy_revision AND policy . template_key = j . template_key AND policy . approval_reference_sha256 = j . policy_approval_sha256 AND consent . enabled = 1 AND consent . consent_revision = j . consent_revision AND consent . authorization_receipt_sha256 = j . authorization_receipt_sha256 AND consent . destination_revision = j . destination_revision AND consent . destination_sha256 = j . destination_sha256 AND consent . destination_ciphertext = j . destination_ciphertext AND ( u . member_type != 'app' OR EXISTS ( SELECT 1 FROM auth_otp_verifications proof JOIN auth_otp_challenges challenge ON challenge . id = proof . challenge_id WHERE proof . user_id = u . id AND proof . challenge_id = consent . phone_verification_challenge_id AND challenge . identity_type = 'phone' AND challenge . surface = 'member' AND challenge . identity_value = u . phone AND challenge . status = 'consumed' AND challenge . consumed_operation_id = proof . operation_id AND challenge . consumed_at = proof . verified_at AND proof . verified_at BETWEEN challenge . created_at AND challenge . expires_at ) );
CREATE INDEX sms_receipts_metadata_order ON sms_receipts ( created_at DESC , id ASC );
CREATE INDEX momo_binding_owner ON momo_gateway_bindings ( owner_user_id , status , id );
CREATE INDEX momo_job_ready ON momo_processing_jobs ( state , available_at , raw_sms_id );
CREATE INDEX momo_transaction_page ON momo_transactions ( created_at , id );
CREATE UNIQUE INDEX one_payment_per_intent ON payments ( intent_id ) WHERE intent_id IS NOT NULL;
CREATE INDEX auth_google_flows_expiry ON auth_google_flows ( expires_at );
CREATE INDEX admin_email_otp_user ON admin_email_otp_challenges ( user_id , created_at DESC );
CREATE INDEX admin_email_otp_expiry ON admin_email_otp_challenges ( expires_at );
CREATE UNIQUE INDEX admin_users_email_casefold ON app.admin_users(lower(email));
CREATE FUNCTION private.trg_audit_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_audit';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER audit_no_update BEFORE UPDATE ON app.audit_log FOR EACH ROW EXECUTE FUNCTION private.trg_audit_no_update();
CREATE FUNCTION private.trg_audit_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_audit';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON app.audit_log FOR EACH ROW EXECUTE FUNCTION private.trg_audit_no_delete();
CREATE FUNCTION private.trg_ledger_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_ledger';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER ledger_no_update BEFORE UPDATE ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION private.trg_ledger_no_update();
CREATE FUNCTION private.trg_ledger_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_ledger';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER ledger_no_delete BEFORE DELETE ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION private.trg_ledger_no_delete();
CREATE FUNCTION private.trg_evidence_no_rewrite() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_evidence';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER evidence_no_rewrite BEFORE UPDATE OF object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,amount_minor,currency,observed_at ON app.payment_evidence FOR EACH ROW EXECUTE FUNCTION private.trg_evidence_no_rewrite();
CREATE FUNCTION private.trg_evidence_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_financial_evidence';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER evidence_no_delete BEFORE DELETE ON app.payment_evidence FOR EACH ROW EXECUTE FUNCTION private.trg_evidence_no_delete();
CREATE FUNCTION private.trg_reversal_matches() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . reverses_entry_id IS NOT NULL), false) THEN RETURN NEW; END IF;
  IF NOT EXISTS ( SELECT 1 FROM ledger_entries e WHERE e . id = NEW . reverses_entry_id AND e . payment_id = NEW . payment_id AND e . collection_id = NEW . collection_id AND e . member_id IS NOT DISTINCT FROM NEW . member_id AND e . currency = NEW . currency AND e . amount_minor = - NEW . amount_minor AND e . evidence_id = NEW . evidence_id AND e . kind = 'contribution' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='invalid_reversal'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER reversal_matches BEFORE INSERT ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION private.trg_reversal_matches();
CREATE FUNCTION private.trg_receipt_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_receipt';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER receipt_no_update BEFORE UPDATE ON app.request_receipts FOR EACH ROW EXECUTE FUNCTION private.trg_receipt_no_update();
CREATE FUNCTION private.trg_receipt_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_request_receipt';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER receipt_no_delete BEFORE DELETE ON app.request_receipts FOR EACH ROW EXECUTE FUNCTION private.trg_receipt_no_delete();
CREATE FUNCTION private.trg_auth_mfa_factor_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_mfa_factor';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_mfa_factor_identity BEFORE UPDATE OF id,user_id,friendly_name,secret_ciphertext,created_at,enrollment_session_id ON app.auth_mfa_factors FOR EACH ROW EXECUTE FUNCTION private.trg_auth_mfa_factor_identity();
CREATE FUNCTION private.trg_auth_mfa_factor_final() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((OLD . status = 'revoked'), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='mfa_revocation_is_final';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_mfa_factor_final BEFORE UPDATE ON app.auth_mfa_factors FOR EACH ROW EXECUTE FUNCTION private.trg_auth_mfa_factor_final();
CREATE FUNCTION private.trg_auth_mfa_counter_monotonic() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((OLD . last_totp_counter IS NOT NULL AND ( NEW . last_totp_counter IS NULL OR NEW . last_totp_counter <= OLD . last_totp_counter )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='mfa_code_replay';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_mfa_counter_monotonic BEFORE UPDATE OF last_totp_counter ON app.auth_mfa_factors FOR EACH ROW EXECUTE FUNCTION private.trg_auth_mfa_counter_monotonic();
CREATE FUNCTION private.trg_auth_mfa_claim_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_mfa_claim';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_mfa_claim_no_update BEFORE UPDATE ON app.auth_mfa_claims FOR EACH ROW EXECUTE FUNCTION private.trg_auth_mfa_claim_no_update();
CREATE FUNCTION private.trg_auth_mfa_claim_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_mfa_claim';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER auth_mfa_claim_no_delete BEFORE DELETE ON app.auth_mfa_claims FOR EACH ROW EXECUTE FUNCTION private.trg_auth_mfa_claim_no_delete();
CREATE FUNCTION private.trg_auth_mfa_verified_session() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . assurance_level = 2 AND NOT EXISTS ( SELECT 1 FROM auth_mfa_claims c JOIN auth_mfa_factors f ON f . id = c . factor_id WHERE c . session_id = NEW . id AND c . factor_id = NEW . mfa_factor_id AND c . user_id = NEW . user_id AND c . verified_at = NEW . mfa_at AND f . status = 'verified' AND f . last_totp_counter = c . totp_counter )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='verified_mfa_claim_required';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_mfa_verified_session BEFORE UPDATE OF assurance_level,mfa_at,mfa_factor_id ON app.auth_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_auth_mfa_verified_session();
CREATE FUNCTION private.trg_auth_verification_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_auth_verification';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_verification_no_update BEFORE UPDATE ON app.auth_otp_verifications FOR EACH ROW EXECUTE FUNCTION private.trg_auth_verification_no_update();
CREATE FUNCTION private.trg_auth_verification_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_auth_verification';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER auth_verification_no_delete BEFORE DELETE ON app.auth_otp_verifications FOR EACH ROW EXECUTE FUNCTION private.trg_auth_verification_no_delete();
CREATE FUNCTION private.trg_auth_session_identity_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_session_identity';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_session_identity_no_update BEFORE UPDATE OF id,user_id,surface,auth_at,created_at,expires_at ON app.auth_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_auth_session_identity_no_update();
CREATE FUNCTION private.trg_auth_session_no_unrevoke() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((OLD . revoked_at IS NOT NULL AND ( NEW . revoked_at IS DISTINCT FROM OLD . revoked_at OR NEW . revocation_reason IS DISTINCT FROM OLD . revocation_reason )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='session_revocation_is_final';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_session_no_unrevoke BEFORE UPDATE OF revoked_at,revocation_reason ON app.auth_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_auth_session_no_unrevoke();
CREATE FUNCTION private.trg_mutation_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN users u ON u . id = s . user_id WHERE s . id = NEW . session_id AND s . user_id = NEW . user_id AND s . revoked_at IS NULL AND s . expires_at > NEW . now_seconds AND u . access_status = 'active' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='session_changed'; END IF;
  IF NEW . fresh_seconds IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM auth_sessions s WHERE s . id = NEW . session_id AND ( CASE WHEN s . assurance_level = 2 THEN s . mfa_at ELSE s . auth_at END ) >= NEW . now_seconds - NEW . fresh_seconds ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='fresh_auth_required'; END IF;
  IF NEW . minimum_assurance IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN auth_mfa_factors f ON f . id = s . mfa_factor_id AND f . status = 'verified' WHERE s . id = NEW . session_id AND s . assurance_level >= NEW . minimum_assurance AND s . mfa_at = NEW . expected_mfa_at AND s . mfa_at >= NEW . now_seconds - 300 AND s . mfa_factor_id IS NOT NULL ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='mfa_required'; END IF;
  IF NEW . permission IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN admin_grants g ON g . user_id = s . user_id WHERE s . id = NEW . session_id AND s . surface = 'admin' AND g . permission = NEW . permission ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='permission_denied'; END IF;
  IF NEW . collection_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM memberships m JOIN collections c ON c . id = m . collection_id WHERE m . collection_id = NEW . collection_id AND m . user_id = NEW . user_id AND m . active = 1 AND c . status = 'active' AND ( NEW . required_group_role IS NULL OR m . role = NEW . required_group_role OR ( NEW . required_group_role = 'admin' AND m . role = 'owner' ) ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='group_access_denied'; END IF;
  IF NEW . invite_collection_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM collections c WHERE c . id = NEW . invite_collection_id AND c . status = 'active' AND c . share_code_hash = NEW . expected_share_hash AND c . share_code_version = NEW . expected_share_version ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='invitation_changed'; END IF;
  IF NEW . recipient_user_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM memberships m JOIN users u ON u . id = m . user_id WHERE m . user_id = NEW . recipient_user_id AND m . collection_id = NEW . recipient_collection_id AND m . active = 1 AND u . access_status = 'active' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='recipient_changed'; END IF;
  IF NEW . expected_preference_revision IS NOT NULL AND coalesce ( ( SELECT revision FROM notification_preferences WHERE user_id = NEW . user_id ) , 1 ) != NEW . expected_preference_revision THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='stale_preferences'; END IF;
  IF NEW . expected_collection_revision IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM collections c WHERE c . id = NEW . collection_id AND c . revision = NEW . expected_collection_revision ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='stale_collection'; END IF;
  IF NEW . expected_payment_revision IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM payments p WHERE p . id = NEW . payment_id AND p . revision = NEW . expected_payment_revision ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='stale_payment'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER mutation_authority BEFORE INSERT ON app.mutation_guards FOR EACH ROW EXECUTE FUNCTION private.trg_mutation_authority();
CREATE FUNCTION private.trg_privacy_submission_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM deletion_requests r WHERE r . id = NEW . request_id AND r . user_id = NEW . user_id ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_request_conflict'; END IF;
  IF ( SELECT count ( * ) FROM privacy_submissions WHERE request_id = NEW . request_id ) >= 32 THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_request_submission_limit'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_submission_admission BEFORE INSERT ON app.privacy_submissions FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_submission_admission();
CREATE FUNCTION private.trg_privacy_submissions_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_privacy_submission';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_submissions_no_update BEFORE UPDATE ON app.privacy_submissions FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_submissions_no_update();
CREATE FUNCTION private.trg_privacy_submissions_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_privacy_submission';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_submissions_no_delete BEFORE DELETE ON app.privacy_submissions FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_submissions_no_delete();
CREATE FUNCTION private.trg_privacy_intake_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_privacy_intake';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_intake_no_update BEFORE UPDATE ON app.deletion_requests FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_intake_no_update();
CREATE FUNCTION private.trg_privacy_intake_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_privacy_intake';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_intake_no_delete BEFORE DELETE ON app.deletion_requests FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_intake_no_delete();
CREATE FUNCTION private.trg_privacy_intake_no_erasure() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . status != 'received'), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_policy_authority_unavailable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_intake_no_erasure BEFORE INSERT ON app.deletion_requests FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_intake_no_erasure();
CREATE FUNCTION private.trg_privacy_claim_binding() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM privacy_review_heads h WHERE h . request_id = NEW . request_id AND h . revision = NEW . expected_revision AND h . fence = NEW . fence - 1 AND h . state != 'blocked' AND ( h . latest_claim_id IS NULL OR EXISTS ( SELECT 1 FROM privacy_review_claims old WHERE old . claim_id = h . latest_claim_id AND old . expires_at <= NEW . claimed_at ) ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_review_source_changed'; END IF;
  IF ( SELECT count ( * ) FROM privacy_review_claims WHERE request_id = NEW . request_id ) >= 32 THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_review_claim_limit'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_claim_binding BEFORE INSERT ON app.privacy_review_claims FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_claim_binding();
CREATE FUNCTION private.trg_privacy_outcome_binding() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM privacy_review_claims c JOIN privacy_review_heads h ON h . request_id = c . request_id WHERE c . claim_id = NEW . claim_id AND c . request_id = NEW . request_id AND c . actor_id = NEW . actor_id AND c . originating_session_id = NEW . originating_session_id AND c . fence = NEW . fence AND c . fence = h . fence AND h . state = 'claim_active' AND h . latest_claim_id = c . claim_id AND h . revision = c . revision AND NEW . revision = h . revision + 1 AND c . claimed_at <= NEW . recorded_at AND c . expires_at > NEW . recorded_at ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_review_claim_stale'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_outcome_binding BEFORE INSERT ON app.privacy_review_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_outcome_binding();
CREATE FUNCTION private.trg_privacy_review_head_binding() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NEW . request_id IS DISTINCT FROM OLD . request_id OR NEW . created_at IS DISTINCT FROM OLD . created_at OR NEW . updated_at < OLD . updated_at OR OLD . state = 'blocked' THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_privacy_review_head'; END IF;
  IF NOT ( ( NEW . state = 'claim_active' AND NEW . revision = OLD . revision + 1 AND NEW . fence = OLD . fence + 1 AND NEW . last_outcome_id IS NULL AND EXISTS ( SELECT 1 FROM privacy_review_claims c WHERE c . claim_id = NEW . latest_claim_id AND c . request_id = NEW . request_id AND c . expected_revision = OLD . revision AND c . revision = NEW . revision AND c . fence = NEW . fence AND c . claimed_at = NEW . updated_at ) ) OR ( NEW . state = 'blocked' AND OLD . state = 'claim_active' AND NEW . revision = OLD . revision + 1 AND NEW . fence = OLD . fence AND NEW . latest_claim_id = OLD . latest_claim_id AND EXISTS ( SELECT 1 FROM privacy_review_outcomes o WHERE o . outcome_request_id = NEW . last_outcome_id AND o . request_id = NEW . request_id AND o . claim_id = NEW . latest_claim_id AND o . revision = NEW . revision AND o . fence = NEW . fence AND o . recorded_at = NEW . updated_at ) ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_review_revision_invalid'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_review_head_binding BEFORE UPDATE ON app.privacy_review_heads FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_review_head_binding();
CREATE FUNCTION private.trg_privacy_review_head_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_privacy_review_head';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_review_head_no_delete BEFORE DELETE ON app.privacy_review_heads FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_review_head_no_delete();
CREATE FUNCTION private.trg_privacy_claim_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_privacy_review_claim';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_claim_no_update BEFORE UPDATE ON app.privacy_review_claims FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_claim_no_update();
CREATE FUNCTION private.trg_privacy_claim_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_privacy_review_claim';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_claim_no_delete BEFORE DELETE ON app.privacy_review_claims FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_claim_no_delete();
CREATE FUNCTION private.trg_privacy_outcome_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_privacy_review_outcome';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_outcome_no_update BEFORE UPDATE ON app.privacy_review_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_outcome_no_update();
CREATE FUNCTION private.trg_privacy_outcome_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_privacy_review_outcome';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_outcome_no_delete BEFORE DELETE ON app.privacy_review_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_outcome_no_delete();
CREATE FUNCTION private.trg_native_consent_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN users u ON u . id = s . user_id WHERE s . id = NEW . session_id AND s . user_id = NEW . user_id AND s . surface = 'member' AND s . revoked_at IS NULL AND s . expires_at > NEW . created_seconds AND u . access_status = 'active' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_session_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_consent_authority BEFORE INSERT ON app.native_consents FOR EACH ROW EXECUTE FUNCTION private.trg_native_consent_authority();
CREATE FUNCTION private.trg_native_reservation_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN users u ON u . id = s . user_id WHERE s . id = NEW . session_id AND s . user_id = NEW . user_id AND s . surface = 'member' AND s . revoked_at IS NULL AND s . expires_at > NEW . created_seconds AND u . access_status = 'active' AND u . phone = NEW . verified_phone AND u . country_code = 'RW' AND u . currency_code = 'RWF' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_session_changed'; END IF;
  IF NOT EXISTS ( SELECT 1 FROM native_consents c WHERE c . id = ( SELECT max ( id ) FROM native_consents WHERE user_id = NEW . user_id ) AND c . session_id = NEW . session_id AND c . enabled = 1 AND c . receiver_hash = NEW . receiver_hash AND c . created_seconds BETWEEN NEW . created_seconds - 600 AND NEW . created_seconds ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_consent_required'; END IF;
  IF ( SELECT count ( * ) FROM native_reservations WHERE user_id = NEW . user_id AND created_seconds >= NEW . created_seconds - 3600 ) >= NEW . actor_hour_limit THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_actor_budget'; END IF;
  IF ( SELECT count ( * ) FROM native_reservations WHERE project_id = NEW . project_id AND created_seconds >= CAST ( NEW . created_seconds / 86400 AS BIGINT ) * 86400 ) >= NEW . project_day_limit THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_project_budget'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_reservation_authority BEFORE INSERT ON app.native_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_native_reservation_authority();
CREATE FUNCTION private.trg_native_phase_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM native_reservations r JOIN auth_sessions s ON s . id = r . session_id JOIN users u ON u . id = r . user_id WHERE r . id = NEW . reservation_id AND r . expires_seconds > NEW . started_seconds AND s . revoked_at IS NULL AND s . expires_at > NEW . started_seconds AND u . access_status = 'active' AND u . phone = r . verified_phone AND ( ( NEW . phase = 'oauth' AND r . state = 'reserved' ) OR ( NEW . phase = 'decode' AND r . state = 'oauth_started' ) ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_dispatch_denied'; END IF;
  IF NOT EXISTS ( SELECT 1 FROM native_reservations r JOIN native_consents c ON c . user_id = r . user_id WHERE r . id = NEW . reservation_id AND c . id = ( SELECT max ( id ) FROM native_consents WHERE user_id = r . user_id ) AND c . enabled = 1 AND c . session_id = r . session_id AND c . receiver_hash = r . receiver_hash AND c . created_seconds BETWEEN NEW . started_seconds - 600 AND NEW . started_seconds ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_consent_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_phase_authority BEFORE INSERT ON app.native_phases FOR EACH ROW EXECUTE FUNCTION private.trg_native_phase_authority();
CREATE FUNCTION private.trg_native_phase_state() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE native_reservations SET state = CASE NEW . phase WHEN 'oauth' THEN 'oauth_started' ELSE 'decode_started' END WHERE id = NEW . reservation_id;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_phase_state AFTER INSERT ON app.native_phases FOR EACH ROW EXECUTE FUNCTION private.trg_native_phase_state();
CREATE FUNCTION private.trg_native_capability_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM native_reservations r JOIN auth_sessions s ON s . id = r . session_id JOIN users u ON u . id = r . user_id WHERE r . id = NEW . reservation_id AND r . state = 'decode_started' AND r . expires_seconds > NEW . created_seconds AND r . user_id = NEW . user_id AND r . session_id = NEW . session_id AND r . action = NEW . action AND r . receiver_hash = NEW . receiver_hash AND r . payload_sha256 = NEW . payload_sha256 AND r . verified_phone = NEW . verified_phone AND s . revoked_at IS NULL AND s . expires_at > NEW . created_seconds AND u . access_status = 'active' AND u . phone = NEW . verified_phone ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_completion_denied'; END IF;
  IF NOT EXISTS ( SELECT 1 FROM native_consents c WHERE c . id = ( SELECT max ( id ) FROM native_consents WHERE user_id = NEW . user_id ) AND c . session_id = NEW . session_id AND c . enabled = 1 AND c . receiver_hash = NEW . receiver_hash AND c . created_seconds BETWEEN NEW . created_seconds - 600 AND NEW . created_seconds ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_consent_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_capability_authority BEFORE INSERT ON app.native_capabilities FOR EACH ROW EXECUTE FUNCTION private.trg_native_capability_authority();
CREATE FUNCTION private.trg_native_claim_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NEW . claimed_seconds NOT BETWEEN unixepoch ( ) - 5 AND unixepoch ( ) + 5 THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_claim_expired'; END IF;
  IF NOT EXISTS ( SELECT 1 FROM native_capabilities c JOIN native_completions d ON d . capability_id = c . id JOIN auth_sessions s ON s . id = c . session_id JOIN users u ON u . id = c . user_id WHERE c . id = NEW . capability_id AND c . user_id = NEW . user_id AND c . session_id = NEW . session_id AND c . action = NEW . action AND c . payload_sha256 = NEW . payload_sha256 AND c . receiver_hash = NEW . receiver_hash AND c . expires_seconds > greatest ( NEW . claimed_seconds , unixepoch ( ) ) AND s . revoked_at IS NULL AND s . expires_at > greatest ( NEW . claimed_seconds , unixepoch ( ) ) AND u . access_status = 'active' AND u . phone = c . verified_phone ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_capability_denied'; END IF;
  IF NOT EXISTS ( SELECT 1 FROM native_consents c WHERE c . id = ( SELECT max ( id ) FROM native_consents WHERE user_id = NEW . user_id ) AND c . session_id = NEW . session_id AND c . enabled = 1 AND c . receiver_hash = NEW . receiver_hash AND c . created_seconds BETWEEN NEW . claimed_seconds - 600 AND NEW . claimed_seconds ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_consent_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_claim_authority BEFORE INSERT ON app.native_capability_claims FOR EACH ROW EXECUTE FUNCTION private.trg_native_claim_authority();
CREATE FUNCTION private.trg_native_reservation_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_reservation_identity BEFORE UPDATE OF id,user_id,session_id,nonce,action,request_hash,token_sha256,receiver_hash,verified_phone,payload_sha256,payload_ciphertext,policy_sha256,approval_id,approval_evidence_sha256,project_id,created_seconds,expires_seconds,actor_hour_limit,project_day_limit ON app.native_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_native_reservation_identity();
CREATE FUNCTION private.trg_native_reservation_state() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NOT ( ( OLD . state = 'reserved' AND NEW . state IN ( 'oauth_started' , 'ambiguous' , 'rejected' ) ) OR ( OLD . state = 'oauth_started' AND NEW . state IN ( 'decode_started' , 'ambiguous' , 'rejected' ) ) OR ( OLD . state = 'decode_started' AND NEW . state IN ( 'completed' , 'ambiguous' , 'rejected' ) ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_state_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_reservation_state BEFORE UPDATE OF state ON app.native_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_native_reservation_state();
CREATE FUNCTION private.trg_native_phases_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_phases_immutable BEFORE UPDATE ON app.native_phases FOR EACH ROW EXECUTE FUNCTION private.trg_native_phases_immutable();
CREATE FUNCTION private.trg_native_phases_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER native_phases_no_delete BEFORE DELETE ON app.native_phases FOR EACH ROW EXECUTE FUNCTION private.trg_native_phases_no_delete();
CREATE FUNCTION private.trg_native_capabilities_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_capabilities_immutable BEFORE UPDATE ON app.native_capabilities FOR EACH ROW EXECUTE FUNCTION private.trg_native_capabilities_immutable();
CREATE FUNCTION private.trg_native_capabilities_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER native_capabilities_no_delete BEFORE DELETE ON app.native_capabilities FOR EACH ROW EXECUTE FUNCTION private.trg_native_capabilities_no_delete();
CREATE FUNCTION private.trg_native_completions_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_completions_immutable BEFORE UPDATE ON app.native_completions FOR EACH ROW EXECUTE FUNCTION private.trg_native_completions_immutable();
CREATE FUNCTION private.trg_native_completions_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER native_completions_no_delete BEFORE DELETE ON app.native_completions FOR EACH ROW EXECUTE FUNCTION private.trg_native_completions_no_delete();
CREATE FUNCTION private.trg_native_claims_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER native_claims_immutable BEFORE UPDATE ON app.native_capability_claims FOR EACH ROW EXECUTE FUNCTION private.trg_native_claims_immutable();
CREATE FUNCTION private.trg_native_claims_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='native_evidence_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER native_claims_no_delete BEFORE DELETE ON app.native_capability_claims FOR EACH ROW EXECUTE FUNCTION private.trg_native_claims_no_delete();
CREATE FUNCTION private.trg_roster_upload_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN users u ON u . id = s . user_id JOIN admin_grants g ON g . user_id = u . id JOIN auth_mfa_factors f ON f . id = s . mfa_factor_id WHERE s . id = NEW . session_id AND s . user_id = NEW . user_id AND s . surface = 'admin' AND s . revoked_at IS NULL AND s . expires_at > unixepoch ( ) AND s . assurance_level = 2 AND s . mfa_at >= unixepoch ( ) - 300 AND f . status = 'verified' AND u . access_status = 'active' AND g . permission = 'roster.import' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_session_changed'; END IF;
  IF ( SELECT count ( * ) FROM roster_imports WHERE user_id = NEW . user_id AND created_seconds >= unixepoch ( ) - 86400 ) >= 20 THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_import_limit'; END IF;
  IF NEW . collection_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM collections WHERE id = NEW . collection_id AND status = 'active' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_collection_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_upload_authority BEFORE INSERT ON app.roster_imports FOR EACH ROW EXECUTE FUNCTION private.trg_roster_upload_authority();
CREATE FUNCTION private.trg_roster_current_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NEW . now_seconds NOT BETWEEN unixepoch ( ) - 5 AND unixepoch ( ) + 5 THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_current_dispatch_expired'; END IF;
  IF NOT EXISTS ( SELECT 1 FROM roster_imports i JOIN auth_sessions s ON s . id = i . session_id JOIN users u ON u . id = i . user_id JOIN admin_grants g ON g . user_id = u . id JOIN auth_mfa_factors f ON f . id = s . mfa_factor_id WHERE i . id = NEW . import_id AND i . user_id = NEW . actor_user_id AND i . session_id = NEW . session_id AND i . expires_seconds > greatest ( NEW . now_seconds , unixepoch ( ) ) AND i . state = NEW . expected_state AND i . latest_revision_id IS NOT DISTINCT FROM NEW . expected_latest_revision AND s . surface = 'admin' AND s . revoked_at IS NULL AND s . expires_at > greatest ( NEW . now_seconds , unixepoch ( ) ) AND s . assurance_level = 2 AND s . mfa_at >= unixepoch ( ) - 300 AND f . status = 'verified' AND u . access_status = 'active' AND g . permission = NEW . permission ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_session_or_revision_changed'; END IF;
  IF NEW . revision_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM roster_revisions r WHERE r . id = NEW . revision_id AND r . import_id = NEW . import_id AND r . human_reviewed = 1 ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_review_required'; END IF;
  IF NEW . collection_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM collections c WHERE c . id = NEW . collection_id AND c . status = 'active' AND c . revision = NEW . expected_collection_revision ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_collection_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_current_authority BEFORE INSERT ON app.roster_commit_guards FOR EACH ROW EXECUTE FUNCTION private.trg_roster_current_authority();
CREATE FUNCTION private.trg_roster_processing_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM roster_imports i JOIN auth_sessions s ON s . id = i . session_id JOIN users u ON u . id = i . user_id JOIN admin_grants g ON g . user_id = u . id WHERE i . id = NEW . import_id AND i . user_id = NEW . actor_user_id AND i . session_id = NEW . session_id AND i . source_sha256 = NEW . source_sha256 AND i . object_sha256 = NEW . source_object_sha256 AND i . state = 'processing' AND i . expires_seconds > NEW . created_seconds AND s . revoked_at IS NULL AND s . expires_at > NEW . created_seconds AND s . surface = 'admin' AND u . access_status = 'active' AND g . permission = 'roster.import' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_processing_denied'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_processing_authority BEFORE INSERT ON app.roster_processing_records FOR EACH ROW EXECUTE FUNCTION private.trg_roster_processing_authority();
CREATE FUNCTION private.trg_roster_dispatch_authority() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM roster_processing_records p JOIN roster_imports i ON i . id = p . import_id JOIN auth_sessions s ON s . id = p . session_id JOIN users u ON u . id = p . actor_user_id JOIN admin_grants g ON g . user_id = u . id WHERE p . id = NEW . processing_id AND p . expires_seconds > NEW . started_seconds AND i . state = 'processing' AND i . expires_seconds > NEW . started_seconds AND s . revoked_at IS NULL AND s . expires_at > NEW . started_seconds AND u . access_status = 'active' AND g . permission = 'roster.import' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_dispatch_denied'; END IF;
  IF NEW . phase = 'extract' AND NOT EXISTS ( SELECT 1 FROM roster_dispatch_phases WHERE processing_id = NEW . processing_id AND phase = 'decode' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_decoder_lineage_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_dispatch_authority BEFORE INSERT ON app.roster_dispatch_phases FOR EACH ROW EXECUTE FUNCTION private.trg_roster_dispatch_authority();
CREATE FUNCTION private.trg_roster_source_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_source_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_source_immutable BEFORE UPDATE OF id,user_id,session_id,request_id,collection_id,request_sha256,source_sha256,object_sha256,source_object_key,source_size,source_kind,source_receipt_json,source_ciphertext,created_seconds,expires_seconds ON app.roster_imports FOR EACH ROW EXECUTE FUNCTION private.trg_roster_source_immutable();
CREATE FUNCTION private.trg_roster_revisions_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_revision_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_revisions_immutable BEFORE UPDATE ON app.roster_revisions FOR EACH ROW EXECUTE FUNCTION private.trg_roster_revisions_immutable();
CREATE FUNCTION private.trg_roster_revisions_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_revision_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER roster_revisions_no_delete BEFORE DELETE ON app.roster_revisions FOR EACH ROW EXECUTE FUNCTION private.trg_roster_revisions_no_delete();
CREATE FUNCTION private.trg_roster_processing_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_processing_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_processing_immutable BEFORE UPDATE ON app.roster_processing_records FOR EACH ROW EXECUTE FUNCTION private.trg_roster_processing_immutable();
CREATE FUNCTION private.trg_roster_processing_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_processing_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER roster_processing_no_delete BEFORE DELETE ON app.roster_processing_records FOR EACH ROW EXECUTE FUNCTION private.trg_roster_processing_no_delete();
CREATE FUNCTION private.trg_roster_dispatch_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_dispatch_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_dispatch_immutable BEFORE UPDATE ON app.roster_dispatch_phases FOR EACH ROW EXECUTE FUNCTION private.trg_roster_dispatch_immutable();
CREATE FUNCTION private.trg_roster_dispatch_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_dispatch_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER roster_dispatch_no_delete BEFORE DELETE ON app.roster_dispatch_phases FOR EACH ROW EXECUTE FUNCTION private.trg_roster_dispatch_no_delete();
CREATE FUNCTION private.trg_roster_intents_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_intent_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER roster_intents_immutable BEFORE UPDATE ON app.roster_intents FOR EACH ROW EXECUTE FUNCTION private.trg_roster_intents_immutable();
CREATE FUNCTION private.trg_roster_intents_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='roster_intent_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER roster_intents_no_delete BEFORE DELETE ON app.roster_intents FOR EACH ROW EXECUTE FUNCTION private.trg_roster_intents_no_delete();
CREATE FUNCTION private.trg_admin_account_audit_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_admin_account_audit';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_account_audit_no_update BEFORE UPDATE ON app.admin_account_audit FOR EACH ROW EXECUTE FUNCTION private.trg_admin_account_audit_no_update();
CREATE FUNCTION private.trg_admin_account_audit_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_admin_account_audit';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_account_audit_no_delete BEFORE DELETE ON app.admin_account_audit FOR EACH ROW EXECUTE FUNCTION private.trg_admin_account_audit_no_delete();
CREATE FUNCTION private.trg_admin_principal_link_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='explicit_principal_link_required';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_principal_link_immutable BEFORE UPDATE ON app.admin_principal_links FOR EACH ROW EXECUTE FUNCTION private.trg_admin_principal_link_immutable();
CREATE FUNCTION private.trg_admin_role_capabilities_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='approved_role_capabilities_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_role_capabilities_no_update BEFORE UPDATE ON app.admin_account_role_capabilities FOR EACH ROW EXECUTE FUNCTION private.trg_admin_role_capabilities_no_update();
CREATE FUNCTION private.trg_admin_role_capabilities_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='approved_role_capabilities_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_role_capabilities_no_delete BEFORE DELETE ON app.admin_account_role_capabilities FOR EACH ROW EXECUTE FUNCTION private.trg_admin_role_capabilities_no_delete();
CREATE FUNCTION private.trg_admin_link_grants() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  INSERT INTO admin_grants ( user_id , permission , granted_by , granted_at ) SELECT NEW . user_id , c . permission , 'admin-account:' || u . id , strftime ( '%Y-%m-%dT%H:%M:%fZ' , 'now' ) FROM admin_users u JOIN admin_account_role_capabilities c ON c . role = u . role WHERE u . id = NEW . admin_user_id AND u . status = 'active' ON CONFLICT DO NOTHING;
  INSERT INTO admin_role_assignments ( user_id , role , granted_by , granted_at ) SELECT NEW . user_id , ( CASE WHEN u . role = 'owner' THEN 'platform_owner' ELSE 'operator' END ) , 'admin-account:' || u . id , strftime ( '%Y-%m-%dT%H:%M:%fZ' , 'now' ) FROM admin_users u WHERE u . id = NEW . admin_user_id AND u . status = 'active' ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_link_grants AFTER INSERT ON app.admin_principal_links FOR EACH ROW EXECUTE FUNCTION private.trg_admin_link_grants();
CREATE FUNCTION private.trg_admin_account_authority_changed() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . status != OLD . status OR NEW . role != OLD . role OR NEW . auth_version != OLD . auth_version), false) THEN RETURN NEW; END IF;
  UPDATE auth_sessions SET revoked_at = unixepoch ( ) , revocation_reason = 'admin_account_changed' WHERE user_id = ( SELECT user_id FROM admin_principal_links WHERE admin_user_id = NEW . id ) AND surface = 'admin' AND revoked_at IS NULL;
  DELETE FROM admin_sessions WHERE user_id = NEW . id;
  DELETE FROM admin_grants WHERE user_id = ( SELECT user_id FROM admin_principal_links WHERE admin_user_id = NEW . id ) AND granted_by = 'admin-account:' || NEW . id;
  DELETE FROM admin_role_assignments WHERE user_id = ( SELECT user_id FROM admin_principal_links WHERE admin_user_id = NEW . id ) AND granted_by = 'admin-account:' || NEW . id;
  INSERT INTO admin_grants ( user_id , permission , granted_by , granted_at ) SELECT l . user_id , c . permission , 'admin-account:' || NEW . id , strftime ( '%Y-%m-%dT%H:%M:%fZ' , 'now' ) FROM admin_principal_links l JOIN admin_account_role_capabilities c ON c . role = NEW . role WHERE l . admin_user_id = NEW . id AND NEW . status = 'active' ON CONFLICT DO NOTHING;
  INSERT INTO admin_role_assignments ( user_id , role , granted_by , granted_at ) SELECT l . user_id , ( CASE WHEN NEW . role = 'owner' THEN 'platform_owner' ELSE 'operator' END ) , 'admin-account:' || NEW . id , strftime ( '%Y-%m-%dT%H:%M:%fZ' , 'now' ) FROM admin_principal_links l WHERE l . admin_user_id = NEW . id AND NEW . status = 'active' ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_account_authority_changed AFTER UPDATE OF status,role,auth_version ON app.admin_users FOR EACH ROW EXECUTE FUNCTION private.trg_admin_account_authority_changed();
CREATE FUNCTION private.trg_admin_principal_link_revoked() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE auth_sessions SET revoked_at = unixepoch ( ) , revocation_reason = 'admin_principal_unlinked' WHERE user_id = OLD . user_id AND surface = 'admin' AND revoked_at IS NULL;
  DELETE FROM admin_sessions WHERE user_id = OLD . admin_user_id;
  DELETE FROM admin_grants WHERE user_id = OLD . user_id AND granted_by = 'admin-account:' || OLD . admin_user_id;
  DELETE FROM admin_role_assignments WHERE user_id = OLD . user_id AND granted_by = 'admin-account:' || OLD . admin_user_id;
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_principal_link_revoked BEFORE DELETE ON app.admin_principal_links FOR EACH ROW EXECUTE FUNCTION private.trg_admin_principal_link_revoked();
CREATE FUNCTION private.trg_admin_cookie_session_bound() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM admin_users a JOIN admin_principal_links l ON l . admin_user_id = a . id JOIN users u ON u . id = l . user_id JOIN auth_sessions s ON s . user_id = u . id WHERE a . id = NEW . user_id AND a . status = 'active' AND a . auth_version = NEW . auth_version AND u . access_status = 'active' AND s . id = NEW . auth_session_id AND s . surface = 'admin' AND s . auth_at = NEW . created_at AND s . revoked_at IS NULL AND s . expires_at = NEW . expires_at AND NEW . issued_assurance_level = 1 ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='admin_session_link_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_cookie_session_bound BEFORE INSERT ON app.admin_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_admin_cookie_session_bound();
CREATE FUNCTION private.trg_admin_cookie_mfa_bound() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . issued_assurance_level = 2), false) THEN RETURN NEW; END IF;
  IF NOT EXISTS ( SELECT 1 FROM auth_sessions s JOIN auth_mfa_factors f ON f . id = s . mfa_factor_id WHERE s . id = NEW . auth_session_id AND s . assurance_level = 2 AND s . mfa_at = NEW . issued_mfa_at AND s . mfa_factor_id = NEW . issued_mfa_factor_id AND s . revoked_at IS NULL AND s . expires_at > unixepoch ( ) AND f . status = 'verified' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='real_mfa_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_cookie_mfa_bound BEFORE UPDATE OF issued_assurance_level,issued_mfa_at,issued_mfa_factor_id ON app.admin_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_admin_cookie_mfa_bound();
CREATE FUNCTION private.trg_admin_cookie_session_revoked() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE auth_sessions SET revoked_at = unixepoch ( ) , revocation_reason = 'admin_cookie_session_ended' WHERE id = OLD . auth_session_id AND revoked_at IS NULL;
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_cookie_session_revoked AFTER DELETE ON app.admin_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_admin_cookie_session_revoked();
CREATE FUNCTION private.trg_admin_bridge_request_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_admin_bridge_request';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_bridge_request_no_update BEFORE UPDATE ON app.admin_bridge_requests FOR EACH ROW EXECUTE FUNCTION private.trg_admin_bridge_request_no_update();
CREATE FUNCTION private.trg_admin_bridge_request_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_admin_bridge_request';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_bridge_request_no_delete BEFORE DELETE ON app.admin_bridge_requests FOR EACH ROW EXECUTE FUNCTION private.trg_admin_bridge_request_no_delete();
CREATE FUNCTION private.trg_admin_bridge_reconciliation_snapshot_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_reconciliation_snapshot';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_bridge_reconciliation_snapshot_no_update BEFORE UPDATE ON app.admin_bridge_reconciliation_snapshots FOR EACH ROW EXECUTE FUNCTION private.trg_admin_bridge_reconciliation_snapshot_no_update();
CREATE FUNCTION private.trg_admin_bridge_reconciliation_snapshot_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_reconciliation_snapshot';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_bridge_reconciliation_snapshot_no_delete BEFORE DELETE ON app.admin_bridge_reconciliation_snapshots FOR EACH ROW EXECUTE FUNCTION private.trg_admin_bridge_reconciliation_snapshot_no_delete();
CREATE FUNCTION private.trg_admin_owner_bootstrap_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF EXISTS ( SELECT 1 FROM admin_users WHERE role = 'owner' ) OR length ( NEW . approval_reference ) < 8 OR ( NEW . password_hash !~ '^pbkdf2\-sha256\$600000\$.*$' ) OR EXISTS ( SELECT 1 FROM users WHERE id = NEW . principal_user_id ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='explicit_fresh_owner_bootstrap_required'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_owner_bootstrap_admission BEFORE INSERT ON app.admin_owner_bootstrap_claims FOR EACH ROW EXECUTE FUNCTION private.trg_admin_owner_bootstrap_admission();
CREATE FUNCTION private.trg_admin_owner_bootstrap_apply() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  INSERT INTO users ( id , public_id , full_name , member_type , created_at , updated_at ) VALUES ( NEW . principal_user_id , ( SELECT printf ( '%06d' , min ( candidate ) ) FROM ( SELECT 0 AS candidate UNION ALL SELECT CAST ( public_id AS BIGINT ) + 1 FROM users WHERE public_id != '999999' ) c WHERE candidate < 1000000 AND NOT EXISTS ( SELECT 1 FROM users WHERE public_id = printf ( '%06d' , candidate ) ) ) , NEW . display_name , 'operator' , NEW . created_at , NEW . created_at );
  INSERT INTO admin_users ( id , email , role , status , password_hash , display_name , created_at , accepted_at , updated_at ) VALUES ( NEW . admin_user_id , 'info@ikanisa.com' , 'owner' , 'active' , NEW . password_hash , NEW . display_name , NEW . created_seconds , NEW . created_seconds , NEW . created_seconds );
  INSERT INTO admin_principal_links ( admin_user_id , user_id , approved_by , approved_at ) VALUES ( NEW . admin_user_id , NEW . principal_user_id , NEW . approval_reference , NEW . created_at );
  INSERT INTO admin_account_audit ( id , actor_id , subject_id , action , occurred_at ) VALUES ( NEW . operation_id , NEW . admin_user_id , NEW . admin_user_id , 'explicit_owner_bootstrapped' , NEW . created_seconds );
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_owner_bootstrap_apply AFTER INSERT ON app.admin_owner_bootstrap_claims FOR EACH ROW EXECUTE FUNCTION private.trg_admin_owner_bootstrap_apply();
CREATE FUNCTION private.trg_admin_owner_bootstrap_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_owner_bootstrap';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_owner_bootstrap_no_update BEFORE UPDATE ON app.admin_owner_bootstrap_claims FOR EACH ROW EXECUTE FUNCTION private.trg_admin_owner_bootstrap_no_update();
CREATE FUNCTION private.trg_admin_owner_bootstrap_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_owner_bootstrap';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER admin_owner_bootstrap_no_delete BEFORE DELETE ON app.admin_owner_bootstrap_claims FOR EACH ROW EXECUTE FUNCTION private.trg_admin_owner_bootstrap_no_delete();
CREATE FUNCTION private.trg_user_revision_monotonic() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . revision = OLD . revision), false) THEN RETURN NEW; END IF;
  UPDATE users SET revision = revision + 1 WHERE id = NEW . id;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER user_revision_monotonic AFTER UPDATE OF phone,email,full_name,momo_number,momo_pay_code,momo_provider,access_status ON app.users FOR EACH ROW EXECUTE FUNCTION private.trg_user_revision_monotonic();
CREATE FUNCTION private.trg_membership_revision_monotonic() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . revision = OLD . revision), false) THEN RETURN NEW; END IF;
  UPDATE memberships SET revision = revision + 1 WHERE id = NEW . id;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER membership_revision_monotonic AFTER UPDATE OF role,active ON app.memberships FOR EACH ROW EXECUTE FUNCTION private.trg_membership_revision_monotonic();
CREATE FUNCTION private.trg_evidence_route_snapshot_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_evidence';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER evidence_route_snapshot_immutable BEFORE UPDATE OF receiver_network,receiver_display_label ON app.payment_evidence FOR EACH ROW EXECUTE FUNCTION private.trg_evidence_route_snapshot_immutable();
CREATE FUNCTION private.trg_mutation_target_collection() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NEW . target_collection_id IS NOT NULL AND NOT EXISTS ( SELECT 1 FROM collections c WHERE c . id = NEW . target_collection_id AND c . status = 'active' AND ( NEW . expected_target_collection_revision IS NULL OR c . revision = NEW . expected_target_collection_revision ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='stale_collection'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER mutation_target_collection BEFORE INSERT ON app.mutation_guards FOR EACH ROW EXECUTE FUNCTION private.trg_mutation_target_collection();
CREATE FUNCTION private.trg_sms_receipt_source_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_sms_source';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER sms_receipt_source_immutable BEFORE UPDATE OF id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,evidence_level,created_at ON app.sms_receipts FOR EACH ROW EXECUTE FUNCTION private.trg_sms_receipt_source_immutable();
CREATE FUNCTION private.trg_sms_receipt_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_receipt_until_approved_privacy_disposition';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER sms_receipt_retain BEFORE DELETE ON app.sms_receipts FOR EACH ROW EXECUTE FUNCTION private.trg_sms_receipt_retain();
CREATE FUNCTION private.trg_admin_operator_note_target() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF ( NEW . entity_type = 'collection' AND NOT EXISTS ( SELECT 1 FROM collections WHERE id = NEW . entity_id ) ) OR ( NEW . entity_type = 'profile' AND NOT EXISTS ( SELECT 1 FROM users WHERE id = NEW . entity_id ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='operator_note_target_unavailable'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_operator_note_target BEFORE INSERT ON app.admin_operator_notes FOR EACH ROW EXECUTE FUNCTION private.trg_admin_operator_note_target();
CREATE FUNCTION private.trg_privacy_retention_plan_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_retention_plan';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_plan_identity BEFORE UPDATE OF id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds ON app.privacy_retention_plans FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_plan_identity();
CREATE FUNCTION private.trg_privacy_retention_plan_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_retention_plan';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_plan_retain BEFORE DELETE ON app.privacy_retention_plans FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_plan_retain();
CREATE FUNCTION private.trg_privacy_retention_task_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_retention_task';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_task_identity BEFORE UPDATE OF id,plan_id,class_name,action,expected_json ON app.privacy_retention_tasks FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_task_identity();
CREATE FUNCTION private.trg_privacy_retention_task_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_retention_task';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_task_retain BEFORE DELETE ON app.privacy_retention_tasks FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_task_retain();
CREATE FUNCTION private.trg_privacy_retention_claim_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_retention_claim';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_claim_identity BEFORE UPDATE ON app.privacy_retention_claims FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_claim_identity();
CREATE FUNCTION private.trg_privacy_retention_claim_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_retention_claim';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_claim_retain BEFORE DELETE ON app.privacy_retention_claims FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_claim_retain();
CREATE FUNCTION private.trg_privacy_retention_outcome_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_retention_outcome';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_outcome_identity BEFORE UPDATE ON app.privacy_retention_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_outcome_identity();
CREATE FUNCTION private.trg_privacy_retention_outcome_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_retention_outcome';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_outcome_retain BEFORE DELETE ON app.privacy_retention_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_outcome_retain();
CREATE FUNCTION private.trg_privacy_retention_effect_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_retention_effect';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_effect_identity BEFORE UPDATE ON app.privacy_retention_effects FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_effect_identity();
CREATE FUNCTION private.trg_privacy_retention_effect_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_retention_effect';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_effect_retain BEFORE DELETE ON app.privacy_retention_effects FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_effect_retain();
CREATE FUNCTION private.trg_privacy_retention_barrier_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_retention_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_barrier_identity BEFORE UPDATE ON app.privacy_retention_barriers FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_barrier_identity();
CREATE FUNCTION private.trg_privacy_retention_barrier_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retention_barrier_requires_separate_recovery_authority';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_barrier_retain BEFORE DELETE ON app.privacy_retention_barriers FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_barrier_retain();
CREATE FUNCTION private.trg_privacy_retention_no_reactivation() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . access_status = 'active' AND EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . id )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_access_quarantined';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_no_reactivation BEFORE UPDATE OF access_status ON app.users FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_no_reactivation();
CREATE FUNCTION private.trg_privacy_retention_no_new_session() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_access_quarantined';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_no_new_session BEFORE INSERT ON app.auth_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_no_new_session();
CREATE FUNCTION private.trg_privacy_retention_notification_devices_insert() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'notification_devices' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_devices_insert BEFORE INSERT ON app.notification_devices FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_devices_insert();
CREATE FUNCTION private.trg_privacy_retention_notification_devices_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'notification_devices' ) AND g . passed = 1 ) ) OR ( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'notification_devices' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_devices_update BEFORE UPDATE ON app.notification_devices FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_devices_update();
CREATE FUNCTION private.trg_privacy_retention_notification_devices_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'notification_devices' ) AND g . passed = 1 ) )), false) THEN RETURN OLD; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_devices_delete BEFORE DELETE ON app.notification_devices FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_devices_delete();
CREATE FUNCTION private.trg_privacy_retention_notification_preferences_insert() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'notification_preferences' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_preferences_insert BEFORE INSERT ON app.notification_preferences FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_preferences_insert();
CREATE FUNCTION private.trg_privacy_retention_notification_preferences_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'notification_preferences' ) AND g . passed = 1 ) ) OR ( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'notification_preferences' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_preferences_update BEFORE UPDATE ON app.notification_preferences FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_preferences_update();
CREATE FUNCTION private.trg_privacy_retention_notification_preferences_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'notification_preferences' ) AND g . passed = 1 ) )), false) THEN RETURN OLD; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_preferences_delete BEFORE DELETE ON app.notification_preferences FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_preferences_delete();
CREATE FUNCTION private.trg_privacy_retention_notification_events_insert() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'notification_events' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_events_insert BEFORE INSERT ON app.notification_events FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_events_insert();
CREATE FUNCTION private.trg_privacy_retention_notification_events_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'notification_events' ) AND g . passed = 1 ) ) OR ( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'notification_events' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_events_update BEFORE UPDATE ON app.notification_events FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_events_update();
CREATE FUNCTION private.trg_privacy_retention_notification_events_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'notification_events' ) AND g . passed = 1 ) )), false) THEN RETURN OLD; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_notification_events_delete BEFORE DELETE ON app.notification_events FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_notification_events_delete();
CREATE FUNCTION private.trg_privacy_retention_support_requests_insert() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'support_requests' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_support_requests_insert BEFORE INSERT ON app.support_requests FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_support_requests_insert();
CREATE FUNCTION private.trg_privacy_retention_support_requests_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'support_requests' ) AND g . passed = 1 ) ) OR ( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'support_requests' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_support_requests_update BEFORE UPDATE ON app.support_requests FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_support_requests_update();
CREATE FUNCTION private.trg_privacy_retention_support_requests_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'support_requests' ) AND g . passed = 1 ) )), false) THEN RETURN OLD; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_support_requests_delete BEFORE DELETE ON app.support_requests FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_support_requests_delete();
CREATE FUNCTION private.trg_privacy_retention_upload_objects_insert() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'upload_objects' , 'r2:upload_objects' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_upload_objects_insert BEFORE INSERT ON app.upload_objects FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_upload_objects_insert();
CREATE FUNCTION private.trg_privacy_retention_upload_objects_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'upload_objects' , 'r2:upload_objects' ) AND g . passed = 1 ) ) OR ( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = NEW . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = NEW . user_id AND g . class_name IN ( 'upload_objects' , 'r2:upload_objects' ) AND g . passed = 1 ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER privacy_retention_upload_objects_update BEFORE UPDATE ON app.upload_objects FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_upload_objects_update();
CREATE FUNCTION private.trg_privacy_retention_upload_objects_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((( EXISTS ( SELECT 1 FROM privacy_retention_barriers b WHERE b . subject_id = OLD . user_id ) AND NOT EXISTS ( SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p . id = g . plan_id WHERE p . subject_id = OLD . user_id AND g . class_name IN ( 'upload_objects' , 'r2:upload_objects' ) AND g . passed = 1 ) )), false) THEN RETURN OLD; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='privacy_retention_write_barrier';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER privacy_retention_upload_objects_delete BEFORE DELETE ON app.upload_objects FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_retention_upload_objects_delete();
CREATE FUNCTION private.trg_auth_rate_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF length ( NEW . identity_hash ) != 64 OR ( NEW . identity_hash ~ '^.*[^0-9a-f].*$' ) OR json_array_length ( NEW . identity_aliases_json ) > 10 OR ( json_array_length ( NEW . identity_aliases_json ) = 0 AND NEW . identity_key_id != 'legacy-token-hash-v1' ) OR ( NEW . identity_key_id != 'legacy-token-hash-v1' AND NOT EXISTS ( SELECT 1 FROM json_each ( NEW . identity_aliases_json ) WHERE json_extract ( value , '$.key_id' ) = 'legacy-token-hash-v1' ) ) OR EXISTS ( SELECT 1 FROM json_each ( NEW . identity_aliases_json ) e WHERE e . type != 'object' OR ( SELECT count ( * ) FROM json_each ( e . value ) ) != 2 OR json_type ( e . value , '$.key_id' ) IS DISTINCT FROM 'text' OR json_type ( e . value , '$.identity_hash' ) IS DISTINCT FROM 'text' OR length ( json_extract ( e . value , '$.key_id' ) ) NOT BETWEEN 1 AND 128 OR ( substr ( json_extract ( e . value , '$.key_id' ) , 1 , 1 ) !~ '^[A-Za-z0-9]$' ) OR ( json_extract ( e . value , '$.key_id' ) ~ '^.*[^A-Za-z0-9._:-].*$' ) OR length ( json_extract ( e . value , '$.identity_hash' ) ) != 64 OR ( json_extract ( e . value , '$.identity_hash' ) ~ '^.*[^0-9a-f].*$' ) ) OR ( SELECT count ( * ) FROM json_each ( NEW . identity_aliases_json ) ) != ( SELECT count ( DISTINCT json_extract ( value , '$.key_id' ) ) FROM json_each ( NEW . identity_aliases_json ) ) OR ( SELECT count ( * ) FROM json_each ( NEW . identity_aliases_json ) ) != ( SELECT count ( DISTINCT json_extract ( value , '$.identity_hash' ) ) FROM json_each ( NEW . identity_aliases_json ) ) OR ( json_array_length ( NEW . identity_aliases_json ) > 0 AND NOT EXISTS ( SELECT 1 FROM json_each ( NEW . identity_aliases_json ) WHERE json_extract ( value , '$.key_id' ) = NEW . identity_key_id AND json_extract ( value , '$.identity_hash' ) = NEW . identity_hash ) ) OR EXISTS ( SELECT 1 FROM auth_identity_rate_aliases existing JOIN ( SELECT NEW . identity_hash AS identity_hash , NEW . identity_key_id AS key_id UNION SELECT json_extract ( value , '$.identity_hash' ) , json_extract ( value , '$.key_id' ) FROM json_each ( NEW . identity_aliases_json ) ) incoming ON incoming . identity_hash = existing . identity_hash WHERE incoming . key_id != existing . identity_key_id ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='auth_identity_aliases_invalid'; END IF;
  IF ( SELECT count ( DISTINCT request_id ) FROM auth_identity_rate_aliases WHERE identity_hash IN ( SELECT NEW . identity_hash UNION SELECT json_extract ( value , '$.identity_hash' ) FROM json_each ( NEW . identity_aliases_json ) ) AND hourly_window_ends_at > NEW . requested_at ) >= NEW . identity_limit OR COALESCE ( ( SELECT used FROM auth_rate_buckets WHERE bucket_key = NEW . ip_bucket ) , 0 ) >= NEW . ip_limit OR COALESCE ( ( SELECT used FROM auth_rate_buckets WHERE bucket_key = NEW . global_bucket ) , 0 ) >= NEW . global_limit OR EXISTS ( SELECT 1 FROM auth_otp_throttles WHERE identity_hash IN ( SELECT NEW . identity_hash UNION SELECT json_extract ( value , '$.identity_hash' ) FROM json_each ( NEW . identity_aliases_json ) ) AND last_requested_at + NEW . cooldown_seconds > NEW . requested_at ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='auth_rate_limited'; END IF;
  INSERT INTO auth_rate_buckets ( bucket_key , used , window_ends_at ) VALUES ( NEW . identity_bucket , 1 , NEW . hourly_window_ends_at ) ON CONFLICT ( bucket_key ) DO UPDATE SET used = auth_rate_buckets.used + 1;
  INSERT INTO auth_rate_buckets ( bucket_key , used , window_ends_at ) VALUES ( NEW . ip_bucket , 1 , NEW . hourly_window_ends_at ) ON CONFLICT ( bucket_key ) DO UPDATE SET used = auth_rate_buckets.used + 1;
  INSERT INTO auth_rate_buckets ( bucket_key , used , window_ends_at ) VALUES ( NEW . global_bucket , 1 , NEW . daily_window_ends_at ) ON CONFLICT ( bucket_key ) DO UPDATE SET used = auth_rate_buckets.used + 1;
  INSERT INTO auth_otp_throttles ( identity_hash , last_requested_at , identity_key_id ) SELECT incoming . identity_hash , NEW . requested_at , incoming . key_id FROM ( SELECT NEW . identity_hash AS identity_hash , NEW . identity_key_id AS key_id UNION SELECT json_extract ( value , '$.identity_hash' ) , json_extract ( value , '$.key_id' ) FROM json_each ( NEW . identity_aliases_json ) ) incoming WHERE true ON CONFLICT ( identity_hash ) DO UPDATE SET last_requested_at = excluded . last_requested_at;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_rate_admission BEFORE INSERT ON app.auth_rate_claims FOR EACH ROW EXECUTE FUNCTION private.trg_auth_rate_admission();
CREATE FUNCTION private.trg_auth_identity_alias_capture() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  INSERT INTO auth_identity_rate_aliases ( request_id , identity_key_id , identity_hash , requested_at , hourly_window_ends_at ) SELECT NEW . request_id , incoming . key_id , incoming . identity_hash , NEW . requested_at , NEW . hourly_window_ends_at FROM ( SELECT NEW . identity_hash AS identity_hash , NEW . identity_key_id AS key_id UNION SELECT json_extract ( value , '$.identity_hash' ) , json_extract ( value , '$.key_id' ) FROM json_each ( NEW . identity_aliases_json ) ) incoming;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_identity_alias_capture AFTER INSERT ON app.auth_rate_claims FOR EACH ROW EXECUTE FUNCTION private.trg_auth_identity_alias_capture();
CREATE FUNCTION private.trg_auth_identity_alias_supersession() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE auth_otp_challenges SET status = 'superseded' WHERE surface = NEW . surface AND status IN ( 'dispatching' , 'accepted' , 'delivery_unknown' ) AND id IN ( SELECT prior . request_id FROM auth_identity_rate_aliases incoming JOIN auth_identity_rate_aliases prior ON prior . identity_hash = incoming . identity_hash WHERE incoming . request_id = NEW . id );
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_identity_alias_supersession BEFORE INSERT ON app.auth_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_auth_identity_alias_supersession();
CREATE FUNCTION private.trg_auth_identity_alias_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='auth_identity_alias_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_identity_alias_no_update BEFORE UPDATE ON app.auth_identity_rate_aliases FOR EACH ROW EXECUTE FUNCTION private.trg_auth_identity_alias_no_update();
CREATE FUNCTION private.trg_auth_identity_alias_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='auth_identity_alias_immutable';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER auth_identity_alias_no_delete BEFORE DELETE ON app.auth_identity_rate_aliases FOR EACH ROW EXECUTE FUNCTION private.trg_auth_identity_alias_no_delete();
CREATE FUNCTION private.trg_auth_otp_identity_no_relabel() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . identity_key_id != OLD . identity_key_id OR NEW . identity_hash != OLD . identity_hash OR NEW . identity_type != OLD . identity_type OR NEW . identity_value != OLD . identity_value OR NEW . code_hash != OLD . code_hash), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='auth_identity_history_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_otp_identity_no_relabel BEFORE UPDATE OF identity_key_id,identity_hash,identity_type,identity_value,code_hash ON app.auth_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_auth_otp_identity_no_relabel();
CREATE FUNCTION private.trg_auth_rate_identity_no_relabel() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . identity_key_id != OLD . identity_key_id OR NEW . identity_hash != OLD . identity_hash OR NEW . identity_aliases_json != OLD . identity_aliases_json), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='auth_identity_history_immutable';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER auth_rate_identity_no_relabel BEFORE UPDATE OF identity_key_id,identity_hash,identity_aliases_json ON app.auth_rate_claims FOR EACH ROW EXECUTE FUNCTION private.trg_auth_rate_identity_no_relabel();
CREATE FUNCTION private.trg_assisted_sms_grant_explicit() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . permission IN ( 'assisted_sms.read' , 'assisted_sms.manage' )), false) THEN RETURN NEW; END IF;
  IF NOT EXISTS ( SELECT 1 FROM request_receipts r JOIN assisted_sms_current_sessions s ON s . auth_session_id = r . session_id AND s . user_id = r . user_id JOIN admin_users a ON a . id = s . admin_id WHERE s . permission = 'admin_users.manage' AND s . role = 'owner' AND a . email = 'info@ikanisa.com' AND r . operation = 'assisted_sms.access.set' AND r . user_id = NEW . user_id AND NEW . granted_by = 'admin-account:' || s . admin_id AND json_extract ( r . response_json , '$.kind' ) = 'authenticated_owner_receipt_sms_access' AND json_extract ( r . response_json , '$.scope' ) = 'owner_receipt_sms_access' AND json_numeric ( r . response_json , '$.enabled' ) = 1 AND json_extract ( r . response_json , '$.current_admin_id' ) = s . admin_id AND json_extract ( r . response_json , '$.current_principal_id' ) = s . user_id AND json_extract ( r . response_json , '$.originating_session_id' ) = s . auth_session_id AND json_extract ( r . response_json , '$.public_session_id' ) = s . public_id AND json_extract ( r . response_json , '$.request_id' ) = r . request_id AND EXISTS ( SELECT 1 FROM admin_bridge_guards transaction_guard WHERE transaction_guard . id = json_extract ( r . response_json , '$.grant_transaction_id' ) AND transaction_guard . passed = 1 ) AND json_array_length ( r . response_json , '$.permissions' ) = 2 AND json_extract ( r . response_json , '$.permissions[0]' ) = 'assisted_sms.read' AND json_extract ( r . response_json , '$.permissions[1]' ) = 'assisted_sms.manage' ) THEN RETURN NULL; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_grant_explicit BEFORE INSERT ON app.admin_grants FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_grant_explicit();
CREATE FUNCTION private.trg_assisted_sms_grant_no_relabel() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((OLD . permission IN ( 'assisted_sms.read' , 'assisted_sms.manage' ) OR NEW . permission IN ( 'assisted_sms.read' , 'assisted_sms.manage' )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_grant_requires_explicit_decision';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_grant_no_relabel BEFORE UPDATE OF permission,user_id,granted_by ON app.admin_grants FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_grant_no_relabel();
CREATE FUNCTION private.trg_assisted_sms_job_current() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM assisted_sms_current_jobs WHERE id = NEW . id ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_source_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_job_current AFTER INSERT ON app.assisted_sms_jobs FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_job_current();
CREATE FUNCTION private.trg_assisted_sms_claim_current() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM assisted_sms_current_sessions s WHERE s . admin_id = NEW . actor_admin_id AND s . user_id = NEW . actor_user_id AND s . auth_session_id = NEW . originating_session_id AND s . public_id = NEW . public_session_id AND s . role = NEW . actor_role AND s . auth_version = NEW . actor_auth_version AND s . mfa_at = NEW . actor_mfa_at AND s . origin = NEW . origin AND s . permission = 'assisted_sms.manage' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_original_session_changed'; END IF;
  IF NEW . created_seconds != unixepoch ( ) OR NEW . expires_seconds <= unixepoch ( ) OR NEW . expires_seconds > unixepoch ( ) + 120 OR NOT EXISTS ( SELECT 1 FROM assisted_sms_current_jobs j WHERE j . id = NEW . job_id AND j . fence = NEW . previous_fence AND ( j . state = 'queued' OR ( j . state = 'claimed' AND EXISTS ( SELECT 1 FROM assisted_sms_claims old WHERE old . id = j . active_claim_id AND old . expires_seconds <= unixepoch ( ) ) ) ) ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_claim_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_claim_current BEFORE INSERT ON app.assisted_sms_claims FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_claim_current();
CREATE FUNCTION private.trg_assisted_sms_claim_head() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE assisted_sms_jobs SET state = 'claimed' , fence = NEW . fence , active_claim_id = NEW . id WHERE id = NEW . job_id;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_claim_head AFTER INSERT ON app.assisted_sms_claims FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_claim_head();
CREATE FUNCTION private.trg_assisted_sms_confirmation_current() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM assisted_sms_claims claim JOIN assisted_sms_current_jobs j ON j . id = claim . job_id JOIN assisted_sms_current_sessions s ON s . admin_id = claim . actor_admin_id AND s . user_id = claim . actor_user_id AND s . auth_session_id = claim . originating_session_id AND s . public_id = claim . public_session_id AND s . role = claim . actor_role AND s . auth_version = claim . actor_auth_version AND s . mfa_at = claim . actor_mfa_at AND s . origin = claim . origin WHERE s . permission = 'assisted_sms.manage' AND claim . id = NEW . claim_id AND claim . job_id = NEW . job_id AND j . state = 'claimed' AND j . active_claim_id = claim . id AND j . fence = NEW . fence AND claim . fence = NEW . fence AND claim . actor_admin_id = NEW . actor_admin_id AND claim . actor_user_id = NEW . actor_user_id AND claim . originating_session_id = NEW . originating_session_id AND claim . public_session_id = NEW . public_session_id AND claim . expires_seconds > unixepoch ( ) AND NEW . confirmed_seconds = unixepoch ( ) AND NEW . expires_seconds > unixepoch ( ) AND NEW . expires_seconds <= least ( claim . expires_seconds , unixepoch ( ) + 120 ) AND j . body_sha256 = NEW . body_sha256 AND j . destination_sha256 = NEW . destination_sha256 AND j . destination_revision = NEW . destination_revision ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_confirmation_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_confirmation_current BEFORE INSERT ON app.assisted_sms_confirmations FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_confirmation_current();
CREATE FUNCTION private.trg_assisted_sms_send_current() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM assisted_sms_confirmations confirmation JOIN assisted_sms_claims claim ON claim . id = confirmation . claim_id JOIN assisted_sms_current_jobs j ON j . id = claim . job_id JOIN assisted_sms_current_sessions s ON s . admin_id = claim . actor_admin_id AND s . user_id = claim . actor_user_id AND s . auth_session_id = claim . originating_session_id AND s . public_id = claim . public_session_id AND s . role = claim . actor_role AND s . auth_version = claim . actor_auth_version AND s . mfa_at = claim . actor_mfa_at AND s . origin = claim . origin WHERE s . permission = 'assisted_sms.manage' AND confirmation . id = NEW . confirmation_id AND confirmation . claim_id = NEW . claim_id AND confirmation . fence = NEW . fence AND confirmation . job_id = NEW . job_id AND j . active_claim_id = claim . id AND j . fence = NEW . fence AND j . state = 'claimed' AND confirmation . actor_admin_id = NEW . actor_admin_id AND confirmation . actor_user_id = NEW . actor_user_id AND confirmation . originating_session_id = NEW . originating_session_id AND confirmation . public_session_id = NEW . public_session_id AND claim . expires_seconds > unixepoch ( ) AND confirmation . expires_seconds > unixepoch ( ) AND NEW . started_seconds = unixepoch ( ) AND confirmation . body_sha256 = NEW . body_sha256 AND confirmation . destination_sha256 = NEW . destination_sha256 AND confirmation . destination_revision = NEW . destination_revision AND j . body_sha256 = NEW . body_sha256 AND j . destination_sha256 = NEW . destination_sha256 AND j . destination_revision = NEW . destination_revision ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_send_start_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_send_current BEFORE INSERT ON app.assisted_sms_send_starts FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_send_current();
CREATE FUNCTION private.trg_assisted_sms_send_head() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE assisted_sms_jobs SET state = 'send_started' WHERE id = NEW . job_id;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_send_head AFTER INSERT ON app.assisted_sms_send_starts FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_send_head();
CREATE FUNCTION private.trg_assisted_sms_outcome_current() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT EXISTS ( SELECT 1 FROM assisted_sms_current_sessions s WHERE s . permission = 'assisted_sms.manage' AND s . admin_id = NEW . observer_admin_id AND s . user_id = NEW . observer_user_id AND s . auth_session_id = NEW . observer_session_id AND s . public_id = NEW . observer_public_session_id ) OR NEW . observed_seconds != unixepoch ( ) OR NOT EXISTS ( SELECT 1 FROM assisted_sms_send_starts a JOIN assisted_sms_jobs j ON j . id = a . job_id WHERE a . id = NEW . attempt_id AND j . state = 'send_started' ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_observation_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_outcome_current BEFORE INSERT ON app.assisted_sms_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_outcome_current();
CREATE FUNCTION private.trg_assisted_sms_outcome_head() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  UPDATE assisted_sms_jobs SET state = NEW . observation WHERE id = ( SELECT job_id FROM assisted_sms_send_starts WHERE id = NEW . attempt_id );
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_outcome_head AFTER INSERT ON app.assisted_sms_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_outcome_head();
CREATE FUNCTION private.trg_assisted_sms_job_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_sms_envelope';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_job_immutable BEFORE UPDATE OF id,payment_id,entry_id,collection_id,recipient_user_id,payment_revision,amount_minor,destination_revision,destination_sha256,destination_ciphertext,consent_revision,policy_revision,policy_approval_sha256,authorization_receipt_sha256,template_key,body_ciphertext,body_sha256,created_at ON app.assisted_sms_jobs FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_job_immutable();
CREATE FUNCTION private.trg_assisted_sms_job_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_sms_envelope';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER assisted_sms_job_no_delete BEFORE DELETE ON app.assisted_sms_jobs FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_job_no_delete();
CREATE FUNCTION private.trg_assisted_sms_claims_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_claims_no_update BEFORE UPDATE ON app.assisted_sms_claims FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_claims_no_update();
CREATE FUNCTION private.trg_assisted_sms_claims_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER assisted_sms_claims_no_delete BEFORE DELETE ON app.assisted_sms_claims FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_claims_no_delete();
CREATE FUNCTION private.trg_assisted_sms_confirmations_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_confirmations_no_update BEFORE UPDATE ON app.assisted_sms_confirmations FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_confirmations_no_update();
CREATE FUNCTION private.trg_assisted_sms_confirmations_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER assisted_sms_confirmations_no_delete BEFORE DELETE ON app.assisted_sms_confirmations FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_confirmations_no_delete();
CREATE FUNCTION private.trg_assisted_sms_send_starts_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_send_starts_no_update BEFORE UPDATE ON app.assisted_sms_send_starts FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_send_starts_no_update();
CREATE FUNCTION private.trg_assisted_sms_send_starts_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER assisted_sms_send_starts_no_delete BEFORE DELETE ON app.assisted_sms_send_starts FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_send_starts_no_delete();
CREATE FUNCTION private.trg_assisted_sms_outcomes_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_outcomes_no_update BEFORE UPDATE ON app.assisted_sms_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_outcomes_no_update();
CREATE FUNCTION private.trg_assisted_sms_outcomes_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_immutable_sms_evidence';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER assisted_sms_outcomes_no_delete BEFORE DELETE ON app.assisted_sms_outcomes FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_outcomes_no_delete();
CREATE FUNCTION private.trg_assisted_sms_policy_revision() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . collection_id != OLD . collection_id OR NEW . revision <= OLD . revision), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_policy_revision_required';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_policy_revision BEFORE UPDATE ON app.assisted_sms_policies FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_policy_revision();
CREATE FUNCTION private.trg_assisted_sms_authorization_revision() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . collection_id != OLD . collection_id OR NEW . recipient_user_id != OLD . recipient_user_id OR NEW . consent_revision <= OLD . consent_revision OR NEW . destination_revision < OLD . destination_revision OR ( ( NEW . destination_sha256 != OLD . destination_sha256 OR NEW . destination_ciphertext != OLD . destination_ciphertext ) AND NEW . destination_revision <= OLD . destination_revision )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='sms_authorization_revision_required';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER assisted_sms_authorization_revision BEFORE UPDATE ON app.assisted_sms_authorizations FOR EACH ROW EXECUTE FUNCTION private.trg_assisted_sms_authorization_revision();
CREATE FUNCTION private.trg_momo_binding_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_gateway_binding';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_binding_identity BEFORE UPDATE OF id,owner_user_id,receiving_account_id,version,subscription_evidence,created_at ON app.momo_gateway_bindings FOR EACH ROW EXECUTE FUNCTION private.trg_momo_binding_identity();
CREATE FUNCTION private.trg_momo_binding_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_gateway_binding';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_binding_no_delete BEFORE DELETE ON app.momo_gateway_bindings FOR EACH ROW EXECUTE FUNCTION private.trg_momo_binding_no_delete();
CREATE FUNCTION private.trg_momo_account_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_receiving_account';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_account_identity BEFORE UPDATE OF id,provider,public_code,receiver_hash,currency,timezone ON app.momo_receiving_accounts FOR EACH ROW EXECUTE FUNCTION private.trg_momo_account_identity();
CREATE FUNCTION private.trg_momo_job_enrollment() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NEW . binding_id IS NOT NULL), false) THEN RETURN NEW; END IF;
  IF NOT EXISTS ( SELECT 1 FROM momo_gateway_bindings b JOIN momo_receiving_accounts a ON a . id = b . receiving_account_id JOIN sms_receipts s ON s . id = NEW . raw_sms_id WHERE b . id = NEW . binding_id AND b . version = NEW . binding_version AND b . receiving_account_id = NEW . receiving_account_id AND b . owner_user_id = s . owner_user_id AND b . status = 'active' AND a . status = 'active' AND a . receiver_hash = s . receiver_hash ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='gateway_binding_changed'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_job_enrollment BEFORE INSERT ON app.momo_processing_jobs FOR EACH ROW EXECUTE FUNCTION private.trg_momo_job_enrollment();
CREATE FUNCTION private.trg_momo_attempt_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_momo_attempt';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_attempt_no_update BEFORE UPDATE ON app.momo_parse_attempts FOR EACH ROW EXECUTE FUNCTION private.trg_momo_attempt_no_update();
CREATE FUNCTION private.trg_momo_attempt_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_momo_attempt';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_attempt_no_delete BEFORE DELETE ON app.momo_parse_attempts FOR EACH ROW EXECUTE FUNCTION private.trg_momo_attempt_no_delete();
CREATE FUNCTION private.trg_momo_transaction_facts() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_momo_transaction_facts';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_transaction_facts BEFORE UPDATE OF id,receiving_account_id,provider,provider_transaction_id,event_kind,original_transaction_id,amount_minor,currency,currency_scale,payer_name,payer_identifier,payer_last3,transaction_at,transaction_datetime_raw,transaction_timezone,transaction_time_source,fee_minor,wallet_balance_after_minor,parse_attempt_id,mode,created_at ON app.momo_transactions FOR EACH ROW EXECUTE FUNCTION private.trg_momo_transaction_facts();
CREATE FUNCTION private.trg_momo_transaction_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_momo_transaction';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_transaction_no_delete BEFORE DELETE ON app.momo_transactions FOR EACH ROW EXECUTE FUNCTION private.trg_momo_transaction_no_delete();
CREATE FUNCTION private.trg_momo_transaction_source_no_update() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_momo_source_link';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_transaction_source_no_update BEFORE UPDATE ON app.momo_transaction_sources FOR EACH ROW EXECUTE FUNCTION private.trg_momo_transaction_source_no_update();
CREATE FUNCTION private.trg_momo_transaction_source_no_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_momo_source_link';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_transaction_source_no_delete BEFORE DELETE ON app.momo_transaction_sources FOR EACH ROW EXECUTE FUNCTION private.trg_momo_transaction_source_no_delete();
CREATE FUNCTION private.trg_momo_gateway_capture_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_gateway_capture';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_gateway_capture_immutable BEFORE UPDATE ON app.momo_gateway_captures FOR EACH ROW EXECUTE FUNCTION private.trg_momo_gateway_capture_immutable();
CREATE FUNCTION private.trg_momo_gateway_capture_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_gateway_capture';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_gateway_capture_retain BEFORE DELETE ON app.momo_gateway_captures FOR EACH ROW EXECUTE FUNCTION private.trg_momo_gateway_capture_retain();
CREATE FUNCTION private.trg_momo_source_resolution_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_source_resolution';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_source_resolution_immutable BEFORE UPDATE ON app.momo_source_resolutions FOR EACH ROW EXECUTE FUNCTION private.trg_momo_source_resolution_immutable();
CREATE FUNCTION private.trg_momo_source_resolution_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_source_resolution';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_source_resolution_retain BEFORE DELETE ON app.momo_source_resolutions FOR EACH ROW EXECUTE FUNCTION private.trg_momo_source_resolution_retain();
CREATE FUNCTION private.trg_momo_job_source_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((NOT ( OLD . state = 'source_unresolved' AND OLD . binding_id IS NULL AND OLD . receiving_account_id IS NULL AND NEW . raw_sms_id = OLD . raw_sms_id AND NEW . binding_id IS NULL AND NEW . binding_version IS NULL AND NEW . mode = 'historical' AND NEW . created_at = OLD . created_at AND EXISTS ( SELECT 1 FROM momo_source_resolutions r JOIN sms_receipts s ON s . id = r . raw_sms_id JOIN momo_receiving_accounts a ON a . id = r . receiving_account_id WHERE r . raw_sms_id = NEW . raw_sms_id AND r . receiving_account_id = NEW . receiving_account_id AND r . source_body_sha256 = s . body_sha256 AND a . receiver_hash = s . receiver_hash ) )), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_momo_source';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_job_source_identity BEFORE UPDATE OF raw_sms_id,binding_id,binding_version,receiving_account_id,mode,created_at ON app.momo_processing_jobs FOR EACH ROW EXECUTE FUNCTION private.trg_momo_job_source_identity();
CREATE FUNCTION private.trg_momo_financial_link_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_momo_financial_link';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER momo_financial_link_immutable BEFORE UPDATE ON app.momo_financial_links FOR EACH ROW EXECUTE FUNCTION private.trg_momo_financial_link_immutable();
CREATE FUNCTION private.trg_momo_financial_link_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_momo_financial_link';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER momo_financial_link_retain BEFORE DELETE ON app.momo_financial_links FOR EACH ROW EXECUTE FUNCTION private.trg_momo_financial_link_retain();
CREATE FUNCTION private.trg_contribution_snapshot_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_contribution_snapshot';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER contribution_snapshot_immutable BEFORE UPDATE ON app.contribution_posting_snapshots FOR EACH ROW EXECUTE FUNCTION private.trg_contribution_snapshot_immutable();
CREATE FUNCTION private.trg_contribution_snapshot_retain() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='retain_contribution_snapshot';
  RETURN OLD;
END;
$trigger$;
CREATE TRIGGER contribution_snapshot_retain BEFORE DELETE ON app.contribution_posting_snapshots FOR EACH ROW EXECUTE FUNCTION private.trg_contribution_snapshot_retain();
CREATE FUNCTION private.trg_admin_email_otp_cooldown() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF EXISTS ( SELECT 1 FROM admin_email_otp_challenges WHERE user_id = NEW . user_id AND created_at + 60 > NEW . created_at ) THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='admin_email_otp_cooldown'; END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_email_otp_cooldown BEFORE INSERT ON app.admin_email_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_admin_email_otp_cooldown();
CREATE FUNCTION private.trg_admin_email_otp_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='immutable_admin_email_otp_identity';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_email_otp_identity BEFORE UPDATE OF id,user_id,principal_user_id,origin,role,
 auth_version,challenge_version,account_status,code_hash,created_at,expires_at ON app.admin_email_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_admin_email_otp_identity();
CREATE FUNCTION private.trg_admin_email_otp_consumed() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $trigger$
BEGIN
  IF NOT coalesce((OLD . used_at IS NOT NULL), false) THEN RETURN NEW; END IF;
  RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='admin_email_otp_already_consumed';
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER admin_email_otp_consumed BEFORE UPDATE ON app.admin_email_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_admin_email_otp_consumed();
-- Durable protected-object control plane. Provider bytes remain private and
-- are accepted only after full body hashing by the native Storage adapter.
-- This SQL does not turn a caller-supplied provider response into proof.
CREATE TABLE private.storage_namespace (
 singleton boolean PRIMARY KEY CHECK(singleton),
 origin text NOT NULL CHECK(origin ~ '^https://[^/?#@[:space:]]+$'),
 bucket text NOT NULL CHECK(bucket ~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.storage_payload_reservations (
 object_key text PRIMARY KEY,
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),
 aad text NOT NULL CHECK(length(aad) BETWEEN 1 AND 2000),
 key_id text NOT NULL CHECK(length(key_id) BETWEEN 1 AND 200),
 plaintext_sha256 text NOT NULL CHECK(plaintext_sha256 ~ '^[a-f0-9]{64}$'),
 sealed_body text CHECK(octet_length(sealed_body) BETWEEN 1 AND 10700000),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),cleared_at timestamptz,
 CHECK((sealed_body IS NULL)=(cleared_at IS NOT NULL))
);
CREATE INDEX storage_pending_owner ON private.storage_payload_reservations((scope->>'ownerId')) WHERE sealed_body IS NOT NULL;
CREATE TABLE private.storage_put_intents (
 operation_id text PRIMARY KEY,object_key text NOT NULL UNIQUE,
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),size bigint NOT NULL CHECK(size BETWEEN 1 AND 8000000),
 scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),http_metadata jsonb NOT NULL CHECK(jsonb_typeof(http_metadata)='object'),custom_metadata jsonb NOT NULL CHECK(jsonb_typeof(custom_metadata)='object'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','committed','erased')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),active_attempt uuid,
 upload_unresolved boolean NOT NULL DEFAULT false,delete_tombstone boolean NOT NULL DEFAULT false,
 last_outcome text,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.storage_upload_attempts (
 id uuid PRIMARY KEY,operation_id text NOT NULL REFERENCES private.storage_put_intents(operation_id),
 outcome text NOT NULL DEFAULT 'started',started_at timestamptz NOT NULL DEFAULT clock_timestamp(),completed_at timestamptz
);
ALTER TABLE private.storage_put_intents ADD CONSTRAINT storage_active_attempt_fk FOREIGN KEY(active_attempt) REFERENCES private.storage_upload_attempts(id) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE private.storage_objects (
 object_key text PRIMARY KEY,operation_id text NOT NULL UNIQUE REFERENCES private.storage_put_intents(operation_id),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),size bigint NOT NULL CHECK(size BETWEEN 1 AND 8000000),
 scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),http_metadata jsonb NOT NULL CHECK(jsonb_typeof(http_metadata)='object'),custom_metadata jsonb NOT NULL CHECK(jsonb_typeof(custom_metadata)='object'),etag text,
 committed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.storage_delete_intents (
 operation_id text PRIMARY KEY,object_key text NOT NULL UNIQUE REFERENCES private.storage_put_intents(object_key),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),expected_sha256 text NOT NULL CHECK(expected_sha256 ~ '^[a-f0-9]{64}$'),scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','committed')),
 last_outcome text,absence_proof jsonb,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),committed_at timestamptz,
 CHECK(state<>'committed' OR (committed_at IS NOT NULL AND absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb))
);

-- One canonical metadata writer. This view exists for read compatibility only;
-- it has no INSERT/UPDATE/DELETE grants and uses the caller's RLS privileges.
CREATE VIEW private.object_metadata WITH(security_invoker=true) AS
 SELECT object_key,size,http_metadata,custom_metadata,sha256,committed_at AS created_at FROM private.storage_objects;

-- The source implements physical erasure only for its generic upload catalog.
-- Financial evidence, raw SMS and roster sources remain retained. Authority,
-- source/preimage guards, claim and barrier must still be present in this
-- transaction; neither an HTTP callback nor a JSON boolean grants erasure.
CREATE FUNCTION private.assert_storage_delete_authorized(p_key text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE actor text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,7346369));
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF EXISTS(SELECT 1 FROM app.payment_evidence WHERE object_key=p_key) OR EXISTS(SELECT 1 FROM app.sms_receipts WHERE object_key=p_key) OR EXISTS(SELECT 1 FROM app.roster_imports WHERE source_object_key=p_key) THEN RAISE EXCEPTION 'storage_retention_class_not_erasable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM private.storage_put_intents i
  JOIN app.upload_objects o ON o.object_key=i.object_key AND o.sha256=i.sha256 AND o.user_id=i.scope->>'ownerId' AND o.id=i.scope->>'entityId'
  JOIN app.privacy_retention_effects e ON e.object_key=i.object_key AND e.source_sha256=i.sha256
  JOIN app.privacy_retention_tasks t ON t.id=e.task_id AND t.class_name='r2:upload_objects' AND t.action='erase' AND t.state='claimed' AND t.claim_id=e.claim_id AND t.fence=e.fence
  JOIN app.privacy_retention_claims c ON c.id=e.claim_id AND c.task_id=t.id AND c.fence=t.fence AND c.actor_id=actor AND c.session_id=api.current_session_id() AND c.expires_seconds>app.unixepoch()
  JOIN app.privacy_retention_plans p ON p.id=t.plan_id AND p.subject_id=o.user_id
  JOIN app.privacy_retention_barriers b ON b.subject_id=p.subject_id AND (b.plan_id=p.id OR b.plan_id=app.json_extract(p.policy_json,'$.quarantine_continuation.previous_plan_id'))
  JOIN app.runtime_config cfg ON cfg.key='privacy:retention:approved:v1' AND cfg.revision=p.policy_config_revision AND cfg.value_json=p.policy_json
  WHERE i.object_key=p_key AND i.active_attempt IS NULL AND NOT i.upload_unresolved
   AND app.json_numeric(p.policy_json,'$.writer_fence.generic_upload_catalog_only')=1 AND app.json_numeric(p.policy_json,'$.writer_fence.unknown_in_flight')=0
   AND app.julianday(app.json_extract(p.policy_json,'$.expires_at'))>app.julianday('now')
   AND encode(sha256(convert_to(p.policy_json,'UTF8')),'hex')=p.policy_sha256
   AND coalesce((SELECT revision FROM app.privacy_review_heads WHERE request_id=p.request_id),0)=p.review_revision
   AND EXISTS(SELECT 1 FROM app.mutation_guards g WHERE g.user_id=actor AND g.session_id=api.current_session_id() AND g.permission='privacy.review' AND g.minimum_assurance=2 AND g.fresh_seconds<=300)
   AND EXISTS(SELECT 1 FROM app.privacy_retention_guards g WHERE g.plan_id=p.id AND g.class_name=t.class_name AND g.passed=1)
   AND NOT EXISTS(SELECT 1 FROM app.privacy_holds h WHERE h.user_id=p.subject_id AND h.active=1)
   AND NOT EXISTS(SELECT 1 FROM app.native_reservations n WHERE n.user_id=p.subject_id AND n.state NOT IN('completed','rejected'))
   AND NOT EXISTS(SELECT 1 FROM app.roster_imports r WHERE r.user_id=p.subject_id AND r.state IN('processing','ambiguous'))
   AND NOT EXISTS(SELECT 1 FROM app.auth_otp_challenges x WHERE x.identity_value IN(SELECT phone FROM app.users WHERE id=p.subject_id UNION SELECT email FROM app.users WHERE id=p.subject_id) AND x.status IN('dispatching','delivery_unknown'))
 ) THEN RAISE EXCEPTION 'storage_retention_admission_required' USING ERRCODE='42501'; END IF;
END$$;

CREATE FUNCTION private.trg_storage_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE old_json jsonb;new_json jsonb;mutable text[];
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'retain_storage_control_identity' USING ERRCODE='42501'; END IF;
 mutable:=CASE TG_TABLE_NAME
  WHEN 'storage_put_intents' THEN ARRAY['state','attempts','active_attempt','upload_unresolved','delete_tombstone','last_outcome','updated_at']
  WHEN 'storage_upload_attempts' THEN ARRAY['outcome','completed_at']
  WHEN 'storage_delete_intents' THEN ARRAY['state','last_outcome','absence_proof','committed_at']
  WHEN 'storage_payload_reservations' THEN ARRAY['sealed_body','cleared_at']
  ELSE ARRAY[]::text[] END;
 old_json:=to_jsonb(OLD);new_json:=to_jsonb(NEW);
 IF old_json-mutable IS DISTINCT FROM new_json-mutable THEN RAISE EXCEPTION 'immutable_storage_identity' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='storage_namespace' THEN RAISE EXCEPTION 'immutable_storage_namespace' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='storage_payload_reservations' THEN
  IF OLD.sealed_body IS NULL OR NEW.sealed_body IS NOT NULL OR NEW.cleared_at IS NULL THEN RAISE EXCEPTION 'immutable_storage_payload' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.owner_user_id=OLD.scope->>'ownerId' AND r.object_sha256=OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM app.payment_evidence r WHERE r.object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.owner_user_id=OLD.scope->>'ownerId' AND r.object_sha256=OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM app.roster_imports r WHERE r.source_object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.user_id=OLD.scope->>'ownerId' AND r.source_sha256=OLD.plaintext_sha256 AND r.state='retained')
   AND NOT EXISTS(SELECT 1 FROM private.storage_put_intents i JOIN private.storage_delete_intents d ON d.object_key=i.object_key WHERE i.object_key=OLD.object_key AND i.state='erased' AND i.delete_tombstone AND d.state='committed' AND d.absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb)
  THEN RAISE EXCEPTION 'storage_payload_clear_requires_application_or_erasure_commit' USING ERRCODE='42501'; END IF;
 ELSIF TG_TABLE_NAME='storage_put_intents' THEN
  IF (OLD.delete_tombstone AND NOT NEW.delete_tombstone) OR (OLD.upload_unresolved AND NOT NEW.upload_unresolved) OR NEW.attempts<OLD.attempts OR (OLD.state='erased' AND NEW.state<>'erased') OR (OLD.state='committed' AND NEW.state='pending') THEN RAISE EXCEPTION 'storage_state_regression' USING ERRCODE='42501'; END IF;
  IF (NEW.delete_tombstone AND NOT OLD.delete_tombstone) OR (NEW.state='erased' AND OLD.state<>'erased') THEN PERFORM private.assert_storage_delete_authorized(NEW.object_key); END IF;
 ELSIF TG_TABLE_NAME='storage_delete_intents' THEN
  IF OLD.state='committed' AND old_json IS DISTINCT FROM new_json THEN RAISE EXCEPTION 'immutable_storage_delete_result' USING ERRCODE='42501'; END IF;
 ELSIF TG_TABLE_NAME='storage_upload_attempts' THEN
  IF OLD.completed_at IS NOT NULL AND old_json IS DISTINCT FROM new_json THEN RAISE EXCEPTION 'immutable_storage_attempt_result' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER storage_namespace_identity BEFORE UPDATE OR DELETE ON private.storage_namespace FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_payload_identity BEFORE UPDATE OR DELETE ON private.storage_payload_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_put_identity BEFORE UPDATE OR DELETE ON private.storage_put_intents FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_upload_identity BEFORE UPDATE OR DELETE ON private.storage_upload_attempts FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_delete_identity BEFORE UPDATE OR DELETE ON private.storage_delete_intents FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_object_identity BEFORE UPDATE ON private.storage_objects FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();

CREATE FUNCTION private.trg_storage_object_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_storage_delete_authorized(OLD.object_key);
 IF NOT EXISTS(SELECT 1 FROM private.storage_put_intents WHERE object_key=OLD.object_key AND delete_tombstone AND active_attempt IS NULL AND NOT upload_unresolved) THEN RAISE EXCEPTION 'storage_delete_tombstone_required' USING ERRCODE='42501'; END IF;
 RETURN OLD;
END$$;
CREATE TRIGGER storage_object_delete BEFORE DELETE ON private.storage_objects FOR EACH ROW EXECUTE FUNCTION private.trg_storage_object_delete();

-- Journal ordering removes metadata before marking its erasure receipt. Check
-- the final transaction state, so a partial SQL batch cannot commit metadata
-- loss without the exact dual-absence receipt and retained tombstone.
CREATE FUNCTION private.trg_storage_erasure_commit() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM private.storage_objects WHERE object_key=OLD.object_key)
  OR NOT EXISTS(SELECT 1 FROM private.storage_put_intents i JOIN private.storage_delete_intents d ON d.object_key=i.object_key WHERE i.object_key=OLD.object_key AND i.state='erased' AND i.delete_tombstone AND i.active_attempt IS NULL AND NOT i.upload_unresolved AND d.state='committed' AND d.expected_sha256=OLD.sha256 AND d.scope=OLD.scope AND d.absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb)
 THEN RAISE EXCEPTION 'storage_erasure_commit_incomplete' USING ERRCODE='42501';END IF;
 UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp() WHERE object_key=OLD.object_key AND sealed_body IS NOT NULL;
 RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER storage_object_erase_commit AFTER DELETE ON private.storage_objects DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.trg_storage_erasure_commit();

CREATE FUNCTION private.trg_storage_reservation_budget() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE count_pending bigint;bytes_pending bigint;
BEGIN
 IF NEW.scope->>'ownerId' IS NULL OR NEW.scope->>'entityId' IS NULL OR NEW.scope->>'purpose' IS NULL OR (SELECT count(*) FROM jsonb_object_keys(NEW.scope))<>3 THEN RAISE EXCEPTION 'invalid_storage_scope' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.scope->>'ownerId',7346370));
 SELECT count(*),coalesce(sum(octet_length(sealed_body)),0) INTO count_pending,bytes_pending FROM private.storage_payload_reservations WHERE scope->>'ownerId'=NEW.scope->>'ownerId' AND sealed_body IS NOT NULL;
 IF count_pending>=128 OR bytes_pending+octet_length(NEW.sealed_body)>64000000 THEN RAISE EXCEPTION 'storage_pending_budget_exceeded' USING ERRCODE='54000'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER storage_reservation_budget BEFORE INSERT ON private.storage_payload_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_storage_reservation_budget();

CREATE FUNCTION private.assert_storage_ready(p_key text,p_owner text,p_entity text,p_plain_sha text,p_purpose text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE object private.storage_objects%ROWTYPE;intent private.storage_put_intents%ROWTYPE;reserved private.storage_payload_reservations%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,7346369));
 -- Immutable metadata needs no UPDATE privilege. The shared per-object
 -- advisory lock serializes this lookup with every journal mutation.
 SELECT * INTO object FROM private.storage_objects WHERE object_key=p_key;
 SELECT * INTO intent FROM private.storage_put_intents WHERE object_key=p_key FOR SHARE;
 SELECT * INTO reserved FROM private.storage_payload_reservations WHERE object_key=p_key FOR UPDATE;
 IF object.object_key IS NULL OR intent.object_key IS NULL OR reserved.object_key IS NULL OR intent.state<>'committed' OR intent.delete_tombstone
  OR object.operation_id<>intent.operation_id OR object.fingerprint<>intent.fingerprint OR object.sha256<>intent.sha256 OR object.size<>intent.size
  OR object.scope IS DISTINCT FROM intent.scope OR object.http_metadata IS DISTINCT FROM intent.http_metadata OR object.custom_metadata IS DISTINCT FROM intent.custom_metadata
  OR object.scope IS DISTINCT FROM jsonb_build_object('ownerId',p_owner,'entityId',p_entity,'purpose',p_purpose)
  OR reserved.scope IS DISTINCT FROM object.scope OR reserved.plaintext_sha256 IS DISTINCT FROM p_plain_sha
  OR object.custom_metadata->>'source_fingerprint' IS DISTINCT FROM reserved.source_fingerprint
  OR object.custom_metadata->>'sha256' IS DISTINCT FROM p_plain_sha
 THEN RAISE EXCEPTION 'storage_not_ready_for_application_commit' USING ERRCODE='42501'; END IF;
END$$;

CREATE FUNCTION private.trg_storage_application_commit() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE key text;
BEGIN
 IF TG_TABLE_NAME='sms_receipts' THEN
  key:=NEW.object_key;PERFORM private.assert_storage_ready(key,NEW.owner_user_id,NEW.id,NEW.object_sha256,'sms_receipt');
 ELSIF TG_TABLE_NAME='payment_evidence' THEN
  key:=NEW.object_key;PERFORM private.assert_storage_ready(key,NEW.owner_user_id,NEW.id,NEW.object_sha256,'payment_evidence');
 ELSIF TG_TABLE_NAME='roster_imports' THEN
  IF NEW.state<>'retained' OR OLD.state=NEW.state THEN RETURN NEW; END IF;
  key:=NEW.source_object_key;PERFORM private.assert_storage_ready(key,NEW.user_id,NEW.id,NEW.source_sha256,'roster_source');
  IF NOT EXISTS(SELECT 1 FROM private.storage_objects o WHERE o.object_key=key AND o.sha256=NEW.object_sha256 AND o.custom_metadata->>'source_sha256'=NEW.source_sha256 AND o.custom_metadata->>'object_sha256'=NEW.object_sha256) THEN RAISE EXCEPTION 'roster_storage_source_changed' USING ERRCODE='42501'; END IF;
 END IF;
 UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp() WHERE object_key=key AND sealed_body IS NOT NULL;
 RETURN NEW;
END$$;
CREATE TRIGGER storage_sms_application_commit AFTER INSERT ON app.sms_receipts FOR EACH ROW EXECUTE FUNCTION private.trg_storage_application_commit();
CREATE TRIGGER storage_evidence_application_commit AFTER INSERT ON app.payment_evidence FOR EACH ROW EXECUTE FUNCTION private.trg_storage_application_commit();
CREATE TRIGGER storage_roster_application_commit AFTER UPDATE OF state ON app.roster_imports FOR EACH ROW EXECUTE FUNCTION private.trg_storage_application_commit();
-- Managed Auth is the identity authority. These are immutable principal links
-- and server-side custody/projections, never a transplant of legacy tokens.
CREATE TABLE private.auth_principal_links (
 auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),
 user_id text NOT NULL UNIQUE REFERENCES app.users(id),
 linked_at timestamptz NOT NULL DEFAULT now(),
 proof_reference text NOT NULL CHECK(length(proof_reference)>0)
);
CREATE FUNCTION private.trg_auth_principal_link_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_managed_principal_link' USING ERRCODE='42501';END$$;
CREATE TRIGGER auth_principal_link_identity BEFORE UPDATE OR DELETE ON private.auth_principal_links FOR EACH ROW EXECUTE FUNCTION private.trg_auth_principal_link_identity();
CREATE TABLE private.supabase_otp_challenges (
 id text PRIMARY KEY, identity_hash text NOT NULL CHECK(length(identity_hash)=64), identity_type text NOT NULL CHECK(identity_type IN('phone','email')),
 identity_value text NOT NULL, surface text NOT NULL CHECK(surface IN('member','admin')),
 registration_allowed bigint NOT NULL CHECK(registration_allowed IN(0,1)),
 created_at bigint NOT NULL, expires_at bigint NOT NULL CHECK(expires_at>created_at),
 attempts bigint NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5), consumed_at bigint,
 delivery_status text NOT NULL DEFAULT 'reserved' CHECK(delivery_status IN('reserved','accepted','rejected','unknown'))
);
CREATE INDEX supabase_otp_identity_cooldown ON private.supabase_otp_challenges(identity_hash,surface,created_at DESC);
CREATE FUNCTION private.trg_supabase_otp_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=private,pg_catalog AS $$
BEGIN
 -- Lock the identity before checking the previous reservation. The reservation
 -- is committed before the provider call; a missing acknowledgement keeps it.
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.identity_hash||':'||NEW.surface,1));
 IF EXISTS(SELECT 1 FROM private.supabase_otp_challenges c WHERE c.identity_hash=NEW.identity_hash AND c.surface=NEW.surface AND c.created_at+60>NEW.created_at) THEN RAISE EXCEPTION 'otp_cooldown' USING ERRCODE='P0001'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER supabase_otp_admission BEFORE INSERT ON private.supabase_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_supabase_otp_admission();
CREATE FUNCTION private.trg_supabase_otp_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'retain_managed_otp_admission' USING ERRCODE='42501';END IF;
 IF to_jsonb(OLD)-ARRAY['attempts','consumed_at','delivery_status'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['attempts','consumed_at','delivery_status'] THEN RAISE EXCEPTION 'immutable_managed_otp_identity' USING ERRCODE='42501';END IF;
 IF NEW.attempts<OLD.attempts OR (OLD.consumed_at IS NOT NULL AND NEW.consumed_at IS DISTINCT FROM OLD.consumed_at) THEN RAISE EXCEPTION 'managed_otp_state_regression' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER supabase_otp_identity BEFORE UPDATE OR DELETE ON private.supabase_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_supabase_otp_identity();
CREATE TABLE private.bff_sessions (
 token_hash text PRIMARY KEY REFERENCES app.admin_sessions(token_hash) ON UPDATE CASCADE ON DELETE CASCADE,
 auth_user_id uuid NOT NULL REFERENCES auth.users(id), auth_session_id uuid NOT NULL UNIQUE,
 token_ciphertext text NOT NULL CHECK(app.json_valid(token_ciphertext)),
 version bigint NOT NULL DEFAULT 1, refresh_lease text, refresh_lease_until bigint
);
CREATE TABLE private.managed_mfa_proofs (
 session_id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id),
 factor_id uuid NOT NULL, verified_at_epoch bigint NOT NULL,
 CHECK(verified_at_epoch>0)
);
-- Original managed OTP proof is retained independently of the provider's
-- disposable session row. Only record_managed_phone_verification may write it.
CREATE TABLE private.managed_phone_verifications (
 challenge_id text PRIMARY KEY REFERENCES private.supabase_otp_challenges(id),
 auth_user_id uuid NOT NULL REFERENCES auth.users(id), session_id uuid NOT NULL,
 user_id text NOT NULL REFERENCES app.users(id),
 phone text NOT NULL CHECK(phone ~ '^\+[1-9][0-9]{6,14}$'),
 verified_at bigint NOT NULL CHECK(verified_at>0)
);
CREATE FUNCTION private.trg_managed_phone_proof_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_managed_phone_verification' USING ERRCODE='42501';END$$;
CREATE TRIGGER managed_phone_proof_identity BEFORE UPDATE OR DELETE ON private.managed_phone_verifications FOR EACH ROW EXECUTE FUNCTION private.trg_managed_phone_proof_identity();
-- Bind the same managed OAuth handoff to its original product surface and
-- exact browser origin. A legacy flow without this context is inadmissible.
CREATE TABLE private.google_flow_context (
 flow_id text PRIMARY KEY REFERENCES app.auth_google_flows(id),
 surface text NOT NULL CHECK(surface IN('member','admin')),
 request_origin text CHECK(request_origin IS NULL OR length(request_origin) BETWEEN 1 AND 2048),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(surface<>'admin' OR request_origin IS NOT NULL)
);
CREATE FUNCTION private.trg_google_flow_context_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_google_flow_context' USING ERRCODE='42501';END$$;
CREATE TRIGGER google_flow_context_identity BEFORE UPDATE OR DELETE ON private.google_flow_context FOR EACH ROW EXECUTE FUNCTION private.trg_google_flow_context_identity();

CREATE FUNCTION private.request_claims() RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
EXCEPTION WHEN invalid_text_representation THEN RETURN '{}'::jsonb; END$$;
CREATE FUNCTION api.current_principal_id() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT l.user_id FROM private.auth_principal_links l
 WHERE l.auth_user_id::text=private.request_claims()->>'sub'
$$;
CREATE FUNCTION api.current_session_id() RETURNS text LANGUAGE sql STABLE AS $$SELECT private.request_claims()->>'session_id'$$;
CREATE FUNCTION private.is_managed_session(p_auth_user_id uuid,p_session_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.request_claims()->>'sub'=p_auth_user_id::text AND private.request_claims()->>'session_id'=p_session_id::text
 AND private.request_claims()->>'role'='authenticated' AND EXISTS(
 SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id WHERE s.id=p_session_id AND s.user_id=p_auth_user_id
 AND (to_jsonb(u)->>'deleted_at') IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()))
$$;
CREATE FUNCTION private.session_expiry(p_requested_epoch bigint) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); actual jsonb; limited bigint;
BEGIN
 IF NOT coalesce(private.is_managed_session((claims->>'sub')::uuid,(claims->>'session_id')::uuid),false) THEN RAISE EXCEPTION 'managed_session_required' USING ERRCODE='42501'; END IF;
 IF p_requested_epoch<=extract(epoch FROM now())::bigint OR p_requested_epoch>extract(epoch FROM now())::bigint+2592000 THEN RAISE EXCEPTION 'invalid_session_lifetime' USING ERRCODE='22023'; END IF;
 SELECT to_jsonb(s) INTO actual FROM auth.sessions s WHERE s.id::text=claims->>'session_id';
 limited:=p_requested_epoch;
 IF actual->>'not_after' IS NOT NULL THEN limited:=least(limited,floor(extract(epoch FROM (actual->>'not_after')::timestamptz))::bigint); END IF;
 RETURN limited;
END$$;
CREATE FUNCTION private.record_managed_phone_verification(p_challenge_id text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims();principal uuid;session_uuid uuid;legacy_id text;actual_phone text;confirmed timestamptz;canonical_phone text;verified bigint;challenge private.supabase_otp_challenges%ROWTYPE;retained private.managed_phone_verifications%ROWTYPE;
BEGIN
 principal:=(claims->>'sub')::uuid;session_uuid:=(claims->>'session_id')::uuid;legacy_id:=api.current_principal_id();
 IF p_challenge_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR legacy_id IS NULL OR NOT coalesce(private.is_managed_session(principal,session_uuid),false) THEN RAISE EXCEPTION 'managed_phone_proof_required' USING ERRCODE='42501';END IF;
 SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge_id FOR SHARE;
 IF NOT FOUND OR challenge.identity_type<>'phone' OR challenge.surface<>'member' OR challenge.delivery_status NOT IN('accepted','unknown') OR challenge.consumed_at IS NULL OR challenge.consumed_at NOT BETWEEN challenge.created_at AND challenge.expires_at THEN RAISE EXCEPTION 'consumed_managed_phone_challenge_required' USING ERRCODE='42501';END IF;
 SELECT u.phone,u.phone_confirmed_at INTO actual_phone,confirmed FROM auth.users u WHERE u.id=principal;
 IF actual_phone !~ '^\+?[1-9][0-9]{6,14}$' OR confirmed IS NULL THEN RAISE EXCEPTION 'confirmed_managed_phone_required' USING ERRCODE='42501';END IF;
 canonical_phone:='+'||ltrim(actual_phone,'+');
 IF canonical_phone IS DISTINCT FROM challenge.identity_value OR NOT EXISTS(SELECT 1 FROM app.users u JOIN app.auth_sessions s ON s.user_id=u.id WHERE u.id=legacy_id AND u.phone=canonical_phone AND u.access_status='active' AND s.id=session_uuid::text AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM now())::bigint) THEN RAISE EXCEPTION 'managed_phone_identity_changed' USING ERRCODE='42501';END IF;
 -- The timestamp belongs to the signed OTP event; observing it again cannot
 -- manufacture a fresh proof. Other AMR methods, strings and metadata fail.
 SELECT max(CASE WHEN item->>'timestamp' ~ '^[0-9]{1,12}$' THEN (item->>'timestamp')::bigint END) INTO verified FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item WHERE item->>'method'='otp' AND jsonb_typeof(item->'timestamp')='number';
 IF verified IS NULL OR verified NOT BETWEEN challenge.created_at AND challenge.consumed_at+1 OR verified>extract(epoch FROM now())::bigint+1 THEN RAISE EXCEPTION 'original_managed_phone_amr_required' USING ERRCODE='42501';END IF;
 INSERT INTO private.managed_phone_verifications(challenge_id,auth_user_id,session_id,user_id,phone,verified_at) VALUES(p_challenge_id,principal,session_uuid,legacy_id,canonical_phone,verified) ON CONFLICT(challenge_id) DO NOTHING;
 SELECT * INTO retained FROM private.managed_phone_verifications WHERE challenge_id=p_challenge_id;
 IF retained.auth_user_id IS DISTINCT FROM principal OR retained.session_id IS DISTINCT FROM session_uuid OR retained.user_id IS DISTINCT FROM legacy_id OR retained.phone IS DISTINCT FROM canonical_phone OR retained.verified_at IS DISTINCT FROM verified THEN RAISE EXCEPTION 'managed_phone_proof_conflict' USING ERRCODE='42501';END IF;
 RETURN p_challenge_id;
END$$;
CREATE FUNCTION private.managed_phone_binding(p_user_id text,p_challenge_id text,p_phone text,p_session_id text DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM private.managed_phone_verifications p
 JOIN private.auth_principal_links l ON l.auth_user_id=p.auth_user_id AND l.user_id=p.user_id
 JOIN app.users u ON u.id=p.user_id JOIN auth.users a ON a.id=p.auth_user_id
 JOIN private.supabase_otp_challenges c ON c.id=p.challenge_id
 WHERE p.user_id=p_user_id AND p.challenge_id=p_challenge_id AND p.phone=p_phone AND u.phone=p.phone AND u.access_status='active'
 AND a.phone_confirmed_at IS NOT NULL AND a.phone ~ '^\+?[1-9][0-9]{6,14}$' AND '+'||ltrim(a.phone,'+')=p.phone
 AND to_jsonb(a)->>'deleted_at' IS NULL AND (to_jsonb(a)->>'banned_until' IS NULL OR (to_jsonb(a)->>'banned_until')::timestamptz<=now())
 AND c.identity_type='phone' AND c.surface='member' AND c.identity_value=p.phone AND c.delivery_status IN('accepted','unknown')
 AND c.consumed_at BETWEEN c.created_at AND c.expires_at AND p.verified_at BETWEEN c.created_at AND c.consumed_at+1
 AND (p_session_id IS NULL OR (p.session_id::text=p_session_id AND private.request_claims()->>'session_id'=p_session_id AND private.request_claims()->>'sub'=p.auth_user_id::text AND private.is_managed_session(p.auth_user_id,p.session_id)
 AND EXISTS(SELECT 1 FROM app.auth_sessions s WHERE s.id=p_session_id AND s.user_id=p.user_id AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM now())::bigint))))
$$;
CREATE FUNCTION private.record_mfa_projection(p_factor_id uuid) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); verified_at bigint; managed_verified_at bigint; actual jsonb; principal uuid; session_uuid uuid;
BEGIN
 principal:=(claims->>'sub')::uuid; session_uuid:=(claims->>'session_id')::uuid;
 IF claims->>'aal' IS DISTINCT FROM 'aal2' OR NOT coalesce(private.is_managed_session(principal,session_uuid),false) THEN RAISE EXCEPTION 'managed_mfa_required' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(s) INTO actual FROM auth.sessions s JOIN auth.mfa_factors f ON f.user_id=s.user_id AND f.id=p_factor_id WHERE s.id=session_uuid AND s.user_id=principal AND f.status::text='verified' AND to_jsonb(s)->>'aal'='aal2';
 IF actual IS NULL OR (actual->>'factor_id' IS NOT NULL AND actual->>'factor_id'<>p_factor_id::text) THEN RAISE EXCEPTION 'managed_mfa_required' USING ERRCODE='42501'; END IF;
 SELECT max((item->>'timestamp')::bigint) INTO verified_at FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item WHERE item->>'method' IN('totp','mfa/totp') AND item->>'timestamp' ~ '^[0-9]+$';
 SELECT max(floor(extract(epoch FROM updated_at))::bigint) INTO managed_verified_at FROM auth.mfa_amr_claims WHERE session_id=session_uuid AND authentication_method IN('totp','mfa/totp');
 IF managed_verified_at IS NULL OR verified_at IS NULL OR abs(managed_verified_at-verified_at)>1 THEN RAISE EXCEPTION 'managed_mfa_amr_required' USING ERRCODE='42501'; END IF;
 verified_at:=managed_verified_at;
 IF verified_at IS NULL OR verified_at<extract(epoch FROM now())::bigint-300 OR verified_at>extract(epoch FROM now())::bigint+30 THEN RAISE EXCEPTION 'fresh_mfa_required' USING ERRCODE='42501'; END IF;
 INSERT INTO private.managed_mfa_proofs(session_id,user_id,factor_id,verified_at_epoch) VALUES(session_uuid,principal,p_factor_id,verified_at) ON CONFLICT(session_id) DO UPDATE SET factor_id=excluded.factor_id,verified_at_epoch=excluded.verified_at_epoch WHERE managed_mfa_proofs.user_id=excluded.user_id AND managed_mfa_proofs.verified_at_epoch<=excluded.verified_at_epoch;
 RETURN verified_at;
END$$;

CREATE FUNCTION private.assert_actor(p_permission text DEFAULT NULL,p_collection_id text DEFAULT NULL,p_group_role text DEFAULT NULL,p_min_aal bigint DEFAULT 1,p_fresh_seconds bigint DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE principal text; claims jsonb; projected app.auth_sessions%ROWTYPE; managed jsonb; now_seconds bigint:=app.unixepoch();
BEGIN
 claims:=private.request_claims(); principal:=api.current_principal_id();
 IF principal IS NULL OR claims->>'role' IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 SELECT s.* INTO projected FROM app.auth_sessions s JOIN app.users u ON u.id=s.user_id
 WHERE s.id=api.current_session_id() AND s.user_id=principal AND s.revoked_at IS NULL
 AND s.expires_at>now_seconds AND u.access_status='active' FOR SHARE OF s,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(s) INTO managed FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
 WHERE s.id::text=projected.id AND u.id::text=claims->>'sub'
 AND (to_jsonb(u)->>'deleted_at') IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()) FOR SHARE OF s,u;
 IF managed IS NULL THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 IF p_min_aal>1 AND (claims->>'aal' IS DISTINCT FROM 'aal2' OR managed->>'aal' IS DISTINCT FROM 'aal2' OR projected.assurance_level<>2 OR projected.mfa_at IS NULL OR projected.mfa_at<now_seconds-300 OR NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs proof JOIN auth.mfa_factors f ON f.id=proof.factor_id AND f.user_id=proof.user_id WHERE proof.session_id::text=projected.id AND proof.user_id::text=claims->>'sub' AND proof.factor_id::text=projected.mfa_factor_id AND f.status::text='verified' AND proof.verified_at_epoch=projected.mfa_at)) THEN RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501'; END IF;
 IF p_fresh_seconds IS NOT NULL AND greatest(projected.auth_at,coalesce(projected.mfa_at,0))<now_seconds-p_fresh_seconds THEN RAISE EXCEPTION 'fresh_auth_required' USING ERRCODE='42501'; END IF;
 IF p_permission IS NOT NULL AND (projected.surface<>'admin' OR NOT EXISTS(SELECT 1 FROM app.admin_grants g WHERE g.user_id=principal AND g.permission=p_permission)) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501'; END IF;
 IF p_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.memberships m JOIN app.collections c ON c.id=m.collection_id WHERE m.user_id=principal AND m.collection_id=p_collection_id AND m.active=1 AND c.status='active' AND (p_group_role IS NULL OR m.role=p_group_role OR (p_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501'; END IF;
 RETURN principal;
END$$;

-- This additional guard binds the existing169 source guards to the real
-- managed identity/session. A forged application session row is insufficient.
CREATE FUNCTION private.trg_managed_mutation_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE principal text;
BEGIN
 principal:=private.assert_actor(NEW.permission,NEW.collection_id,NEW.required_group_role,coalesce(NEW.minimum_assurance,1),NEW.fresh_seconds);
 IF NEW.user_id IS DISTINCT FROM principal OR NEW.session_id IS DISTINCT FROM api.current_session_id() THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER managed_mutation_admission BEFORE INSERT ON app.mutation_guards FOR EACH ROW EXECUTE FUNCTION private.trg_managed_mutation_admission();

CREATE FUNCTION private.trg_managed_auth_projection() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE actual jsonb;
BEGIN
 -- Access can always be irreversibly removed after provider logout. This
 -- exception changes no identity, expiry or assurance and cannot renew access.
 IF TG_OP='UPDATE' THEN
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND NEW.revocation_reason IS NOT NULL AND length(btrim(NEW.revocation_reason))>0 AND NEW.revoked_at>=OLD.created_at AND to_jsonb(OLD)-ARRAY['revoked_at','revocation_reason']=to_jsonb(NEW)-ARRAY['revoked_at','revocation_reason'] THEN RETURN NEW;END IF;
 END IF;
 SELECT to_jsonb(s) INTO actual FROM auth.sessions s JOIN private.auth_principal_links l ON l.auth_user_id=s.user_id WHERE s.id::text=NEW.id AND l.user_id=NEW.user_id;
 IF actual IS NULL THEN RAISE EXCEPTION 'managed_session_required' USING ERRCODE='42501'; END IF;
 IF NEW.assurance_level=2 AND actual->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'managed_mfa_required' USING ERRCODE='42501'; END IF;
 IF actual->>'not_after' IS NOT NULL AND NEW.expires_at>extract(epoch FROM (actual->>'not_after')::timestamptz)::bigint THEN RAISE EXCEPTION 'managed_session_expiry_exceeded' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER managed_auth_projection BEFORE INSERT OR UPDATE ON app.auth_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_managed_auth_projection();

-- Curated replacement of the local-TOTP claim proof. A managed Auth proof is
-- required instead of inventing a TOTP counter/challenge or copying a secret.
CREATE OR REPLACE FUNCTION private.trg_auth_mfa_verified_session() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
BEGIN
 IF TG_OP='UPDATE' THEN
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND NEW.revocation_reason IS NOT NULL AND length(btrim(NEW.revocation_reason))>0 AND NEW.revoked_at>=OLD.created_at AND to_jsonb(OLD)-ARRAY['revoked_at','revocation_reason']=to_jsonb(NEW)-ARRAY['revoked_at','revocation_reason'] THEN RETURN NEW;END IF;
 END IF;
 IF NEW.assurance_level=2 AND NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs p JOIN auth.sessions s ON s.id=p.session_id AND s.user_id=p.user_id JOIN auth.mfa_factors f ON f.id=p.factor_id AND f.user_id=p.user_id JOIN private.auth_principal_links l ON l.auth_user_id=p.user_id WHERE p.session_id::text=NEW.id AND l.user_id=NEW.user_id AND p.factor_id::text=NEW.mfa_factor_id AND p.verified_at_epoch=NEW.mfa_at AND p.verified_at_epoch>=app.unixepoch()-300 AND to_jsonb(s)->>'aal'='aal2' AND f.status::text='verified') THEN RAISE EXCEPTION 'verified_mfa_claim_required'; END IF;
 RETURN NEW;
END$$;

DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_runtime') THEN CREATE ROLE collect_runtime NOLOGIN NOINHERIT NOBYPASSRLS; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_importer') THEN CREATE ROLE collect_importer NOLOGIN NOINHERIT NOBYPASSRLS; END IF;
END$$;
GRANT USAGE ON SCHEMA app,private,api TO collect_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA app TO collect_runtime;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA app TO collect_runtime;
GRANT SELECT,INSERT ON private.auth_principal_links TO collect_runtime;
GRANT SELECT,INSERT,UPDATE ON private.supabase_otp_challenges TO collect_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.bff_sessions TO collect_runtime;
GRANT SELECT,INSERT ON private.storage_namespace TO collect_runtime;
GRANT SELECT,INSERT,UPDATE ON private.storage_payload_reservations,private.storage_put_intents,private.storage_upload_attempts,private.storage_delete_intents TO collect_runtime;
GRANT SELECT,INSERT,DELETE ON private.storage_objects TO collect_runtime;
GRANT SELECT ON private.object_metadata TO collect_runtime;
-- Managed MFA proofs can only be written by the verified helper.
GRANT SELECT ON private.managed_mfa_proofs TO collect_runtime;
GRANT SELECT ON private.managed_phone_verifications TO collect_runtime;
GRANT SELECT,INSERT ON private.google_flow_context TO collect_runtime;
REVOKE ALL ON ALL TABLES IN SCHEMA app,private FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private,api FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app,private TO collect_runtime;
GRANT EXECUTE ON FUNCTION api.current_principal_id(),api.current_session_id() TO collect_runtime;
DO $$DECLARE t record; r text; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='app' LOOP
  EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('CREATE POLICY edge_runtime ON app.%I FOR ALL TO collect_runtime USING (true) WITH CHECK (true)',t.tablename);
 END LOOP;
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='private' LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('CREATE POLICY edge_runtime ON private.%I FOR ALL TO collect_runtime USING (true) WITH CHECK (true)',t.tablename);
 END LOOP;
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   EXECUTE format('REVOKE ALL ON SCHEMA app,private FROM %I',r);
   EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA app,private FROM %I',r);
   EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private FROM %I',r);
   EXECUTE format('GRANT USAGE ON SCHEMA api TO %I',r);
  END IF;
 END LOOP;
END$$;
ALTER DEFAULT PRIVILEGES IN SCHEMA app,private,api REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA app,private,api REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE OR REPLACE VIEW app.assisted_sms_current_jobs WITH (security_invoker=true) AS SELECT j . * FROM assisted_sms_jobs j JOIN payments p ON p . id = j . payment_id JOIN ledger_entries e ON e . id = j . entry_id AND e . payment_id = p . id JOIN collections c ON c . id = j . collection_id JOIN users u ON u . id = j . recipient_user_id JOIN memberships m ON m . collection_id = c . id AND m . user_id = u . id JOIN assisted_sms_policies policy ON policy . collection_id = c . id JOIN assisted_sms_authorizations consent ON consent . collection_id = c . id AND consent . recipient_user_id = u . id WHERE p . collection_id = c . id AND p . member_id = u . id AND p . revision = j . payment_revision AND p . status IN ( 'reconciled' , 'confirmed' ) AND p . currency = 'RWF' AND p . rail = 'rwanda_momo' AND e . kind = 'contribution' AND e . amount_minor = j . amount_minor AND p . amount_minor = j . amount_minor AND e . collection_id = c . id AND e . member_id = u . id AND e . evidence_id = p . evidence_id AND e . currency = 'RWF' AND NOT EXISTS ( SELECT 1 FROM ledger_entries inverse WHERE inverse . reverses_entry_id = e . id ) AND c . status = 'active' AND u . access_status = 'active' AND u . member_type != 'operator' AND m . active = 1 AND policy . enabled = 1 AND policy . revision = j . policy_revision AND policy . template_key = j . template_key AND policy . approval_reference_sha256 = j . policy_approval_sha256 AND consent . enabled = 1 AND consent . consent_revision = j . consent_revision AND consent . authorization_receipt_sha256 = j . authorization_receipt_sha256 AND consent . destination_revision = j . destination_revision AND consent . destination_sha256 = j . destination_sha256 AND consent . destination_ciphertext = j . destination_ciphertext AND ( u . member_type != 'app' OR private . managed_phone_binding ( u . id , consent . phone_verification_challenge_id , u . phone ) OR EXISTS ( SELECT 1 FROM auth_otp_verifications proof JOIN auth_otp_challenges challenge ON challenge . id = proof . challenge_id WHERE proof . user_id = u . id AND proof . challenge_id = consent . phone_verification_challenge_id AND challenge . identity_type = 'phone' AND challenge . surface = 'member' AND challenge . identity_value = u . phone AND challenge . status = 'consumed' AND challenge . consumed_operation_id = proof . operation_id AND challenge . consumed_at = proof . verified_at AND proof . verified_at BETWEEN challenge . created_at AND challenge . expires_at ) );
-- One group lock serializes independent payments before aggregates/snapshots.
-- All existing domain batches run in one transaction; trigger locking also
-- covers callers that append through the dedicated runtime connection.
CREATE FUNCTION private.trg_lock_collection_accounting() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
BEGIN
 PERFORM 1 FROM app.collections WHERE id=NEW.collection_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'collection_unavailable' USING ERRCODE='23503'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER accounting_collection_lock BEFORE INSERT ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION private.trg_lock_collection_accounting();

CREATE FUNCTION private.lock_collections(collection_ids text[]) RETURNS void LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE item text;
BEGIN
 FOR item IN SELECT DISTINCT unnest(collection_ids) ORDER BY 1 LOOP
  PERFORM 1 FROM app.collections WHERE id=item FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'collection_unavailable' USING ERRCODE='23503'; END IF;
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.lock_collections(text[]) TO collect_runtime;

-- All financial commands remain in the canonical domain adapters. No second
-- shortened reversal/posting API is exposed by the baseline.
-- Read-only provider database inventory. Returns bounded opaque row hashes,
-- never Auth secrets/tokens/emails/factor values or object contents. Unknown
-- managed relations fail closed. Provider logs/backups/unlinked identifiers
-- are not proven absent by this scoped database observation.
CREATE FUNCTION private.retention_managed_inventory(p_subject text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE
 relation record;managed_id uuid;keys text[]:=ARRAY[]::text[];bucket_name text;
 auth_rows jsonb:='[]';storage_rows jsonb:='[]';found jsonb;schema_rows jsonb;schema_identity jsonb;
 predicate text;sql_text text;auth_status text;storage_status text;has_storage boolean;bucket_private boolean:=false;storage_count bigint:=0;
 known_auth text[]:=ARRAY['audit_log_entries','custom_oauth_providers','flow_state','identities','instances','mfa_amr_claims','mfa_challenges','mfa_factors','mfa_recovery_code_sets','mfa_recovery_codes','oauth_authorizations','oauth_client_states','oauth_clients','oauth_consents','one_time_tokens','refresh_tokens','saml_providers','saml_relay_states','schema_migrations','scim_tokens','scim_users','sessions','sso_domains','sso_providers','users','webauthn_challenges','webauthn_credentials'];
 known_storage text[]:=ARRAY['buckets','buckets_analytics','buckets_vectors','migrations','objects','s3_multipart_uploads','s3_multipart_uploads_parts','vector_indexes'];
BEGIN
 PERFORM private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF p_subject IS NOT NULL AND (length(p_subject)<1 OR length(p_subject)>200) THEN RAISE EXCEPTION 'retention_subject_invalid' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'kind',c.relkind,
  'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'foreign_keys',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid AND x.contype='f')) ORDER BY n.nspname,c.relname),'[]') INTO schema_rows
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('auth','storage') AND c.relkind IN('r','p');
 FOR relation IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('auth','storage') AND c.relkind IN('r','p') LOOP
  IF (relation.nspname='auth' AND NOT relation.relname=ANY(known_auth)) OR (relation.nspname='storage' AND NOT relation.relname=ANY(known_storage)) THEN RAISE EXCEPTION 'retention_unknown_managed_relation' USING ERRCODE='42501';END IF;
 END LOOP;
 schema_identity:=jsonb_build_object('sha256',encode(sha256(convert_to(schema_rows::text,'UTF8')),'hex'),'contract','collect.managed.inventory.v1');
 SELECT auth_user_id INTO managed_id FROM private.auth_principal_links WHERE user_id=p_subject;
 SELECT bucket INTO bucket_name FROM private.storage_namespace WHERE singleton;
 SELECT coalesce(array_agg(object_key ORDER BY object_key),ARRAY[]::text[]) INTO keys FROM (
  (SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=p_subject LIMIT 501)
  UNION (SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=p_subject LIMIT 501)
  UNION (SELECT object_key FROM app.payment_evidence WHERE owner_user_id=p_subject LIMIT 501)
  UNION (SELECT object_key FROM app.sms_receipts WHERE owner_user_id=p_subject LIMIT 501)
  UNION (SELECT source_object_key FROM app.roster_imports WHERE user_id=p_subject LIMIT 501)
  UNION (SELECT object_key FROM app.upload_objects WHERE user_id=p_subject LIMIT 501)
  LIMIT 501
 ) owned;
 IF cardinality(keys)>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
 FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='auth' AND c.relkind IN('r','p') ORDER BY c.relname LOOP
  predicate:=CASE relation.relname
   WHEN 'users' THEN 'r.id=$1'
   WHEN 'refresh_tokens' THEN 'r.user_id=$1::text OR r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'flow_state' THEN 'r.user_id=$1 OR to_jsonb(r)->>''linking_target_id''=$1::text'
   WHEN 'mfa_amr_claims' THEN 'r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'mfa_challenges' THEN 'r.factor_id IN(SELECT id FROM auth.mfa_factors WHERE user_id=$1)'
   WHEN 'mfa_recovery_codes' THEN 'r.mfa_recovery_code_set_id IN(SELECT id FROM auth.mfa_recovery_code_sets WHERE user_id=$1)'
   WHEN 'oauth_client_states' THEN 'r.id IN(SELECT (to_jsonb(f)->>''oauth_client_state_id'')::uuid FROM auth.flow_state f WHERE f.user_id=$1 OR to_jsonb(f)->>''linking_target_id''=$1::text)'
   WHEN 'saml_relay_states' THEN 'r.flow_state_id IN(SELECT id FROM auth.flow_state WHERE user_id=$1)'
   WHEN 'audit_log_entries' THEN 'r.payload::jsonb->>''actor_id''=$1::text OR r.payload::jsonb->>''user_id''=$1::text'
   WHEN 'custom_oauth_providers' THEN NULL WHEN 'instances' THEN NULL WHEN 'oauth_clients' THEN NULL WHEN 'saml_providers' THEN NULL WHEN 'schema_migrations' THEN NULL WHEN 'scim_tokens' THEN NULL WHEN 'sso_domains' THEN NULL WHEN 'sso_providers' THEN NULL
   ELSE 'r.user_id=$1' END;
  -- Shared provider configuration has no subject ownership column. Its schema
  -- is bound above; its contents are not represented as erased subject copies.
  IF predicate IS NULL OR managed_id IS NULL THEN CONTINUE;END IF;
  sql_text:=format('SELECT coalesce(jsonb_agg(jsonb_build_object(''key_sha256'',encode(sha256(convert_to(%L||'':''||coalesce(to_jsonb(q)->>''id'',to_jsonb(q)->>''session_id'')||'':''||coalesce(to_jsonb(q)->>''authentication_method'',''''),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(q)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(q)::text,''UTF8'')),''hex''),''lifecycle'',''{}''::jsonb) ORDER BY to_jsonb(q)::text),''[]'') FROM (SELECT r.* FROM auth.%I r WHERE %s LIMIT 501) q',relation.relname,relation.relname,predicate);
  EXECUTE sql_text INTO found USING managed_id;
  auth_rows:=auth_rows||found;
  IF jsonb_array_length(auth_rows)>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
 END LOOP;
 has_storage:=to_regclass('storage.objects') IS NOT NULL AND to_regclass('storage.buckets') IS NOT NULL;
 IF has_storage AND bucket_name IS NOT NULL THEN EXECUTE 'SELECT coalesce(public=false,false) FROM storage.buckets WHERE id=$1' INTO bucket_private USING bucket_name;END IF;
 IF has_storage AND bucket_name IS NOT NULL THEN
  FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='storage' AND c.relkind IN('r','p') AND c.relname IN('objects','s3_multipart_uploads','s3_multipart_uploads_parts') ORDER BY c.relname LOOP
   predicate:=CASE relation.relname WHEN 'objects' THEN 'r.name=ANY($2) OR to_jsonb(r)->>''owner_id''=$1::text OR to_jsonb(r)->>''owner''=$1::text' ELSE 'r.key=ANY($2) OR to_jsonb(r)->>''owner_id''=$1::text' END;
   sql_text:=format('SELECT coalesce(jsonb_agg(jsonb_build_object(''key_sha256'',encode(sha256(convert_to(object_key,''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(body::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(body::text,''UTF8'')),''hex''),''lifecycle'',jsonb_build_object(''catalog_rows'',jsonb_array_length(body))) ORDER BY object_key),''[]'') FROM (SELECT %s AS object_key,jsonb_agg(jsonb_build_object(''relation'',%L,''value'',to_jsonb(r)) ORDER BY to_jsonb(r)::text) AS body FROM (SELECT * FROM storage.%I r WHERE r.bucket_id=$3 AND (%s) LIMIT 501) r GROUP BY %s) grouped',CASE WHEN relation.relname='objects' THEN 'r.name' ELSE 'r.key' END,relation.relname,relation.relname,predicate,CASE WHEN relation.relname='objects' THEN 'r.name' ELSE 'r.key' END);
   EXECUTE sql_text INTO found USING managed_id,keys,bucket_name;
   storage_count:=storage_count+(SELECT coalesce(sum((item->'lifecycle'->>'catalog_rows')::bigint),0) FROM jsonb_array_elements(found) item);
   IF storage_count>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
   storage_rows:=storage_rows||found;
   IF jsonb_array_length(storage_rows)>500 THEN RAISE EXCEPTION 'retention_managed_inventory_limit' USING ERRCODE='54000';END IF;
  END LOOP;
 END IF;
 -- Multiple managed mirror relations for one key are folded into one opaque
 -- descriptor, including every actual archived/version/part row observed.
 SELECT coalesce(jsonb_agg(jsonb_build_object('key_sha256',key_sha256,'row_sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex'),'identity_sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex'),'lifecycle',jsonb_build_object('mirror_groups',jsonb_array_length(items),'catalog_rows',(SELECT sum((part->'lifecycle'->>'catalog_rows')::bigint) FROM jsonb_array_elements(items) part))) ORDER BY key_sha256),'[]') INTO storage_rows
 FROM (SELECT item->>'key_sha256' AS key_sha256,jsonb_agg(item ORDER BY item::text) AS items FROM jsonb_array_elements(storage_rows) item GROUP BY item->>'key_sha256') folded;
 SELECT coalesce(jsonb_agg(item ORDER BY item->>'key_sha256'),'[]') INTO auth_rows FROM jsonb_array_elements(auth_rows) item;
 auth_status:=CASE WHEN managed_id IS NULL THEN 'unmapped' ELSE 'observed' END;
 storage_status:=CASE WHEN has_storage AND bucket_name IS NOT NULL AND bucket_private THEN 'observed' ELSE 'unavailable' END;
 RETURN jsonb_build_object('contract_version',1,'schema',schema_identity,'classes',jsonb_build_object(
  'managed:auth',jsonb_build_object('status',auth_status,'count',jsonb_array_length(auth_rows),'rows',auth_rows),
  'managed:storage',jsonb_build_object('status',storage_status,'count',storage_count,'rows',storage_rows)));
END$$;
REVOKE ALL ON FUNCTION private.retention_managed_inventory(text) FROM PUBLIC;
DO $$DECLARE r text;BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON FUNCTION private.retention_managed_inventory(text) FROM %I',r);END IF;
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.retention_managed_inventory(text) TO collect_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private,api FROM PUBLIC;
DO $$DECLARE r text;BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private,api FROM %I',r);END IF;END LOOP;END$$;
COMMIT;
