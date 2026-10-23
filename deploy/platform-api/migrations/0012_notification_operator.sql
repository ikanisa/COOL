-- Private candidate only. No transport, automatic messages, recipient consent,
-- account grant or existing deployment is activated by this migration.
PRAGMA foreign_keys=ON;
INSERT INTO admin_account_role_capabilities(role,permission) VALUES
 ('owner','assisted_sms.read'),('owner','assisted_sms.manage');
CREATE TABLE assisted_sms_policies (
 collection_id TEXT PRIMARY KEY REFERENCES collections(id), enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1)),
 revision INTEGER NOT NULL CHECK(revision>0), template_key TEXT NOT NULL CHECK(template_key='collect.recorded_contribution.v1'),
 approval_reference_sha256 TEXT NOT NULL CHECK(length(approval_reference_sha256)=64 AND approval_reference_sha256 NOT GLOB '*[^0-9a-f]*'),
 updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE assisted_sms_authorizations (
 collection_id TEXT NOT NULL REFERENCES collections(id), recipient_user_id TEXT NOT NULL REFERENCES users(id),
 enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1)), consent_revision INTEGER NOT NULL CHECK(consent_revision>0),
 destination_revision INTEGER NOT NULL CHECK(destination_revision>0), destination_ciphertext TEXT NOT NULL CHECK(json_valid(destination_ciphertext)),
 destination_sha256 TEXT NOT NULL CHECK(length(destination_sha256)=64 AND destination_sha256 NOT GLOB '*[^0-9a-f]*'),
 -- This is a fail-closed proof reference, not an additional retention FK.
 -- Approved proof cleanup/redaction invalidates current app authorization;
 -- it must not acquire an indefinite OTP-material hold from this feature.
 phone_verification_challenge_id TEXT CHECK(phone_verification_challenge_id IS NULL OR length(phone_verification_challenge_id)=36),
 authorization_receipt_sha256 TEXT NOT NULL CHECK(length(authorization_receipt_sha256)=64 AND authorization_receipt_sha256 NOT GLOB '*[^0-9a-f]*'),
 updated_at TEXT NOT NULL, PRIMARY KEY(collection_id,recipient_user_id)
) STRICT;
CREATE TABLE assisted_sms_jobs (
 id TEXT PRIMARY KEY, payment_id TEXT NOT NULL UNIQUE REFERENCES payments(id), entry_id TEXT NOT NULL UNIQUE REFERENCES ledger_entries(id),
 collection_id TEXT NOT NULL REFERENCES collections(id), recipient_user_id TEXT NOT NULL REFERENCES users(id),
 payment_revision INTEGER NOT NULL CHECK(payment_revision>0), amount_minor INTEGER NOT NULL CHECK(amount_minor>0 AND amount_minor<=9007199254740991),
 destination_revision INTEGER NOT NULL CHECK(destination_revision>0), destination_sha256 TEXT NOT NULL CHECK(length(destination_sha256)=64),
 destination_ciphertext TEXT NOT NULL CHECK(json_valid(destination_ciphertext)), consent_revision INTEGER NOT NULL CHECK(consent_revision>0),
 policy_revision INTEGER NOT NULL CHECK(policy_revision>0), policy_approval_sha256 TEXT NOT NULL CHECK(length(policy_approval_sha256)=64),
 authorization_receipt_sha256 TEXT NOT NULL CHECK(length(authorization_receipt_sha256)=64), template_key TEXT NOT NULL CHECK(template_key='collect.recorded_contribution.v1'),
 body_ciphertext TEXT NOT NULL CHECK(json_valid(body_ciphertext)), body_sha256 TEXT NOT NULL CHECK(length(body_sha256)=64),
 state TEXT NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','claimed','send_started','observed_sent','failed_no_send','uncertain')),
 fence INTEGER NOT NULL DEFAULT 0 CHECK(fence>=0), active_claim_id TEXT, created_at TEXT NOT NULL
) STRICT;
CREATE INDEX assisted_sms_pending ON assisted_sms_jobs(state,created_at,id);
CREATE TABLE assisted_sms_claims (
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL UNIQUE, job_id TEXT NOT NULL REFERENCES assisted_sms_jobs(id),
 actor_admin_id TEXT NOT NULL REFERENCES admin_users(id), actor_user_id TEXT NOT NULL REFERENCES users(id),
 originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id), public_session_id TEXT NOT NULL,
 actor_role TEXT NOT NULL, actor_auth_version INTEGER NOT NULL, actor_mfa_at INTEGER NOT NULL, origin TEXT NOT NULL,
 worker_id TEXT NOT NULL, previous_fence INTEGER NOT NULL CHECK(previous_fence>=0), fence INTEGER NOT NULL CHECK(fence=previous_fence+1),
 created_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL CHECK(expires_seconds>created_seconds),
 UNIQUE(job_id,fence)
) STRICT;
CREATE TABLE assisted_sms_confirmations (
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL UNIQUE, job_id TEXT NOT NULL REFERENCES assisted_sms_jobs(id),
 claim_id TEXT NOT NULL UNIQUE REFERENCES assisted_sms_claims(id), fence INTEGER NOT NULL,
 actor_admin_id TEXT NOT NULL REFERENCES admin_users(id), actor_user_id TEXT NOT NULL REFERENCES users(id),
 originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id), public_session_id TEXT NOT NULL,
 body_sha256 TEXT NOT NULL, destination_sha256 TEXT NOT NULL, destination_revision INTEGER NOT NULL,
 confirmed_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL CHECK(expires_seconds>confirmed_seconds)
) STRICT;
CREATE TABLE assisted_sms_send_starts (
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL UNIQUE, job_id TEXT NOT NULL UNIQUE REFERENCES assisted_sms_jobs(id),
 confirmation_id TEXT NOT NULL UNIQUE REFERENCES assisted_sms_confirmations(id), claim_id TEXT NOT NULL REFERENCES assisted_sms_claims(id), fence INTEGER NOT NULL,
 actor_admin_id TEXT NOT NULL REFERENCES admin_users(id), actor_user_id TEXT NOT NULL REFERENCES users(id),
 originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id), public_session_id TEXT NOT NULL,
 body_sha256 TEXT NOT NULL, destination_sha256 TEXT NOT NULL, destination_revision INTEGER NOT NULL,
 started_seconds INTEGER NOT NULL
) STRICT;
CREATE TABLE assisted_sms_outcomes (
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL UNIQUE, attempt_id TEXT NOT NULL UNIQUE REFERENCES assisted_sms_send_starts(id),
 observer_admin_id TEXT NOT NULL REFERENCES admin_users(id), observer_user_id TEXT NOT NULL REFERENCES users(id),
 observer_session_id TEXT NOT NULL REFERENCES auth_sessions(id), observer_public_session_id TEXT NOT NULL,
 observation TEXT NOT NULL CHECK(observation IN ('observed_sent','failed_no_send','uncertain')),
 evidence_reference_sha256 TEXT NOT NULL CHECK(length(evidence_reference_sha256)=64 AND evidence_reference_sha256 NOT GLOB '*[^0-9a-f]*'),
 observed_seconds INTEGER NOT NULL
) STRICT;
-- No implicit/bearer/service authority: this is the exact current account and
-- issued cookie session, approved principal, capped grant and verified fresh MFA.
CREATE VIEW assisted_sms_current_sessions AS
 SELECT a.id AS admin_id,l.user_id,s.auth_session_id,s.public_id,a.role,a.auth_version,s.issued_mfa_at AS mfa_at,s.origin,c.permission
 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id
 JOIN admin_principal_links l ON l.admin_user_id=a.id JOIN users u ON u.id=l.user_id
 JOIN auth_sessions ss ON ss.id=s.auth_session_id AND ss.user_id=u.id
 JOIN auth_mfa_factors f ON f.id=ss.mfa_factor_id AND f.user_id=u.id
 JOIN admin_grants g ON g.user_id=u.id JOIN admin_account_role_capabilities c ON c.permission=g.permission AND c.role=a.role
 WHERE a.status='active' AND a.auth_version=s.auth_version AND u.access_status='active' AND ss.surface='admin'
 AND s.expires_at>unixepoch() AND ss.expires_at>unixepoch() AND ss.revoked_at IS NULL
 AND s.issued_assurance_level=2 AND ss.assurance_level=2 AND f.status='verified'
 AND s.issued_mfa_at=ss.mfa_at AND s.issued_mfa_factor_id=ss.mfa_factor_id
 AND s.issued_mfa_at BETWEEN unixepoch()-300 AND unixepoch();
