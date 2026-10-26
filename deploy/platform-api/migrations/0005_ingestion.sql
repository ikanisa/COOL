-- Native admission is app/device provenance, never settled-payment evidence.
CREATE TABLE native_consents (
 id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 receiver_hash TEXT NOT NULL CHECK(length(receiver_hash)=64), enabled INTEGER NOT NULL CHECK(enabled IN(0,1)),
 created_seconds INTEGER NOT NULL, build_channel TEXT NOT NULL, request_id TEXT NOT NULL UNIQUE
);
CREATE TABLE native_reservations (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 nonce TEXT NOT NULL, action TEXT NOT NULL CHECK(action IN('group.create','sms.ingest')),
 request_hash TEXT NOT NULL CHECK(length(request_hash)=64), token_sha256 TEXT NOT NULL UNIQUE CHECK(length(token_sha256)=64),
 receiver_hash TEXT NOT NULL CHECK(length(receiver_hash)=64), verified_phone TEXT NOT NULL,
 payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256)=64), payload_ciphertext TEXT NOT NULL,
 policy_sha256 TEXT NOT NULL CHECK(length(policy_sha256)=64), approval_id TEXT NOT NULL, approval_evidence_sha256 TEXT NOT NULL,
 project_id TEXT NOT NULL, created_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL,
 actor_hour_limit INTEGER NOT NULL CHECK(actor_hour_limit BETWEEN 1 AND 100), project_day_limit INTEGER NOT NULL CHECK(project_day_limit BETWEEN 1 AND 10000),
 state TEXT NOT NULL DEFAULT 'reserved' CHECK(state IN('reserved','oauth_started','decode_started','completed','rejected','ambiguous')),
 UNIQUE(user_id,nonce)
);
CREATE INDEX native_budget_actor ON native_reservations(user_id,created_seconds);
CREATE INDEX native_budget_project ON native_reservations(project_id,created_seconds);
CREATE TABLE native_phases (
 reservation_id TEXT NOT NULL REFERENCES native_reservations(id), phase TEXT NOT NULL CHECK(phase IN('oauth','decode')),
 started_seconds INTEGER NOT NULL, PRIMARY KEY(reservation_id,phase)
);
CREATE TABLE native_capabilities (
 id TEXT PRIMARY KEY, token_sha256 TEXT NOT NULL UNIQUE CHECK(length(token_sha256)=64), reservation_id TEXT NOT NULL UNIQUE REFERENCES native_reservations(id),
 user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id), action TEXT NOT NULL,
 receiver_hash TEXT NOT NULL, verified_phone TEXT NOT NULL, payload_sha256 TEXT NOT NULL,
 created_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL CHECK(expires_seconds>created_seconds AND expires_seconds<=created_seconds+180),
 verdict_sha256 TEXT NOT NULL CHECK(length(verdict_sha256)=64)
);
CREATE TABLE native_completions (
 reservation_id TEXT PRIMARY KEY REFERENCES native_reservations(id), capability_id TEXT NOT NULL UNIQUE REFERENCES native_capabilities(id),
 result_ciphertext TEXT NOT NULL, provider_response_sha256 TEXT NOT NULL, completed_seconds INTEGER NOT NULL,
 decode_duration_ms INTEGER NOT NULL CHECK(decode_duration_ms BETWEEN 0 AND 20000)
);
CREATE TABLE native_capability_claims (
 id TEXT PRIMARY KEY, capability_id TEXT NOT NULL UNIQUE REFERENCES native_capabilities(id), user_id TEXT NOT NULL, session_id TEXT NOT NULL,
 action TEXT NOT NULL, payload_sha256 TEXT NOT NULL, receiver_hash TEXT NOT NULL, claimed_seconds INTEGER NOT NULL
);
CREATE TRIGGER native_consent_authority BEFORE INSERT ON native_consents BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=NEW.session_id AND s.user_id=NEW.user_id AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>NEW.created_seconds AND u.access_status='active') THEN RAISE(ABORT,'native_session_changed') END);
END;
CREATE TRIGGER native_reservation_authority BEFORE INSERT ON native_reservations BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=NEW.session_id AND s.user_id=NEW.user_id AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>NEW.created_seconds AND u.access_status='active' AND u.phone=NEW.verified_phone AND u.country_code='RW' AND u.currency_code='RWF') THEN RAISE(ABORT,'native_session_changed') END);
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_consents c WHERE c.id=(SELECT max(id) FROM native_consents WHERE user_id=NEW.user_id) AND c.session_id=NEW.session_id AND c.enabled=1 AND c.receiver_hash=NEW.receiver_hash AND c.created_seconds BETWEEN NEW.created_seconds-600 AND NEW.created_seconds) THEN RAISE(ABORT,'native_consent_required') END);
 SELECT (CASE WHEN (SELECT count(*) FROM native_reservations WHERE user_id=NEW.user_id AND created_seconds>=NEW.created_seconds-3600)>=NEW.actor_hour_limit THEN RAISE(ABORT,'native_actor_budget') END);
 SELECT (CASE WHEN (SELECT count(*) FROM native_reservations WHERE project_id=NEW.project_id AND created_seconds>=CAST(NEW.created_seconds/86400 AS INTEGER)*86400)>=NEW.project_day_limit THEN RAISE(ABORT,'native_project_budget') END);
