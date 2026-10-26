PRAGMA foreign_keys = ON;

-- Preserve every historical challenge/claim and its original hash bytes. The
-- default names the exact predecessor domain/key; it never relabels it as new.
ALTER TABLE auth_otp_challenges ADD COLUMN identity_key_id TEXT NOT NULL
 DEFAULT 'legacy-token-hash-v1'
 CHECK(length(identity_key_id) BETWEEN 1 AND 128
   AND substr(identity_key_id,1,1) GLOB '[A-Za-z0-9]'
   AND identity_key_id NOT GLOB '*[^A-Za-z0-9._:-]*');
ALTER TABLE auth_rate_claims ADD COLUMN identity_key_id TEXT NOT NULL
 DEFAULT 'legacy-token-hash-v1'
 CHECK(length(identity_key_id) BETWEEN 1 AND 128
   AND substr(identity_key_id,1,1) GLOB '[A-Za-z0-9]'
   AND identity_key_id NOT GLOB '*[^A-Za-z0-9._:-]*');
ALTER TABLE auth_rate_claims ADD COLUMN identity_aliases_json TEXT NOT NULL
 DEFAULT '[]' CHECK(json_valid(identity_aliases_json) AND json_type(identity_aliases_json)='array');
ALTER TABLE auth_otp_throttles ADD COLUMN identity_key_id TEXT NOT NULL
 DEFAULT 'legacy-token-hash-v1'
 CHECK(length(identity_key_id) BETWEEN 1 AND 128
   AND substr(identity_key_id,1,1) GLOB '[A-Za-z0-9]'
   AND identity_key_id NOT GLOB '*[^A-Za-z0-9._:-]*');

CREATE TABLE auth_identity_rate_aliases (
 request_id TEXT NOT NULL REFERENCES auth_rate_claims(request_id),
 identity_key_id TEXT NOT NULL CHECK(length(identity_key_id) BETWEEN 1 AND 128
   AND substr(identity_key_id,1,1) GLOB '[A-Za-z0-9]'
   AND identity_key_id NOT GLOB '*[^A-Za-z0-9._:-]*'),
 identity_hash TEXT NOT NULL CHECK(length(identity_hash)=64 AND identity_hash NOT GLOB '*[^0-9a-f]*'),
 requested_at INTEGER NOT NULL,
 hourly_window_ends_at INTEGER NOT NULL,
 PRIMARY KEY(request_id,identity_key_id), UNIQUE(request_id,identity_hash)
);
CREATE INDEX auth_identity_alias_window
 ON auth_identity_rate_aliases(identity_hash,hourly_window_ends_at,request_id);
INSERT INTO auth_identity_rate_aliases(request_id,identity_key_id,identity_hash,requested_at,hourly_window_ends_at)
 SELECT request_id,'legacy-token-hash-v1',identity_hash,requested_at,hourly_window_ends_at
 FROM auth_rate_claims;