-- Role definitions are not a grant to an existing or newly linked principal.
-- Existing generic link/account/password flows remain usable, but silently
-- copying a new notification capability must not activate this feature.
-- Only the exact retained current-owner self-access transaction can insert
-- these two grants. Its post-write guard separately verifies both outcomes.
CREATE TRIGGER assisted_sms_grant_explicit BEFORE INSERT ON admin_grants
 WHEN NEW.permission IN('assisted_sms.read','assisted_sms.manage') BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM request_receipts r JOIN assisted_sms_current_sessions s
  ON s.auth_session_id=r.session_id AND s.user_id=r.user_id JOIN admin_users a ON a.id=s.admin_id
  WHERE s.permission='admin_users.manage' AND s.role='owner' AND a.email='info@ikanisa.com'
  AND r.operation='assisted_sms.access.set' AND r.user_id=NEW.user_id AND NEW.granted_by='admin-account:'||s.admin_id
  AND json_extract(r.response_json,'$.kind')='authenticated_owner_receipt_sms_access'
  AND json_extract(r.response_json,'$.scope')='owner_receipt_sms_access' AND json_extract(r.response_json,'$.enabled')=1
  AND json_extract(r.response_json,'$.current_admin_id')=s.admin_id AND json_extract(r.response_json,'$.current_principal_id')=s.user_id
  AND json_extract(r.response_json,'$.originating_session_id')=s.auth_session_id AND json_extract(r.response_json,'$.public_session_id')=s.public_id
  AND json_extract(r.response_json,'$.request_id')=r.request_id
  AND EXISTS(SELECT 1 FROM admin_bridge_guards transaction_guard WHERE transaction_guard.id=json_extract(r.response_json,'$.grant_transaction_id') AND transaction_guard.passed=1)
  AND json_array_length(r.response_json,'$.permissions')=2
  AND json_extract(r.response_json,'$.permissions[0]')='assisted_sms.read'
  AND json_extract(r.response_json,'$.permissions[1]')='assisted_sms.manage') THEN RAISE(IGNORE) END;