END;
CREATE TRIGGER native_phase_authority BEFORE INSERT ON native_phases BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_reservations r JOIN auth_sessions s ON s.id=r.session_id JOIN users u ON u.id=r.user_id WHERE r.id=NEW.reservation_id AND r.expires_seconds>NEW.started_seconds AND s.revoked_at IS NULL AND s.expires_at>NEW.started_seconds AND u.access_status='active' AND u.phone=r.verified_phone AND ((NEW.phase='oauth' AND r.state='reserved') OR (NEW.phase='decode' AND r.state='oauth_started'))) THEN RAISE(ABORT,'native_dispatch_denied') END);
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_reservations r JOIN native_consents c ON c.user_id=r.user_id WHERE r.id=NEW.reservation_id AND c.id=(SELECT max(id) FROM native_consents WHERE user_id=r.user_id) AND c.enabled=1 AND c.session_id=r.session_id AND c.receiver_hash=r.receiver_hash AND c.created_seconds BETWEEN NEW.started_seconds-600 AND NEW.started_seconds) THEN RAISE(ABORT,'native_consent_required') END);
END;
CREATE TRIGGER native_phase_state AFTER INSERT ON native_phases BEGIN
 UPDATE native_reservations SET state=CASE NEW.phase WHEN 'oauth' THEN 'oauth_started' ELSE 'decode_started' END WHERE id=NEW.reservation_id;
