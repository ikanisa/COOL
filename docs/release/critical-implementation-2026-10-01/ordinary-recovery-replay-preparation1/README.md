# Proposed ordinary logical recovery and original migration replay

Prepared only. No Docker container, PostgreSQL dump, restore, or migration has
run from this candidate. The focused stdlib tests exercise the parser and bounds;
they do not prove recovery. Shipping source, SQL, migration history, admission
policy and registers remain untouched.

The required outcome is a committed synthetic predecessor backup, restoration
into a second independently owned local target, and the original 85 pending
migrations as `postgres NOSUPERUSER`. The existing admitted proof already covers
all 209 migrations in clean/populated targets. This proposal reuses its exact
216 inputs and its 124-version predecessor rather than repeating clean replay.

The private input copies are in
`/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate1`.
`inputs.json` records every SHA-256. Reference files are copied from the sealed
`ordinary-schema-catalog209-execution1` packet. Its complete current209 catalog
is bound to `4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c`.
Every predecessor and final catalog comparison includes all effective ACLs,
roles, memberships, defaults, routines, extensions and database metadata returned
by the unmodified catalog query.

Fresh seed timestamps and generated IDs differ from the older proof. The actual
current209 proof binds the projection column cohort and complete catalog, not the
fresh data hashes. All 18 fresh-run hashes must instead equal each other at the
committed predecessor, restored predecessor, before/after every one of the 85
original migrations, and final state. No row values are fabricated to match the
older randomized hashes.

`pg_dump` captures a whole database with data, ownership, ACLs and the exact
`schema_migrations.statements` history. It does not capture cluster role globals
or all modifications to extension members. The target therefore derives from
`template0`, recreates the exact image role fixture and source database identity,
and explicitly installs the source extension versions under their source owners.
The retained trusted net function metadata is reapplied as a named prerequisite.
Only extension/schema CREATE entries already satisfied by those prerequisites
and separately satisfied database controls are commented in the restore TOC.
All application DDL, data, original history and ACL entries remain intact. The
complete restored predecessor must equal the complete committed source before
forward replay begins. A difference fails; the comparator does not ignore or
normalize missing metadata.

This restore prerequisite is a proposal requiring code/scope review. The shipping
`postgres_admission` policy remains limited to PostgreSQL 17.6 query/migration.
It does not admit restore. The candidate separately requires a retained local
review record bound to the exact code hash, input manifest hash, immutable image,
17.6 client/server and three fixture operations. The candidate cannot create or
authenticate the record; a hash binding is not reviewer authentication. No
shipping restore admission or external acceptance is claimed.

The retained cached image is
`sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a`.
The rehearsal records resolved absolute in-image `psql`, `pg_dump`, `pg_restore`
and `postgres` executable paths, actual bytes hashes and version outputs, plus
the actual server version number. Every application query and dump/restore tool
then uses that captured absolute path and freshly checks its bytes. Initial
image-only readiness/role setup runs before tool discovery; it does not apply
an application migration.

Each container has a unique `collect.recovery.owner` label, `--pull=never`,
`--network=none`, no ports or host mounts, exactly one 1 GiB tmpfs, no privileged
mode or added capabilities/devices, cron launch off, net batch zero and empty
network queue/cron history. Cleanup refuses another owner/image/scope and verifies
absence after removal. The program has a whole 600-second bound, reserving 60
seconds for failure cleanup. Tool input/stdout are capped at 64 MiB, stderr at
1 MiB; command timeouts also obey the remaining program budget.

The dump is written only after committed seed statements, from a separate
`pg_dump` session, fsynced to a private file and sealed by its actual SHA-256.
The source container is removed before starting the restore container. The
restore runs explicitly as fixture-only `supabase_admin`; before the first
pending migration, `postgres` is demoted and its current user/role/NOSUPERUSER
state is read back. CREATE ROLE/CREATE DB/BYPASSRLS and trusted memberships remain
explicit local-image limitations.

Meaningful negatives cover an unsupported client version, corrupt archive
content rejected by the real seal reader, and an actual wrong table ACL observed
through the complete catalog then rolled back before forward replay. That
rollback concerns only the ACL fault. The predecessor dump and restore are
committed operations.

The output contains synthetic-only fingerprints, catalogs, dump seal, original
SQL execution hashes, tool identities and safeguards. The private dump contains
only synthetic fixture rows and no Auth credential/session secrets. There are
no real Auth/customer/financial/provider rows, exports of a production app,
downloads, provider calls, published ports or maintained source/SQL/register
changes. Full BE-08, hosted/system recovery, ARC-08 restore adapter, ARC-11 and
release/production acceptance remain open.

The exact proposed command/input/scope matrix is in `command-scope-matrix.json`.
Execution waits for the parent's code/scope review. The review decision template
is documented in that matrix and is deliberately not written as an approval.

PostgreSQL's documented single-database/role-global boundary and archive restore
semantics are described in [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html)
and [pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html). The
extension archive entry has no owner field in the [17.6 dumpExtension source](https://github.com/postgres/postgres/blob/REL_17_6/src/bin/pg_dump/pg_dump.c#L10208).