END;
CREATE TRIGGER assisted_sms_grant_no_relabel BEFORE UPDATE OF permission,user_id,granted_by ON admin_grants
 WHEN OLD.permission IN('assisted_sms.read','assisted_sms.manage') OR NEW.permission IN('assisted_sms.read','assisted_sms.manage')
 BEGIN SELECT RAISE(ABORT,'sms_grant_requires_explicit_decision'); END;
CREATE VIEW assisted_sms_current_jobs AS
 SELECT j.* FROM assisted_sms_jobs j JOIN payments p ON p.id=j.payment_id
 JOIN ledger_entries e ON e.id=j.entry_id AND e.payment_id=p.id
 JOIN collections c ON c.id=j.collection_id JOIN users u ON u.id=j.recipient_user_id
 JOIN memberships m ON m.collection_id=c.id AND m.user_id=u.id
 JOIN assisted_sms_policies policy ON policy.collection_id=c.id
 JOIN assisted_sms_authorizations consent ON consent.collection_id=c.id AND consent.recipient_user_id=u.id
 WHERE p.collection_id=c.id AND p.member_id=u.id AND p.revision=j.payment_revision
 AND p.status IN ('reconciled','confirmed') AND p.currency='RWF' AND p.rail='rwanda_momo'
 AND e.kind='contribution' AND e.amount_minor=j.amount_minor AND p.amount_minor=j.amount_minor
 AND e.collection_id=c.id AND e.member_id=u.id AND e.evidence_id=p.evidence_id AND e.currency='RWF'
 AND NOT EXISTS(SELECT 1 FROM ledger_entries inverse WHERE inverse.reverses_entry_id=e.id)
 AND c.status='active' AND u.access_status='active' AND u.member_type!='operator' AND m.active=1
 AND policy.enabled=1 AND policy.revision=j.policy_revision AND policy.template_key=j.template_key AND policy.approval_reference_sha256=j.policy_approval_sha256
 AND consent.enabled=1 AND consent.consent_revision=j.consent_revision AND consent.authorization_receipt_sha256=j.authorization_receipt_sha256
 AND consent.destination_revision=j.destination_revision AND consent.destination_sha256=j.destination_sha256
 AND consent.destination_ciphertext=j.destination_ciphertext
 AND (u.member_type!='app' OR EXISTS(SELECT 1 FROM auth_otp_verifications proof JOIN auth_otp_challenges challenge ON challenge.id=proof.challenge_id
  WHERE proof.user_id=u.id AND proof.challenge_id=consent.phone_verification_challenge_id
  AND challenge.identity_type='phone' AND challenge.surface='member' AND challenge.identity_value=u.phone
  AND challenge.status='consumed' AND challenge.consumed_operation_id=proof.operation_id
  AND challenge.consumed_at=proof.verified_at AND proof.verified_at BETWEEN challenge.created_at AND challenge.expires_at));