END;
CREATE TRIGGER native_capability_authority BEFORE INSERT ON native_capabilities BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_reservations r JOIN auth_sessions s ON s.id=r.session_id JOIN users u ON u.id=r.user_id WHERE r.id=NEW.reservation_id AND r.state='decode_started' AND r.expires_seconds>NEW.created_seconds AND r.user_id=NEW.user_id AND r.session_id=NEW.session_id AND r.action=NEW.action AND r.receiver_hash=NEW.receiver_hash AND r.payload_sha256=NEW.payload_sha256 AND r.verified_phone=NEW.verified_phone AND s.revoked_at IS NULL AND s.expires_at>NEW.created_seconds AND u.access_status='active' AND u.phone=NEW.verified_phone) THEN RAISE(ABORT,'native_completion_denied') END);
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_consents c WHERE c.id=(SELECT max(id) FROM native_consents WHERE user_id=NEW.user_id) AND c.session_id=NEW.session_id AND c.enabled=1 AND c.receiver_hash=NEW.receiver_hash AND c.created_seconds BETWEEN NEW.created_seconds-600 AND NEW.created_seconds) THEN RAISE(ABORT,'native_consent_required') END);
END;
CREATE TRIGGER native_claim_authority BEFORE INSERT ON native_capability_claims BEGIN
 SELECT (CASE WHEN NEW.claimed_seconds NOT BETWEEN unixepoch()-5 AND unixepoch()+5 THEN RAISE(ABORT,'native_claim_expired') END);
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_capabilities c JOIN native_completions d ON d.capability_id=c.id JOIN auth_sessions s ON s.id=c.session_id JOIN users u ON u.id=c.user_id WHERE c.id=NEW.capability_id AND c.user_id=NEW.user_id AND c.session_id=NEW.session_id AND c.action=NEW.action AND c.payload_sha256=NEW.payload_sha256 AND c.receiver_hash=NEW.receiver_hash AND c.expires_seconds>max(NEW.claimed_seconds,unixepoch()) AND s.revoked_at IS NULL AND s.expires_at>max(NEW.claimed_seconds,unixepoch()) AND u.access_status='active' AND u.phone=c.verified_phone) THEN RAISE(ABORT,'native_capability_denied') END);
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM native_consents c WHERE c.id=(SELECT max(id) FROM native_consents WHERE user_id=NEW.user_id) AND c.session_id=NEW.session_id AND c.enabled=1 AND c.receiver_hash=NEW.receiver_hash AND c.created_seconds BETWEEN NEW.claimed_seconds-600 AND NEW.claimed_seconds) THEN RAISE(ABORT,'native_consent_required') END);
END;
CREATE TRIGGER native_reservation_identity BEFORE UPDATE OF id,user_id,session_id,nonce,action,request_hash,token_sha256,receiver_hash,verified_phone,payload_sha256,payload_ciphertext,policy_sha256,approval_id,approval_evidence_sha256,project_id,created_seconds,expires_seconds,actor_hour_limit,project_day_limit ON native_reservations BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_reservation_state BEFORE UPDATE OF state ON native_reservations WHEN NOT ((OLD.state='reserved' AND NEW.state IN('oauth_started','ambiguous','rejected')) OR (OLD.state='oauth_started' AND NEW.state IN('decode_started','ambiguous','rejected')) OR (OLD.state='decode_started' AND NEW.state IN('completed','ambiguous','rejected'))) BEGIN SELECT RAISE(ABORT,'native_state_immutable'); END;
CREATE TRIGGER native_phases_immutable BEFORE UPDATE ON native_phases BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_phases_no_delete BEFORE DELETE ON native_phases BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_capabilities_immutable BEFORE UPDATE ON native_capabilities BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_capabilities_no_delete BEFORE DELETE ON native_capabilities BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_completions_immutable BEFORE UPDATE ON native_completions BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_completions_no_delete BEFORE DELETE ON native_completions BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_claims_immutable BEFORE UPDATE ON native_capability_claims BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;
CREATE TRIGGER native_claims_no_delete BEFORE DELETE ON native_capability_claims BEGIN SELECT RAISE(ABORT,'native_evidence_immutable'); END;

