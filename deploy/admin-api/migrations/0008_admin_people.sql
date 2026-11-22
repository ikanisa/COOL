-- System directory identities and explicit App/Direct membership classification.
-- Preserve existing App semantics; expired/no sessions do not imply Direct.
-- A recorded operator link is explicit, never inferred from matching emails.
PRAGMA foreign_keys=ON;

ALTER TABLE collect_users ADD COLUMN member_type TEXT NOT NULL DEFAULT 'app' CHECK(member_type IN ('app','direct'));
ALTER TABLE collect_users ADD COLUMN operator_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX collect_users_operator_link ON collect_users(operator_admin_id) WHERE operator_admin_id IS NOT NULL;
ALTER TABLE admin_users ADD COLUMN display_name TEXT NOT NULL DEFAULT '' CHECK(length(trim(display_name))<=120);
ALTER TABLE collect_profiles ADD COLUMN display_name_recorded INTEGER NOT NULL DEFAULT 1 CHECK(display_name_recorded IN (0,1));
-- The member-auth producer's exact placeholder is known source provenance.
-- Do not infer unknown names from emails, missing sessions or other names.
UPDATE collect_profiles SET display_name_recorded=0 WHERE display_name='Collect member';

-- Reserve identifiers across both account stores. Linked operators keep their
-- original public identifier as an alias of the canonical Collect person.
CREATE TABLE collect_public_identities (
 source_id TEXT PRIMARY KEY NOT NULL,
 public_id TEXT NOT NULL UNIQUE CHECK(length(public_id)=6 AND public_id NOT GLOB '*[^0-9]*'),
 collect_user_id TEXT UNIQUE REFERENCES collect_users(id) ON DELETE RESTRICT,
 admin_user_id TEXT UNIQUE REFERENCES admin_users(id) ON DELETE RESTRICT,
 CHECK(source_id=COALESCE(collect_user_id,admin_user_id)),
 CHECK((collect_user_id IS NOT NULL)!=(admin_user_id IS NOT NULL))
) STRICT;
INSERT INTO collect_public_identities(source_id,public_id,collect_user_id)
 SELECT user_id,public_id,user_id FROM collect_profiles;

-- Select the lowest free boundary in the finite six-digit namespace. The query
-- is index-backed and does not generate a million candidate rows. Exhaustion
-- yields NULL and fails atomically instead of recycling another person's ID.
CREATE TABLE collect_people_identity_backfill (source_id TEXT PRIMARY KEY,kind TEXT NOT NULL);
CREATE TRIGGER collect_people_identity_backfill_insert AFTER INSERT ON collect_people_identity_backfill
BEGIN
 INSERT INTO collect_public_identities(source_id,public_id,collect_user_id,admin_user_id)
 SELECT NEW.source_id,
  (SELECT (CASE WHEN min(candidate) IS NULL THEN NULL ELSE printf('%06d',min(candidate)) END) FROM
   (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM collect_public_identities WHERE public_id!='999999') c
   WHERE NOT EXISTS(SELECT 1 FROM collect_public_identities i WHERE i.public_id=printf('%06d',c.candidate))),
  (CASE WHEN NEW.kind='collect' THEN NEW.source_id END),(CASE WHEN NEW.kind='operator' THEN NEW.source_id END);
END;
INSERT INTO collect_people_identity_backfill(source_id,kind) SELECT id,'operator' FROM admin_users ORDER BY created_at,id;
INSERT INTO collect_people_identity_backfill(source_id,kind)
 SELECT id,'collect' FROM collect_users WHERE NOT EXISTS(SELECT 1 FROM collect_public_identities WHERE source_id=collect_users.id) ORDER BY created_at,id;
DROP TRIGGER collect_people_identity_backfill_insert;
DROP TABLE collect_people_identity_backfill;

CREATE TRIGGER collect_operator_public_identity AFTER INSERT ON admin_users
BEGIN
 INSERT INTO collect_public_identities(source_id,public_id,admin_user_id)
 SELECT NEW.id,(SELECT (CASE WHEN min(candidate) IS NULL THEN NULL ELSE printf('%06d',min(candidate)) END) FROM
  (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM collect_public_identities WHERE public_id!='999999') c
  WHERE NOT EXISTS(SELECT 1 FROM collect_public_identities i WHERE i.public_id=printf('%06d',c.candidate))),NEW.id;