CREATE TRIGGER assisted_sms_job_current AFTER INSERT ON assisted_sms_jobs BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM assisted_sms_current_jobs WHERE id=NEW.id)
 THEN RAISE(ABORT,'sms_source_changed') END;
END;
CREATE TRIGGER assisted_sms_claim_current BEFORE INSERT ON assisted_sms_claims BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM assisted_sms_current_sessions s
 WHERE s.admin_id=NEW.actor_admin_id AND s.user_id=NEW.actor_user_id AND s.auth_session_id=NEW.originating_session_id
 AND s.public_id=NEW.public_session_id AND s.role=NEW.actor_role AND s.auth_version=NEW.actor_auth_version
 AND s.mfa_at=NEW.actor_mfa_at AND s.origin=NEW.origin AND s.permission='assisted_sms.manage')
 THEN RAISE(ABORT,'sms_original_session_changed') END;
 SELECT CASE WHEN NEW.created_seconds!=unixepoch() OR NEW.expires_seconds<=unixepoch() OR NEW.expires_seconds>unixepoch()+120
 OR NOT EXISTS(SELECT 1 FROM assisted_sms_current_jobs j WHERE j.id=NEW.job_id AND j.fence=NEW.previous_fence
 AND (j.state='queued' OR (j.state='claimed' AND EXISTS(SELECT 1 FROM assisted_sms_claims old WHERE old.id=j.active_claim_id AND old.expires_seconds<=unixepoch()))))
 THEN RAISE(ABORT,'sms_claim_changed') END;
END;
CREATE TRIGGER assisted_sms_claim_head AFTER INSERT ON assisted_sms_claims BEGIN
 UPDATE assisted_sms_jobs SET state='claimed',fence=NEW.fence,active_claim_id=NEW.id WHERE id=NEW.job_id;
END;
CREATE TRIGGER assisted_sms_confirmation_current BEFORE INSERT ON assisted_sms_confirmations BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM assisted_sms_claims claim JOIN assisted_sms_current_jobs j ON j.id=claim.job_id
 JOIN assisted_sms_current_sessions s ON s.admin_id=claim.actor_admin_id AND s.user_id=claim.actor_user_id
 AND s.auth_session_id=claim.originating_session_id AND s.public_id=claim.public_session_id
 AND s.role=claim.actor_role AND s.auth_version=claim.actor_auth_version AND s.mfa_at=claim.actor_mfa_at AND s.origin=claim.origin
 WHERE s.permission='assisted_sms.manage' AND claim.id=NEW.claim_id AND claim.job_id=NEW.job_id
 AND j.state='claimed' AND j.active_claim_id=claim.id AND j.fence=NEW.fence AND claim.fence=NEW.fence
 AND claim.actor_admin_id=NEW.actor_admin_id AND claim.actor_user_id=NEW.actor_user_id
 AND claim.originating_session_id=NEW.originating_session_id AND claim.public_session_id=NEW.public_session_id
 AND claim.expires_seconds>unixepoch() AND NEW.confirmed_seconds=unixepoch()
 AND NEW.expires_seconds>unixepoch() AND NEW.expires_seconds<=min(claim.expires_seconds,unixepoch()+120)
 AND j.body_sha256=NEW.body_sha256 AND j.destination_sha256=NEW.destination_sha256 AND j.destination_revision=NEW.destination_revision)
 THEN RAISE(ABORT,'sms_confirmation_changed') END;
END;
CREATE TRIGGER assisted_sms_send_current BEFORE INSERT ON assisted_sms_send_starts BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM assisted_sms_confirmations confirmation
 JOIN assisted_sms_claims claim ON claim.id=confirmation.claim_id JOIN assisted_sms_current_jobs j ON j.id=claim.job_id
 JOIN assisted_sms_current_sessions s ON s.admin_id=claim.actor_admin_id AND s.user_id=claim.actor_user_id
 AND s.auth_session_id=claim.originating_session_id AND s.public_id=claim.public_session_id
 AND s.role=claim.actor_role AND s.auth_version=claim.actor_auth_version AND s.mfa_at=claim.actor_mfa_at AND s.origin=claim.origin
 WHERE s.permission='assisted_sms.manage' AND confirmation.id=NEW.confirmation_id AND confirmation.claim_id=NEW.claim_id
 AND confirmation.fence=NEW.fence AND confirmation.job_id=NEW.job_id AND j.active_claim_id=claim.id AND j.fence=NEW.fence AND j.state='claimed'
 AND confirmation.actor_admin_id=NEW.actor_admin_id AND confirmation.actor_user_id=NEW.actor_user_id
 AND confirmation.originating_session_id=NEW.originating_session_id AND confirmation.public_session_id=NEW.public_session_id
 AND claim.expires_seconds>unixepoch() AND confirmation.expires_seconds>unixepoch() AND NEW.started_seconds=unixepoch()
 AND confirmation.body_sha256=NEW.body_sha256 AND confirmation.destination_sha256=NEW.destination_sha256
 AND confirmation.destination_revision=NEW.destination_revision AND j.body_sha256=NEW.body_sha256
 AND j.destination_sha256=NEW.destination_sha256 AND j.destination_revision=NEW.destination_revision)
 THEN RAISE(ABORT,'sms_send_start_changed') END;
