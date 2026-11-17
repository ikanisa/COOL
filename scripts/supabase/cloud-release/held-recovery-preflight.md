# Held recovery: read-only preflight and migration rehearsal

This plan is for review. It does not apply a migration, enable a route, change
the scheduler or inspect SMS, member, financial or other business rows. The
candidate migration itself must not be run as a production rollback test: it
creates functions and triggers on real relations and can block live work.

The candidate is based on Git commit `3c29f0d6010340c966811a6884cc804b3c38d30f`
(deployed source SHA `16080f9483eb0bc8f272c64ca2dfd72459af530cf89f90767328d9a37d6278d8`).
Verify the currently deployed source and scheduler state immediately before any
future release; integrate newer changes instead of overwriting them.

## Production catalog inspection

Use a dedicated authenticated connection to the intended Supabase Cloud
project. Begin a `REPEATABLE READ READ ONLY` transaction with short statement and
lock timeouts. Inspect only PostgreSQL catalogs and migration metadata:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '8s';
SET LOCAL lock_timeout = '3s';
SELECT session_user, current_user, current_database(),
       current_setting('transaction_read_only') AS read_only,
       current_setting('server_version_num') AS server_version;
SELECT rolname, rolsuper, rolbypassrls FROM pg_roles
 WHERE rolname IN ('postgres', 'collect_runtime') ORDER BY rolname;

WITH expected(signature, sha256) AS (VALUES
 ('private.collect_imported_native_source(text)', '3de5a1c984b9cf3d3e00f0ae8930a85b89cdc9f74f6e70c4744df96717ba2cde'),
 ('private.burimunsi_observation_reconcile_status()', 'dbc081cd16057fb2bf07da3514aab3b3afe4e7d35427651bd8187da0e809c30e'),
 ('private.burimunsi_observation_actor(boolean)', 'e6f1bf1db6c84209a8bf00465201e1db997dc8c03a972399af7e6fcb48f4f9e1'),
 ('private.burimunsi_observation_consent_current()', '4c7f0cea13f47ef0a040c36e3059ded889f42932f0696a554513bf470fa060f9'),
 ('private.burimunsi_observation_own(text,boolean)', 'f306b9c50fafa238f64816bf7a242a21d9f828ad9df5a8c565ada001b15aa7d1'),
 ('private.burimunsi_observation_lookup(uuid,text)', 'bda49fee71b6944325a1fa9d7d884016a00691f4a9a4a0b0f7212a4fb50c71ae'),
 ('private.burimunsi_auto_snapshot(text)', '29bcd9f8440ab6d99571871ca7dc0203ec516d6f4d673a91bfc20eb5cef227f6'),
 ('private.burimunsi_auto_candidates(text)', 'de95126024a114bc696bb570b866aece8d2334bd4db5f742428270c71c682e28'),
 ('private.burimunsi_native_work_candidates(uuid,integer)', '7f6186d02734c5e40ef0e66051d271d1d67e183b2c78ebbe86e7233b78fc729e'),
 ('private.burimunsi_native_sms_post_candidates(integer)', '9e1a2a348a06f270afb65055c58edc7e88181385adac3dd24991384b86fe0adc'),
 ('private.burimunsi_observation_processing_status(jsonb)', '088bb545a1b94022c1bb76203ca7250fa185ad948a5c36d87f4604ef5f32d332'),
 ('private.burimunsi_observation_processing_retry(text,uuid)', 'dfa2af64c98f03135240ac62fb20276b1f9c72495e81d540e53853d5fd6ef863'),
 ('private._retention_manifest_catalog_v2()', 'b05ee1ced84adfbde6f9144039cbd062730dece8dfc060f636425fa64c90d032'),
 ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)', '9fcadb280a30843d3d1d8a006e556a8532f365e3e0b30596d5336e6ab3c9c336')
)
SELECT e.signature, e.sha256 AS expected_sha256,
       encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS actual_sha256,
       pg_get_userbyid(p.proowner) AS owner, p.prosecdef, p.provolatile,
       p.prorettype::regtype::text AS return_type, l.lanname,
       p.proconfig, p.proacl::text AS acl
  FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
  LEFT JOIN pg_language l ON l.oid=p.prolang ORDER BY e.signature;

SELECT to_regclass('private.collect_sms_witnesses') AS witness_table,
       to_regclass('private.burimunsi_recovered_sms_holds') AS hold_table,
       to_regprocedure('private.burimunsi_observation_reconcile_verified_status()') AS verified_status,
       to_regprocedure('private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)') AS ack_snapshot;
SELECT version FROM supabase_migrations.schema_migrations
 WHERE version='20261117210000';
ROLLBACK;
```

Before the migration, every expected function must exist with the exact hash
and metadata required in the draft, both candidate tables and functions must be
absent, and the candidate migration version must be absent. The four ACK
predecessors were checked against the live catalog during this development
session; repeat the full comparison at release time. Do not infer that the
fence is ready for migration from this catalog inspection.

In a separate read-only transaction, `SET LOCAL ROLE collect_runtime` and
inspect effective schema, function and table privileges with
`has_schema_privilege`, `has_function_privilege` and `has_table_privilege`.
Do not call functions with a real actor or source. Verify the role cannot read
or change the proposed private tables directly, and can call only the intended
definer functions after a qualified test migration. PostgreSQL's `postgres`
owner currently has `BYPASSRLS`; all group and actor predicates therefore need
independent review rather than assuming forced RLS enforces them.

## Full rehearsal and release boundary

Use an authorized isolated Supabase Cloud test environment containing the
matching schema and synthetic rows, with no production business records. Replay
the complete migration there under the intended operator/fence state. Verify
all preconditions, ACLs, owner/configuration, trigger functions and enablement,
retention registration and scheduler hash checks. Run the ACK-only fixture,
gateway and queue tests, the two-connection race, and negative tests for
cross-group/owner/installation access, revoked or changed consent, changed
content, incomplete custody and unknown provider outcomes. Confirm the legacy
SQL body remains unchanged and the v47 endpoint is unconfirmed.

The existing temporary PostgreSQL fixtures and shared-schema race tested only
synthetic parts of the candidate; they are not a complete migration rehearsal.
Any future production cutover must use the existing fenced migration/runtime
procedure, prove that older runtimes are drained, and satisfy the separate
five-minute **and fresh-device-read** boundary in `held-recovery-cutover.md`.