END;
CREATE TRIGGER collect_profile_public_identity AFTER INSERT ON collect_profiles
BEGIN
 INSERT INTO collect_public_identities(source_id,public_id,collect_user_id) VALUES(NEW.user_id,NEW.public_id,NEW.user_id)
  ON CONFLICT(source_id) DO NOTHING;
 SELECT (CASE WHEN (SELECT public_id FROM collect_public_identities WHERE source_id=NEW.user_id) IS NOT NEW.public_id
  THEN RAISE(ABORT,'A person keeps the reserved public identifier') END);
END;
CREATE TRIGGER collect_public_identity_no_update BEFORE UPDATE ON collect_public_identities
BEGIN SELECT RAISE(ABORT,'Public person identifiers are immutable'); END;
CREATE TRIGGER collect_public_identity_no_delete BEFORE DELETE ON collect_public_identities
BEGIN SELECT RAISE(ABORT,'Public person identifiers remain reserved'); END;
CREATE TRIGGER collect_profile_public_identity_immutable BEFORE UPDATE OF public_id,user_id ON collect_profiles
WHEN NEW.public_id IS NOT OLD.public_id OR NEW.user_id IS NOT OLD.user_id
BEGIN SELECT RAISE(ABORT,'Public person identifiers are immutable'); END;

-- Direct members never acquire App authentication merely because an email or
-- phone was recorded. Explicit conversion revokes old sessions; a new App
-- session still requires the separate member OTP authentication workflow.
CREATE TRIGGER collect_direct_member_no_session BEFORE INSERT ON member_sessions
WHEN (SELECT member_type FROM collect_users WHERE id=NEW.user_id)!='app'
BEGIN SELECT RAISE(ABORT,'Direct members do not have App authentication'); END;
CREATE TRIGGER collect_direct_member_revoke AFTER UPDATE OF member_type ON collect_users
WHEN NEW.member_type='direct'
BEGIN DELETE FROM member_sessions WHERE user_id=NEW.id; END;

-- Recorded payment identity: names remain recorded data, not a claim that a
-- provider has independently verified them. Missing numbers/codes stay empty.
CREATE TRIGGER collect_profile_momo_insert BEFORE INSERT ON collect_profiles
BEGIN
 SELECT (CASE WHEN NEW.momo_number!='' AND NOT(length(NEW.momo_number)=10 AND substr(NEW.momo_number,1,2)='07'
  AND substr(NEW.momo_number,3,1) IN ('2','3','8','9') AND NEW.momo_number NOT GLOB '*[^0-9]*')
  THEN RAISE(ABORT,'Use a recorded Rwanda MoMo number') END);
 SELECT (CASE WHEN NEW.momo_pay_code!='' AND NOT(length(NEW.momo_pay_code) BETWEEN 4 AND 9 AND NEW.momo_pay_code NOT GLOB '*[^0-9]*')
  THEN RAISE(ABORT,'Use a numeric recorded MoMo code') END);
 SELECT (CASE WHEN NEW.momo_number!='' AND ((NEW.momo_provider='mtn_momo' AND substr(NEW.momo_number,3,1) NOT IN ('8','9'))
  OR (NEW.momo_provider='airtel_money' AND substr(NEW.momo_number,3,1) NOT IN ('2','3')))
  THEN RAISE(ABORT,'The recorded number does not match the selected MoMo provider') END);
END;
CREATE TRIGGER collect_profile_momo_update BEFORE UPDATE OF momo_number,momo_pay_code,momo_provider ON collect_profiles
BEGIN
 SELECT (CASE WHEN NEW.momo_number!='' AND NOT(length(NEW.momo_number)=10 AND substr(NEW.momo_number,1,2)='07'
  AND substr(NEW.momo_number,3,1) IN ('2','3','8','9') AND NEW.momo_number NOT GLOB '*[^0-9]*')
  THEN RAISE(ABORT,'Use a recorded Rwanda MoMo number') END);
 SELECT (CASE WHEN NEW.momo_pay_code!='' AND NOT(length(NEW.momo_pay_code) BETWEEN 4 AND 9 AND NEW.momo_pay_code NOT GLOB '*[^0-9]*')
  THEN RAISE(ABORT,'Use a numeric recorded MoMo code') END);
 SELECT (CASE WHEN NEW.momo_number!='' AND ((NEW.momo_provider='mtn_momo' AND substr(NEW.momo_number,3,1) NOT IN ('8','9'))
  OR (NEW.momo_provider='airtel_money' AND substr(NEW.momo_number,3,1) NOT IN ('2','3')))
  THEN RAISE(ABORT,'The recorded number does not match the selected MoMo provider') END);
END;