END;
CREATE TRIGGER assisted_sms_send_head AFTER INSERT ON assisted_sms_send_starts BEGIN
 UPDATE assisted_sms_jobs SET state='send_started' WHERE id=NEW.job_id;
END;
CREATE TRIGGER assisted_sms_outcome_current BEFORE INSERT ON assisted_sms_outcomes BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM assisted_sms_current_sessions s WHERE s.permission='assisted_sms.manage'
 AND s.admin_id=NEW.observer_admin_id AND s.user_id=NEW.observer_user_id AND s.auth_session_id=NEW.observer_session_id
 AND s.public_id=NEW.observer_public_session_id) OR NEW.observed_seconds!=unixepoch()
 OR NOT EXISTS(SELECT 1 FROM assisted_sms_send_starts a JOIN assisted_sms_jobs j ON j.id=a.job_id WHERE a.id=NEW.attempt_id AND j.state='send_started')
 THEN RAISE(ABORT,'sms_observation_changed') END;
END;
CREATE TRIGGER assisted_sms_outcome_head AFTER INSERT ON assisted_sms_outcomes BEGIN
 UPDATE assisted_sms_jobs SET state=NEW.observation WHERE id=(SELECT job_id FROM assisted_sms_send_starts WHERE id=NEW.attempt_id);
END;
CREATE TRIGGER assisted_sms_job_immutable BEFORE UPDATE OF id,payment_id,entry_id,collection_id,recipient_user_id,payment_revision,amount_minor,destination_revision,destination_sha256,destination_ciphertext,consent_revision,policy_revision,policy_approval_sha256,authorization_receipt_sha256,template_key,body_ciphertext,body_sha256,created_at ON assisted_sms_jobs
 BEGIN SELECT RAISE(ABORT,'immutable_sms_envelope'); END;
CREATE TRIGGER assisted_sms_job_no_delete BEFORE DELETE ON assisted_sms_jobs BEGIN SELECT RAISE(ABORT,'retain_sms_envelope'); END;
CREATE TRIGGER assisted_sms_claims_no_update BEFORE UPDATE ON assisted_sms_claims BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_claims_no_delete BEFORE DELETE ON assisted_sms_claims BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_confirmations_no_update BEFORE UPDATE ON assisted_sms_confirmations BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_confirmations_no_delete BEFORE DELETE ON assisted_sms_confirmations BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_send_starts_no_update BEFORE UPDATE ON assisted_sms_send_starts BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_send_starts_no_delete BEFORE DELETE ON assisted_sms_send_starts BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_outcomes_no_update BEFORE UPDATE ON assisted_sms_outcomes BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;
CREATE TRIGGER assisted_sms_outcomes_no_delete BEFORE DELETE ON assisted_sms_outcomes BEGIN SELECT RAISE(ABORT,'retain_immutable_sms_evidence'); END;

-- Withdrawal and reauthorization never revive an earlier snapshot/version.
CREATE TRIGGER assisted_sms_policy_revision BEFORE UPDATE ON assisted_sms_policies
 WHEN NEW.collection_id!=OLD.collection_id OR NEW.revision<=OLD.revision BEGIN SELECT RAISE(ABORT,'sms_policy_revision_required'); END;
CREATE TRIGGER assisted_sms_authorization_revision BEFORE UPDATE ON assisted_sms_authorizations
 WHEN NEW.collection_id!=OLD.collection_id OR NEW.recipient_user_id!=OLD.recipient_user_id OR NEW.consent_revision<=OLD.consent_revision
 OR NEW.destination_revision<OLD.destination_revision
 OR ((NEW.destination_sha256!=OLD.destination_sha256 OR NEW.destination_ciphertext!=OLD.destination_ciphertext) AND NEW.destination_revision<=OLD.destination_revision)
 BEGIN SELECT RAISE(ABORT,'sms_authorization_revision_required'); END;