DROP TRIGGER auth_rate_admission;
CREATE TRIGGER auth_rate_admission BEFORE INSERT ON auth_rate_claims BEGIN
 SELECT CASE WHEN length(NEW.identity_hash)!=64 OR NEW.identity_hash GLOB '*[^0-9a-f]*'
   OR json_array_length(NEW.identity_aliases_json)>10
   OR (json_array_length(NEW.identity_aliases_json)=0 AND NEW.identity_key_id!='legacy-token-hash-v1')
   OR (NEW.identity_key_id!='legacy-token-hash-v1' AND NOT EXISTS(
     SELECT 1 FROM json_each(NEW.identity_aliases_json)
     WHERE json_extract(value,'$.key_id')='legacy-token-hash-v1'))
   OR EXISTS(SELECT 1 FROM json_each(NEW.identity_aliases_json) e
     WHERE e.type!='object' OR (SELECT count(*) FROM json_each(e.value))!=2
       OR json_type(e.value,'$.key_id') IS NOT 'text'
       OR json_type(e.value,'$.identity_hash') IS NOT 'text'
       OR length(json_extract(e.value,'$.key_id')) NOT BETWEEN 1 AND 128
       OR substr(json_extract(e.value,'$.key_id'),1,1) NOT GLOB '[A-Za-z0-9]'
       OR json_extract(e.value,'$.key_id') GLOB '*[^A-Za-z0-9._:-]*'
       OR length(json_extract(e.value,'$.identity_hash'))!=64
       OR json_extract(e.value,'$.identity_hash') GLOB '*[^0-9a-f]*')
   OR (SELECT count(*) FROM json_each(NEW.identity_aliases_json))!=
      (SELECT count(DISTINCT json_extract(value,'$.key_id')) FROM json_each(NEW.identity_aliases_json))
   OR (SELECT count(*) FROM json_each(NEW.identity_aliases_json))!=
      (SELECT count(DISTINCT json_extract(value,'$.identity_hash')) FROM json_each(NEW.identity_aliases_json))
   OR (json_array_length(NEW.identity_aliases_json)>0 AND NOT EXISTS(
     SELECT 1 FROM json_each(NEW.identity_aliases_json)
     WHERE json_extract(value,'$.key_id')=NEW.identity_key_id
       AND json_extract(value,'$.identity_hash')=NEW.identity_hash))
   OR EXISTS(SELECT 1 FROM auth_identity_rate_aliases existing JOIN (
     SELECT NEW.identity_hash AS identity_hash,NEW.identity_key_id AS key_id UNION
     SELECT json_extract(value,'$.identity_hash'),json_extract(value,'$.key_id')
       FROM json_each(NEW.identity_aliases_json)
   ) incoming ON incoming.identity_hash=existing.identity_hash
     WHERE incoming.key_id!=existing.identity_key_id)
 THEN RAISE(ABORT,'auth_identity_aliases_invalid') END;
 -- Count each real request once, across all configured hashes. An older
 -- application writer's empty alias list still shares the legacy index entry.
 SELECT CASE WHEN
   (SELECT count(DISTINCT request_id) FROM auth_identity_rate_aliases
     WHERE identity_hash IN(SELECT NEW.identity_hash UNION
       SELECT json_extract(value,'$.identity_hash') FROM json_each(NEW.identity_aliases_json))
       AND hourly_window_ends_at>NEW.requested_at)>=NEW.identity_limit
   OR COALESCE((SELECT used FROM auth_rate_buckets WHERE bucket_key=NEW.ip_bucket),0)>=NEW.ip_limit
   OR COALESCE((SELECT used FROM auth_rate_buckets WHERE bucket_key=NEW.global_bucket),0)>=NEW.global_limit
   OR EXISTS(SELECT 1 FROM auth_otp_throttles
     WHERE identity_hash IN(SELECT NEW.identity_hash UNION
       SELECT json_extract(value,'$.identity_hash') FROM json_each(NEW.identity_aliases_json))
       AND last_requested_at+NEW.cooldown_seconds>NEW.requested_at)
 THEN RAISE(ABORT,'auth_rate_limited') END;
 INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at)
 VALUES(NEW.identity_bucket,1,NEW.hourly_window_ends_at)
 ON CONFLICT(bucket_key) DO UPDATE SET used=used+1;
 INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at)
 VALUES(NEW.ip_bucket,1,NEW.hourly_window_ends_at)
 ON CONFLICT(bucket_key) DO UPDATE SET used=used+1;
 INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at)
 VALUES(NEW.global_bucket,1,NEW.daily_window_ends_at)
 ON CONFLICT(bucket_key) DO UPDATE SET used=used+1;
 INSERT INTO auth_otp_throttles(identity_hash,last_requested_at,identity_key_id)
 SELECT incoming.identity_hash,NEW.requested_at,incoming.key_id FROM (
   SELECT NEW.identity_hash AS identity_hash,NEW.identity_key_id AS key_id UNION
   SELECT json_extract(value,'$.identity_hash'),json_extract(value,'$.key_id')
     FROM json_each(NEW.identity_aliases_json)
 ) incoming WHERE 1
 ON CONFLICT(identity_hash) DO UPDATE SET last_requested_at=excluded.last_requested_at;
END;

CREATE TRIGGER auth_identity_alias_capture AFTER INSERT ON auth_rate_claims BEGIN
 INSERT INTO auth_identity_rate_aliases(request_id,identity_key_id,identity_hash,requested_at,hourly_window_ends_at)
 SELECT NEW.request_id,incoming.key_id,incoming.identity_hash,NEW.requested_at,NEW.hourly_window_ends_at
 FROM (SELECT NEW.identity_hash AS identity_hash,NEW.identity_key_id AS key_id UNION
   SELECT json_extract(value,'$.identity_hash'),json_extract(value,'$.key_id')
     FROM json_each(NEW.identity_aliases_json)) incoming;
END;
CREATE TRIGGER auth_identity_alias_supersession BEFORE INSERT ON auth_otp_challenges BEGIN
 UPDATE auth_otp_challenges SET status='superseded'
 WHERE surface=NEW.surface AND status IN('dispatching','accepted','delivery_unknown')
   AND id IN(SELECT prior.request_id FROM auth_identity_rate_aliases incoming
     JOIN auth_identity_rate_aliases prior ON prior.identity_hash=incoming.identity_hash
     WHERE incoming.request_id=NEW.id);
END;
CREATE TRIGGER auth_identity_alias_no_update BEFORE UPDATE ON auth_identity_rate_aliases
 BEGIN SELECT RAISE(ABORT,'auth_identity_alias_immutable'); END;
CREATE TRIGGER auth_identity_alias_no_delete BEFORE DELETE ON auth_identity_rate_aliases
 BEGIN SELECT RAISE(ABORT,'auth_identity_alias_immutable'); END;
CREATE TRIGGER auth_otp_identity_no_relabel BEFORE UPDATE OF identity_key_id,identity_hash,identity_type,identity_value,code_hash
 ON auth_otp_challenges WHEN NEW.identity_key_id!=OLD.identity_key_id OR NEW.identity_hash!=OLD.identity_hash
   OR NEW.identity_type!=OLD.identity_type OR NEW.identity_value!=OLD.identity_value OR NEW.code_hash!=OLD.code_hash
 BEGIN SELECT RAISE(ABORT,'auth_identity_history_immutable'); END;
CREATE TRIGGER auth_rate_identity_no_relabel BEFORE UPDATE OF identity_key_id,identity_hash,identity_aliases_json
 ON auth_rate_claims WHEN NEW.identity_key_id!=OLD.identity_key_id OR NEW.identity_hash!=OLD.identity_hash
   OR NEW.identity_aliases_json!=OLD.identity_aliases_json
 BEGIN SELECT RAISE(ABORT,'auth_identity_history_immutable'); END;
