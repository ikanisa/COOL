-- Additive canonical-integration schema. NOT APPLIED. Requires prior native schemas.
-- Reconcile with pinned Collect schema; qualify through a normal Supabase migration
-- on disposable PostgreSQL before activation. No policies, identities or grants seeded.
BEGIN;
CREATE TABLE private.burimunsi_session_links (
 native_session_id uuid PRIMARY KEY REFERENCES private.burimunsi_sessions(id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,
 principal_user_id text NOT NULL REFERENCES app.users(id),
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 created_at bigint NOT NULL CHECK(created_at>=0),
 expires_at bigint NOT NULL CHECK(expires_at>created_at),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE TABLE private.burimunsi_integration_policies (
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 collection_id text PRIMARY KEY REFERENCES private.burimunsi_scopes(collection_id),
 approved_version text NOT NULL CHECK(length(approved_version) BETWEEN 1 AND 128),
 approved_by text NOT NULL REFERENCES app.users(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),
 expires_at bigint NOT NULL CHECK(expires_at>approved_at),
 revoked_at bigint CHECK(revoked_at>=approved_at),
 source_reference text NOT NULL CHECK(length(source_reference) BETWEEN 1 AND 512),
 native_parser_version text NOT NULL,
 provider_profile_version text NOT NULL,
 provider_profile_sha256 text NOT NULL CHECK(provider_profile_sha256 ~ '^[a-f0-9]{64}$'),
 identity_enabled boolean NOT NULL DEFAULT false,
 processing_enabled boolean NOT NULL DEFAULT false,
 scheduler_enabled boolean NOT NULL DEFAULT false,
 CHECK(NOT scheduler_enabled OR processing_enabled)
);
CREATE TABLE private.burimunsi_identity_proofs (
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 id text PRIMARY KEY CHECK(id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 member_id text NOT NULL REFERENCES app.users(id),
 phone text NOT NULL CHECK(phone ~ '^\+2507[2389][0-9]{7}$'),
 state text NOT NULL CHECK(state IN('verified','revoked')),
 purpose text NOT NULL CHECK(purpose='own_contributions'),
 verification_method text NOT NULL CHECK(verification_method='collect_owner_review'),
 policy_version text NOT NULL CHECK(length(policy_version) BETWEEN 1 AND 128),
 source_reference text NOT NULL CHECK(length(source_reference) BETWEEN 1 AND 512),
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 approved_by text NOT NULL REFERENCES app.users(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),
 valid_from bigint NOT NULL CHECK(valid_from>=0),
 valid_until bigint CHECK(valid_until>valid_from),
 revoked_at bigint CHECK(revoked_at>=approved_at),
 CHECK((state='verified' AND revoked_at IS NULL) OR (state='revoked' AND revoked_at IS NOT NULL))
);
-- Overlapping ownership is representable and stays ambiguous, not silently deduplicated.
CREATE INDEX burimunsi_identity_proof_scope ON private.burimunsi_identity_proofs(collection_id,policy_version,phone,valid_from);
CREATE TABLE private.burimunsi_worker_grants (
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 id uuid PRIMARY KEY,
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 owner text NOT NULL CHECK(owner ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 principal_user_id text NOT NULL REFERENCES app.users(id),
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 policy_version text NOT NULL CHECK(length(policy_version) BETWEEN 1 AND 128),
 work_kinds text[] NOT NULL CHECK(cardinality(work_kinds)>0 AND work_kinds <@ ARRAY['receipt','rematch']::text[]),
 enabled boolean NOT NULL DEFAULT false,
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 approved_by text NOT NULL REFERENCES app.users(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),
 expires_at bigint NOT NULL CHECK(expires_at>approved_at),
 revoked_at bigint CHECK(revoked_at>=approved_at),
 UNIQUE(collection_id,owner), CHECK(NOT enabled OR revoked_at IS NULL)
);
CREATE TABLE private.burimunsi_schedulers (
 collection_id text PRIMARY KEY REFERENCES private.burimunsi_scopes(collection_id),
 state text NOT NULL DEFAULT 'idle' CHECK(state IN('idle','running')),
 run_id uuid,lease_owner text,lease_version bigint NOT NULL DEFAULT 0 CHECK(lease_version>=0),
 lease_expires_at bigint,profile_version text,policy_version text,admission_id uuid,
 source_sha256 text CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 started_at bigint,completed_at bigint,last_outcome text CHECK(last_outcome IN('completed','yielded','stopped','failed')),
 summary jsonb CHECK(summary IS NULL OR jsonb_typeof(summary)='object'),
 CHECK(state<>'running' OR (run_id IS NOT NULL AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL AND
   admission_id IS NOT NULL AND source_sha256 IS NOT NULL AND lease_version>0 AND profile_version IS NOT NULL AND policy_version IS NOT NULL))
);
DO $block$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_session_links','burimunsi_integration_policies','burimunsi_identity_proofs','burimunsi_worker_grants','burimunsi_schedulers'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated,collect_runtime',t);
  EXECUTE format('GRANT SELECT ON TABLE private.%I TO collect_runtime',t);
  EXECUTE format('CREATE POLICY burimunsi_scoped_runtime ON private.%I TO collect_runtime USING (collection_id=current_setting(''burimunsi.collection_id'',true)) WITH CHECK (collection_id=current_setting(''burimunsi.collection_id'',true))',t);
 END LOOP;
END
$block$;
-- PostgreSQL row-locking SELECT requires UPDATE on at least one column.
-- Only the invariant sentinel is writable: CHECK + NOT NULL permits no change
-- to its value. No authorization/policy/evidence field receives UPDATE privilege.
-- Qualify this under collect_runtime and FORCE RLS on real PostgreSQL.
GRANT UPDATE(lock_anchor) ON private.burimunsi_integration_policies TO collect_runtime;
GRANT UPDATE(lock_anchor) ON private.burimunsi_identity_proofs TO collect_runtime;
GRANT UPDATE(lock_anchor) ON private.burimunsi_worker_grants TO collect_runtime;
-- Runtime cannot approve identities, processing policy or worker grants, or mutate
-- an issued linkage. No new SECURITY DEFINER function or financial guard bypass.
GRANT INSERT ON private.burimunsi_session_links TO collect_runtime;
GRANT INSERT,UPDATE ON private.burimunsi_schedulers TO collect_runtime;
COMMIT;
