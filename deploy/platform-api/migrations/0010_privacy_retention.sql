-- Unpublished retention engine. Existing financial/evidence/intake immutability
-- remains unchanged. No policy, approval or execution is enabled by this schema.
CREATE TABLE privacy_retention_plans (
 id TEXT PRIMARY KEY, operation_id TEXT NOT NULL UNIQUE, request_id TEXT NOT NULL REFERENCES deletion_requests(id),
 subject_id TEXT NOT NULL REFERENCES users(id), actor_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 input_sha256 TEXT NOT NULL CHECK(length(input_sha256)=64), policy_sha256 TEXT NOT NULL CHECK(length(policy_sha256)=64),
 policy_json TEXT NOT NULL CHECK(json_valid(policy_json)), policy_config_revision INTEGER NOT NULL,
 source_id TEXT NOT NULL CHECK(length(source_id)=64), schema_sha256 TEXT NOT NULL CHECK(length(schema_sha256)=64),
 scope_json TEXT NOT NULL CHECK(json_valid(scope_json)), scope_sha256 TEXT NOT NULL CHECK(length(scope_sha256)=64),
 ledger_sha256 TEXT NOT NULL CHECK(length(ledger_sha256)=64), review_revision INTEGER NOT NULL,
 state TEXT NOT NULL DEFAULT 'planned' CHECK(state IN('planned','processing','blocked','disposition_verified')),
 revision INTEGER NOT NULL DEFAULT 0 CHECK(revision>=0), created_seconds INTEGER NOT NULL
) STRICT;
CREATE TABLE privacy_retention_tasks (
 id TEXT PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES privacy_retention_plans(id), class_name TEXT NOT NULL,
 action TEXT NOT NULL CHECK(action IN('retain','erase','quarantine','blocked')),
 expected_json TEXT NOT NULL CHECK(json_valid(expected_json)), state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','claimed','blocked','verified')),
 revision INTEGER NOT NULL DEFAULT 0 CHECK(revision>=0), fence INTEGER NOT NULL DEFAULT 0 CHECK(fence>=0),
 claim_id TEXT, post_images_json TEXT CHECK(post_images_json IS NULL OR json_valid(post_images_json)),
 outcome_json TEXT CHECK(outcome_json IS NULL OR json_valid(outcome_json)), UNIQUE(plan_id,class_name)
) STRICT;
CREATE TABLE privacy_retention_claims (
 id TEXT PRIMARY KEY, operation_id TEXT NOT NULL UNIQUE, task_id TEXT NOT NULL REFERENCES privacy_retention_tasks(id),
 actor_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 input_sha256 TEXT NOT NULL CHECK(length(input_sha256)=64), expected_revision INTEGER NOT NULL,
 fence INTEGER NOT NULL CHECK(fence>0), claimed_seconds INTEGER NOT NULL, expires_seconds INTEGER NOT NULL,
 CHECK(expires_seconds>claimed_seconds AND expires_seconds<=claimed_seconds+120)
) STRICT;
CREATE TABLE privacy_retention_outcomes (
 operation_id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES privacy_retention_tasks(id), claim_id TEXT NOT NULL REFERENCES privacy_retention_claims(id),
 fence INTEGER NOT NULL, input_sha256 TEXT NOT NULL CHECK(length(input_sha256)=64),
 outcome_json TEXT NOT NULL CHECK(json_valid(outcome_json)), observed_seconds INTEGER NOT NULL
) STRICT;
CREATE TABLE privacy_retention_effects (
 operation_id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES privacy_retention_tasks(id),
 claim_id TEXT NOT NULL REFERENCES privacy_retention_claims(id), fence INTEGER NOT NULL,
 source_sha256 TEXT NOT NULL CHECK(length(source_sha256)=64),
 object_key TEXT NOT NULL, object_version TEXT NOT NULL, started_seconds INTEGER NOT NULL,
 UNIQUE(task_id,object_key)
) STRICT;
CREATE TABLE privacy_retention_guards (
 id TEXT PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES privacy_retention_plans(id), class_name TEXT NOT NULL,
 passed INTEGER NOT NULL CHECK(passed=1)
) STRICT;
CREATE TABLE privacy_retention_barriers (
 subject_id TEXT PRIMARY KEY REFERENCES users(id), plan_id TEXT NOT NULL UNIQUE REFERENCES privacy_retention_plans(id),
 source_id TEXT NOT NULL CHECK(length(source_id)=64), policy_sha256 TEXT NOT NULL CHECK(length(policy_sha256)=64),
 activated_seconds INTEGER NOT NULL
) STRICT;
CREATE TRIGGER privacy_retention_plan_identity BEFORE UPDATE OF id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds ON privacy_retention_plans BEGIN SELECT RAISE(ABORT,'immutable_retention_plan'); END;
CREATE TRIGGER privacy_retention_plan_retain BEFORE DELETE ON privacy_retention_plans BEGIN SELECT RAISE(ABORT,'retain_retention_plan'); END;
CREATE TRIGGER privacy_retention_task_identity BEFORE UPDATE OF id,plan_id,class_name,action,expected_json ON privacy_retention_tasks BEGIN SELECT RAISE(ABORT,'immutable_retention_task'); END;
CREATE TRIGGER privacy_retention_task_retain BEFORE DELETE ON privacy_retention_tasks BEGIN SELECT RAISE(ABORT,'retain_retention_task'); END;
CREATE TRIGGER privacy_retention_claim_identity BEFORE UPDATE ON privacy_retention_claims BEGIN SELECT RAISE(ABORT,'immutable_retention_claim'); END;
CREATE TRIGGER privacy_retention_claim_retain BEFORE DELETE ON privacy_retention_claims BEGIN SELECT RAISE(ABORT,'retain_retention_claim'); END;
CREATE TRIGGER privacy_retention_outcome_identity BEFORE UPDATE ON privacy_retention_outcomes BEGIN SELECT RAISE(ABORT,'immutable_retention_outcome'); END;
CREATE TRIGGER privacy_retention_outcome_retain BEFORE DELETE ON privacy_retention_outcomes BEGIN SELECT RAISE(ABORT,'retain_retention_outcome'); END;
CREATE TRIGGER privacy_retention_effect_identity BEFORE UPDATE ON privacy_retention_effects BEGIN SELECT RAISE(ABORT,'immutable_retention_effect'); END;
CREATE TRIGGER privacy_retention_effect_retain BEFORE DELETE ON privacy_retention_effects BEGIN SELECT RAISE(ABORT,'retain_retention_effect'); END;
CREATE TRIGGER privacy_retention_barrier_identity BEFORE UPDATE ON privacy_retention_barriers BEGIN SELECT RAISE(ABORT,'immutable_retention_barrier'); END;
CREATE TRIGGER privacy_retention_barrier_retain BEFORE DELETE ON privacy_retention_barriers BEGIN SELECT RAISE(ABORT,'retention_barrier_requires_separate_recovery_authority'); END;
CREATE TRIGGER privacy_retention_no_reactivation BEFORE UPDATE OF access_status ON users WHEN NEW.access_status='active' AND EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.id) BEGIN SELECT RAISE(ABORT,'privacy_retention_access_quarantined'); END;
CREATE TRIGGER privacy_retention_no_new_session BEFORE INSERT ON auth_sessions WHEN EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) BEGIN SELECT RAISE(ABORT,'privacy_retention_access_quarantined'); END;
CREATE TRIGGER privacy_retention_notification_devices_insert BEFORE INSERT ON notification_devices WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('notification_devices') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_devices_update BEFORE UPDATE ON notification_devices WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('notification_devices') AND g.passed=1)) OR (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('notification_devices') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_devices_delete BEFORE DELETE ON notification_devices WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('notification_devices') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_preferences_insert BEFORE INSERT ON notification_preferences WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('notification_preferences') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_preferences_update BEFORE UPDATE ON notification_preferences WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('notification_preferences') AND g.passed=1)) OR (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('notification_preferences') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_preferences_delete BEFORE DELETE ON notification_preferences WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('notification_preferences') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_events_insert BEFORE INSERT ON notification_events WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('notification_events') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_events_update BEFORE UPDATE ON notification_events WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('notification_events') AND g.passed=1)) OR (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('notification_events') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_notification_events_delete BEFORE DELETE ON notification_events WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('notification_events') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_support_requests_insert BEFORE INSERT ON support_requests WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('support_requests') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_support_requests_update BEFORE UPDATE ON support_requests WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('support_requests') AND g.passed=1)) OR (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('support_requests') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_support_requests_delete BEFORE DELETE ON support_requests WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('support_requests') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_upload_objects_insert BEFORE INSERT ON upload_objects WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('upload_objects','r2:upload_objects') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_upload_objects_update BEFORE UPDATE ON upload_objects WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('upload_objects','r2:upload_objects') AND g.passed=1)) OR (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=NEW.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=NEW.user_id AND g.class_name IN ('upload_objects','r2:upload_objects') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
CREATE TRIGGER privacy_retention_upload_objects_delete BEFORE DELETE ON upload_objects WHEN (EXISTS(SELECT 1 FROM privacy_retention_barriers b WHERE b.subject_id=OLD.user_id) AND NOT EXISTS(SELECT 1 FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=OLD.user_id AND g.class_name IN ('upload_objects','r2:upload_objects') AND g.passed=1)) BEGIN SELECT RAISE(ABORT,'privacy_retention_write_barrier'); END;
