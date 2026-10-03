# Current candidate database recovery

The existing encrypted full-database capture and isolated archive restore now
accept an explicit source contract. This removes the historical97 count gate
from the selected current workflow without treating any new migration count as
acceptance. The default historical invocation retains its original scope.

The [contract helper](../../scripts/audits/collect_recovery_source.rb) binds the
exact local migration paths, versions and SHA-256 hashes to a captured
[PostgreSQL17 catalog](../../scripts/sql/collect_recovery_source_catalog.sql).
It records the server version, database properties, all non-system namespaces,
extension versions/owners, password-free role attributes/memberships, hashed
settings, relations/columns, constraints/indexes, function hashes, policies,
triggers, default ACLs, types, event triggers and logical dependencies. Catalog
ACLs expand NULL to PostgreSQL defaults and sort their intact entries; explicit
empty ACLs still mean no grants. Rebuilt TOAST and internal FK-trigger names
contain source OIDs and are excluded from dependency identity. Logical table,
column and constraint definitions remain checked.

Collect the catalog through the intended read-only database connection. Retain
its actual command, authenticated source identity and tool hashes alongside the
output. Preparing a contract checks an input; it does not authenticate that
input or certify the source, a release, data recovery or approvals. Do not
prepare the release contract while its source candidate is still changing.

```sh
ruby scripts/audits/collect_recovery_source.rb prepare \
  /absolute/private/source-catalog.json /absolute/private/candidate-source.json
```

Preparation writes a new0600 file and returns its SHA-256. It reads no
credentials, vault or network service. Paths/hash must be supplied together,
duplicate/unknown arguments are refused, and source changes invalidate the
contract before the backup credential prompt or restore vault access.

```sh
ruby scripts/audits/collect_encrypted_database_backup.rb \
  --approved-ip-129.222.149.205 /absolute/private/database-report.json \
  --source-contract /absolute/private/candidate-source.json \
  --source-contract-sha256 CONTRACT_SHA256

ruby scripts/audits/collect_encrypted_database_backup.rb \
  --approved-ip-129.222.149.205 /absolute/private/roles-report.json --roles-only \
  --source-contract /absolute/private/candidate-source.json \
  --source-contract-sha256 CONTRACT_SHA256
```

These are the existing credential-on-stdin capture commands. Their original
TLS pin, exact egress-IP fence, encrypted vault/remount, full owner/ACL capture,
password-free role export and temporary-rule cleanup remain enforced. This
change performs no capture by itself. Both captures compare the exact catalog
before and after export, retain those observations inside the encrypted vault,
and associate their reports with the source contract. Those observations are
separate snapshots; `pg_dump` supplies its own consistent data snapshot. Roles
and database are separate captures. No combined snapshot claim is made.

The archive report inventories actual schema declarations and schema-qualified
TOC objects rather than a fixed schema shortlist. PostgreSQL can omit a
declaration for implicit `public` or empty extension-owned namespaces. Missing
TOC names remain explicit; complete namespace acceptance requires the restored
catalog comparison.

Supply all three captured recovery inputs to the
[isolated restore](../../scripts/tests/production_archive_restore.rb):

```sh
ruby scripts/tests/production_archive_restore.rb /absolute/private/restore-report.json \
  --database-report /absolute/private/database-report.json \
  --roles-report /absolute/private/roles-report.json \
  --extension-metadata /absolute/private/extension-metadata.json \
  --source-contract /absolute/private/candidate-source.json \
  --source-contract-sha256 CONTRACT_SHA256
```

The extension supplement must match the contract's exact GraphQL function
hash, owner, extension version and ownership set. The restore verifies both
capture associations before opening vaults, rechecks reports before reading
their encrypted archives, and retains input hashes. The existing full data,
sequence, schema/ACL and global-role comparisons remain. Its final catalog must
match the source contract, with source/query hashes still current. It verifies
source state before any business-policy alteration. No business-policy stop
overlay is added by this slice; the disposable target remains network-none,
RAM-only, with cron off and the HTTP worker bound to empty template1/batch0.
The fixed historical upgrade-rehearsal flag is refused with a current contract.

Current full-candidate data recovery, worker hot/cold graph verification,
native ciphertext/Keystore and scheduler manifest joining, durable inactive
restoration, incident drills, independent key escrow, Storage bytes, Auth and
provider configuration, and approved RPO/RTO remain separate work. No hosted
backup, production restore, sender or scheduler activation follows from local
unit or synthetic catalog evidence.

PostgreSQL catalog field definitions are documented in
[pg_database](https://www.postgresql.org/docs/17/catalog-pg-database.html),
[pg_auth_members](https://www.postgresql.org/docs/17/catalog-pg-auth-members.html)
and [pg_proc](https://www.postgresql.org/docs/17/catalog-pg-proc.html).