CREATE TABLE roster_imports (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id), request_id TEXT NOT NULL,
 collection_id TEXT REFERENCES collections(id), request_sha256 TEXT NOT NULL, source_sha256 TEXT NOT NULL, object_sha256 TEXT NOT NULL,
 source_object_key TEXT NOT NULL UNIQUE, source_size INTEGER NOT NULL CHECK(source_size BETWEEN 1 AND 5242880),
 source_kind TEXT NOT NULL, source_receipt_json TEXT NOT NULL CHECK(json_valid(source_receipt_json)),
 state TEXT NOT NULL CHECK(state IN('reserved','retained','processing','preview_ready','committed','failed','ambiguous')), latest_revision_id TEXT,
 source_ciphertext TEXT NOT NULL,
 created_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL, error_code TEXT, UNIQUE(user_id,request_id)
);
CREATE TABLE roster_processing_records (
 id TEXT PRIMARY KEY, import_id TEXT NOT NULL UNIQUE REFERENCES roster_imports(id), actor_user_id TEXT NOT NULL, session_id TEXT NOT NULL,
 source_sha256 TEXT NOT NULL, source_object_sha256 TEXT NOT NULL, policy_sha256 TEXT NOT NULL, approval_id TEXT NOT NULL,
 approval_evidence_sha256 TEXT NOT NULL, processor_policy_json TEXT NOT NULL CHECK(json_valid(processor_policy_json)),
 project_id TEXT NOT NULL, organization_id TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL,
 processing_region_evidence_ref TEXT NOT NULL, retention_evidence_ref TEXT NOT NULL, decoder_build_sha256 TEXT NOT NULL,
 decoder_lineage_json TEXT NOT NULL CHECK(json_valid(decoder_lineage_json)), created_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL
);
CREATE TABLE roster_dispatch_phases (
 processing_id TEXT NOT NULL REFERENCES roster_processing_records(id), phase TEXT NOT NULL CHECK(phase IN('decode','extract')),
 started_seconds INTEGER NOT NULL, PRIMARY KEY(processing_id,phase)
);
CREATE TABLE roster_revisions (
 id TEXT PRIMARY KEY, import_id TEXT NOT NULL REFERENCES roster_imports(id), request_id TEXT NOT NULL, parent_revision_id TEXT REFERENCES roster_revisions(id),
 revision_number INTEGER NOT NULL CHECK(revision_number BETWEEN 1 AND 20), rows_sha256 TEXT NOT NULL, preview_ciphertext TEXT NOT NULL,
 human_reviewed INTEGER NOT NULL CHECK(human_reviewed IN(0,1)), review_reason TEXT, created_seconds INTEGER NOT NULL, UNIQUE(import_id,request_id),UNIQUE(import_id,revision_number)
);
CREATE TABLE roster_members (
 id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES collections(id), source_import_id TEXT NOT NULL REFERENCES roster_imports(id),
 source_revision_id TEXT NOT NULL REFERENCES roster_revisions(id), member_name TEXT NOT NULL, momo_name TEXT NOT NULL,
 momo_number TEXT NOT NULL, linked_user_id TEXT REFERENCES users(id), created_at TEXT NOT NULL, UNIQUE(collection_id,momo_number)
);
CREATE TABLE roster_commit_guards (
 id TEXT PRIMARY KEY, import_id TEXT NOT NULL, revision_id TEXT, actor_user_id TEXT NOT NULL, session_id TEXT NOT NULL,
 now_seconds INTEGER NOT NULL, expected_state TEXT NOT NULL, expected_latest_revision TEXT, permission TEXT NOT NULL DEFAULT 'roster.import',
 collection_id TEXT, expected_collection_revision INTEGER
);
CREATE TABLE roster_intents (
 id TEXT PRIMARY KEY, import_id TEXT NOT NULL REFERENCES roster_imports(id), user_id TEXT NOT NULL, session_id TEXT NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN('review','commit')), request_id TEXT NOT NULL, body_sha256 TEXT NOT NULL,
 payload_ciphertext TEXT NOT NULL, created_seconds INTEGER NOT NULL, UNIQUE(import_id,request_id)
);
CREATE TRIGGER roster_upload_authority BEFORE INSERT ON roster_imports BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id JOIN admin_grants g ON g.user_id=u.id JOIN auth_mfa_factors f ON f.id=s.mfa_factor_id WHERE s.id=NEW.session_id AND s.user_id=NEW.user_id AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>unixepoch() AND s.assurance_level=2 AND s.mfa_at>=unixepoch()-300 AND f.status='verified' AND u.access_status='active' AND g.permission='roster.import') THEN RAISE(ABORT,'roster_session_changed') END);
 SELECT (CASE WHEN (SELECT count(*) FROM roster_imports WHERE user_id=NEW.user_id AND created_seconds>=unixepoch()-86400)>=20 THEN RAISE(ABORT,'roster_import_limit') END);
 SELECT (CASE WHEN NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections WHERE id=NEW.collection_id AND status='active') THEN RAISE(ABORT,'roster_collection_changed') END);
END;
CREATE TRIGGER roster_current_authority BEFORE INSERT ON roster_commit_guards BEGIN
 SELECT (CASE WHEN NEW.now_seconds NOT BETWEEN unixepoch()-5 AND unixepoch()+5 THEN RAISE(ABORT,'roster_current_dispatch_expired') END);
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM roster_imports i JOIN auth_sessions s ON s.id=i.session_id JOIN users u ON u.id=i.user_id JOIN admin_grants g ON g.user_id=u.id JOIN auth_mfa_factors f ON f.id=s.mfa_factor_id WHERE i.id=NEW.import_id AND i.user_id=NEW.actor_user_id AND i.session_id=NEW.session_id AND i.expires_seconds>max(NEW.now_seconds,unixepoch()) AND i.state=NEW.expected_state AND i.latest_revision_id IS NEW.expected_latest_revision AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>max(NEW.now_seconds,unixepoch()) AND s.assurance_level=2 AND s.mfa_at>=unixepoch()-300 AND f.status='verified' AND u.access_status='active' AND g.permission=NEW.permission) THEN RAISE(ABORT,'roster_session_or_revision_changed') END);
 SELECT (CASE WHEN NEW.revision_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM roster_revisions r WHERE r.id=NEW.revision_id AND r.import_id=NEW.import_id AND r.human_reviewed=1) THEN RAISE(ABORT,'roster_review_required') END);
 SELECT (CASE WHEN NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.collection_id AND c.status='active' AND c.revision=NEW.expected_collection_revision) THEN RAISE(ABORT,'roster_collection_changed') END);
