# Collect recovery readiness

Status: **actual production database capture/restore and isolated upgrade pass;
full recovery acceptance remains open**. The 3 September 2026 rehearsal uses the
approved encrypted production archives. It does not establish Storage/off-site
recovery or an agreed recovery-point/recovery-time objective.

For the latest authorization, encrypted-destination checks and hosted backup
attempts, see [3 September continuation](release/CONTINUATION_2026-09-03.md).
The encrypted local backup and a temporary single-IP network exception were
approved. Database capture and restore now pass; the temporary rule is removed.
See the [actual production-copy upgrade rehearsal](release/PRODUCTION_COPY_UPGRADE_REHEARSAL_V4_2026-09-03.json).
This is not production GO or evidence that the candidate migrations are live.

Latest local evidence: [111-migration candidate restore](release/COMBINED_RECOVERY_2026-09-02.json)
and [continuation notes](release/CONTINUATION_2026-09-02.md). All 113 fingerprinted
tables and checked schema/ACL/sequence values matched; the synthetic contribution
readback passed. This supersedes the earlier version's local coverage only.

## Recovery authority and outstanding owner decisions

The exact COOL project, encrypted Mac destination and temporary `/32` access
were approved for this capture. The remaining decisions below are not reasons
to repeat an already-approved export permission request.

- Approve the precise source project (`lhbowpbcpwoiparwnwgt`), scope and export.
- Name the incident/recovery owner, independent verifier and approved private,
  encrypted backup destination; define access, off-site copies and retention.
- Set acceptable lost-data window (RPO) and maximum service interruption (RTO).
- Approve a separate isolated restore target. Never restore a drill over live
  production or send restored notification/payment queues to real providers.

No paid backup option, production export, restore or configuration change is
authorized merely by this document.

## Coverage required

| Asset | Recovery evidence |
| --- | --- |
| Database | Consistent data and schema snapshot, including Auth, public, private, `collect_member_actions` and `collect_admin_access`; functions, triggers, policies, ACLs, ownership, constraints, sequences and migration history |
| Financial records | MoMo payments/allocations/ledger and bank evidence/transactions/allocations/journals; immutable originals, exact totals by currency and uniqueness checks after restore |
| Storage | Bucket metadata/policies plus object bytes, versions where applicable, checksums and separately tested restore; a database backup does not contain object bytes |
| Platform | Auth URLs/provider settings, Edge Function versions and configuration, Realtime/publications, scheduled jobs, hooks and secrets inventory through an approved secret manager |
| Identity and access | Required global roles/ownership and trusted restore administrator; never assume the member-facing `postgres` login can restore Supabase-owned Auth objects |
| App/release | Matching client/API/migration versions, signed artifacts, rollback/minimum-version policy, operator and device access |

Secrets, passwords and raw financial evidence must not appear in logs or public
evidence packets. Restored jobs and outbound integrations must remain disabled
until verified and explicitly approved for activation.

## Existing export script limitation

`scripts/supabase_logical_backup.sh` is a **partial public-schema export**. It
defaults to schema-only and omits ownership/privileges; `INCLUDE_DATA=1` adds
only public-table data. It excludes Auth, private helpers, action helpers and
platform/Storage assets. It cannot satisfy the recovery gate. Its explicit
`--confirm-partial-export` flag acknowledges that narrow scope; it is not a
substitute for human approval to export customer data.

## Isolated restore procedure and acceptance

1. Verify source and destination identifiers, owner approval, snapshot age and
   encryption/access controls. Abort on an unexpected or populated target.
2. Record tool/server versions, source schema/migration version, artifact
   checksum/size and snapshot start/end times. Prevent external provider calls.
3. Restore the approved snapshot into a new isolated target with fail-on-error
   behavior. Preserve ACLs and ownership; do not use `--no-privileges` or
   `--no-owner` as an unreviewed shortcut for a failed restore.
4. Compare table counts and canonical row hashes, schema/function/policy/ACL
   definitions, foreign keys, sequences and migration history. Investigate every
   mismatch; a successful import exit code is insufficient.
5. Verify anonymous/member/Admin deny/allow paths and allowlisted responses.
   Reconcile both currencies separately, prove exact-once financial entries,
   and test journal/ledger mutation denial. Restore and verify Storage bytes.
6. Check client readback and Auth/session behavior on the isolated target.
   Validate replay/queue behavior without sending real OTPs, push or payments.
7. Measure elapsed recovery time and actual source-snapshot age against the
   approved RTO/RPO. Record gaps, signoff, retention and controlled cleanup.

## Local evidence, 2 September 2026

The engagement's `backend/41-paginated-local-restore.json` records the
106-migration local logical snapshot and restore with 99 table fingerprints,
matching columns/views/indexes/triggers/functions/constraints/policies/ACLs and
sequence values, 74 RLS-enabled public tables, denied
anonymous/member base-table access and a restored synthetic RWF 1,234 ledger
read through both the legacy and bounded member history APIs, with complete
aggregate totals and the recent-intent envelope checked. Archive SHA-256:
`baa0ba9c3c80a2544c9c6cdf01afbcbf1733e4bacdea8b9d6c7b1896695f0972`.
The earlier attempt failed on Auth schema ownership;
using the existing local Supabase administrator resolved it without new grants.

The artifact and source/restored databases remain private synthetic evidence.
The drill uses the same cluster/global roles, lacks Storage objects, and does
not cover production provider settings or secrets. Its small-dataset timings
are not production recovery guarantees. Subsequent migrations require a fresh
version-matched rehearsal before release.

Separately, `backend/39-clean-migration-replay-with-owner.json` records all 106
application migrations replayed on a fresh local Supabase platform bootstrap.
The public-group seed intentionally needs a trusted platform owner beforehand;
the first account-free run stopped there after 85 migrations. The passing run
provisioned a synthetic owner only in that isolated environment. This is not
permission to create an owner or seed synthetic accounts in production.

Sources checked 2 September 2026:
[Supabase backups](https://supabase.com/docs/guides/platform/backups) and
[PostgreSQL logical backup/restore](https://www.postgresql.org/docs/current/backup-dump.html).

## Platform approval recovery addendum

`backend/62-platform-admin-recovery-api-v2.json` records a separate current
platform-approval candidate rehearsal. The archive includes the new private
approval schema. Five access-state tables are fingerprinted, together with
relevant function definitions, RLS, grants, namespace privileges and ownership.
The restored synthetic approved operator is allowed; revoked and unapproved
operators remain denied. It uses the same local cluster and pre-existing global
roles. It does not replace the full financial/Storage/production recovery gate.

Restoring historical Auth sessions/approval records can restore historical
authority. A production recovery procedure must independently review post-snapshot
revocations and invalidate obsolete sessions before reopening access; never treat
the restored allow/deny result alone as a current human approval.