END;
CREATE TRIGGER roster_processing_authority BEFORE INSERT ON roster_processing_records BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM roster_imports i JOIN auth_sessions s ON s.id=i.session_id JOIN users u ON u.id=i.user_id JOIN admin_grants g ON g.user_id=u.id WHERE i.id=NEW.import_id AND i.user_id=NEW.actor_user_id AND i.session_id=NEW.session_id AND i.source_sha256=NEW.source_sha256 AND i.object_sha256=NEW.source_object_sha256 AND i.state='processing' AND i.expires_seconds>NEW.created_seconds AND s.revoked_at IS NULL AND s.expires_at>NEW.created_seconds AND s.surface='admin' AND u.access_status='active' AND g.permission='roster.import') THEN RAISE(ABORT,'roster_processing_denied') END);
END;
CREATE TRIGGER roster_dispatch_authority BEFORE INSERT ON roster_dispatch_phases BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM roster_processing_records p JOIN roster_imports i ON i.id=p.import_id JOIN auth_sessions s ON s.id=p.session_id JOIN users u ON u.id=p.actor_user_id JOIN admin_grants g ON g.user_id=u.id WHERE p.id=NEW.processing_id AND p.expires_seconds>NEW.started_seconds AND i.state='processing' AND i.expires_seconds>NEW.started_seconds AND s.revoked_at IS NULL AND s.expires_at>NEW.started_seconds AND u.access_status='active' AND g.permission='roster.import') THEN RAISE(ABORT,'roster_dispatch_denied') END);
 SELECT (CASE WHEN NEW.phase='extract' AND NOT EXISTS(SELECT 1 FROM roster_dispatch_phases WHERE processing_id=NEW.processing_id AND phase='decode') THEN RAISE(ABORT,'roster_decoder_lineage_required') END);
END;
CREATE TRIGGER roster_source_immutable BEFORE UPDATE OF id,user_id,session_id,request_id,collection_id,request_sha256,source_sha256,object_sha256,source_object_key,source_size,source_kind,source_receipt_json,source_ciphertext,created_seconds,expires_seconds ON roster_imports BEGIN SELECT RAISE(ABORT,'roster_source_immutable'); END;
CREATE TRIGGER roster_revisions_immutable BEFORE UPDATE ON roster_revisions BEGIN SELECT RAISE(ABORT,'roster_revision_immutable'); END;
CREATE TRIGGER roster_revisions_no_delete BEFORE DELETE ON roster_revisions BEGIN SELECT RAISE(ABORT,'roster_revision_immutable'); END;
CREATE TRIGGER roster_processing_immutable BEFORE UPDATE ON roster_processing_records BEGIN SELECT RAISE(ABORT,'roster_processing_immutable'); END;
CREATE TRIGGER roster_processing_no_delete BEFORE DELETE ON roster_processing_records BEGIN SELECT RAISE(ABORT,'roster_processing_immutable'); END;
CREATE TRIGGER roster_dispatch_immutable BEFORE UPDATE ON roster_dispatch_phases BEGIN SELECT RAISE(ABORT,'roster_dispatch_immutable'); END;
CREATE TRIGGER roster_dispatch_no_delete BEFORE DELETE ON roster_dispatch_phases BEGIN SELECT RAISE(ABORT,'roster_dispatch_immutable'); END;
CREATE TRIGGER roster_intents_immutable BEFORE UPDATE ON roster_intents BEGIN SELECT RAISE(ABORT,'roster_intent_immutable'); END;
CREATE TRIGGER roster_intents_no_delete BEFORE DELETE ON roster_intents BEGIN SELECT RAISE(ABORT,'roster_intent_immutable'); END;
