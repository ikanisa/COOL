# Synthetic encrypted PostgreSQL backup supervisor

This is an **owned-fixture prototype, not a cloud backup executor**. Both public
entry points reject managed mode before reading credentials or spawning a
process. They hard-code a loopback synthetic target and a fixture database/user;
they cannot connect to project `rrlduytparvsjfmegalh`. The caller, executable
paths and fixture environment are trusted. Do not use real credentials or data
with this prototype. A separate independent review is required before any
production adapter or live use.

## What the prototype tests

`createSyntheticEncryptedBackup` invokes PostgreSQL 17 `pg_dump` for one whole
synthetic database using custom format. The database connection is pinned to
`localhost` via `127.0.0.1`; libpq uses `sslmode=verify-full`, a caller-supplied
CA whose SHA-256 must match an independently supplied expected hash, GSSAPI
encryption disabled, a read-only transaction default, and a bounded lock wait.
The hash comparison is only useful when the caller obtains the expected CA hash
through a separately trusted channel. The fixture's loopback TLS proxy
terminates TLS before forwarding to an owned Unix-socket PostgreSQL server;
its success is not evidence about managed Supabase certificate configuration,
network routing, role permissions, or channel binding.

Password, encryption key and CA bytes enter through three distinct,
caller-owned descriptors for already-complete, seekable regular files. Pipes
and other non-regular descriptors are refused, and an already-aborted request
is rejected before input reads. The prototype uses synchronous positioned file
reads; a stalled filesystem can still block the process, so this is not a
wall-clock cancellation guarantee. The password is escaped as
a scoped libpq passfile line, written only after its 0600 scratch file is
unlinked, and passed to `pg_dump` as `/dev/fd/3`; the CA is similarly passed as
`/dev/fd/4`. No password is placed in command arguments, environment variables
or logs. The unlinked passfile is still backed by the scratch filesystem, so
unlinking is **not** proof of secure erasure of its blocks or snapshots. The
caller must choose appropriately protected scratch storage and control paging,
crash dumps and privileged processes. Inputs can remain in process and library
memory; buffer clearing is best-effort, not secure-erasure proof.

`pg_dump` stdout flows directly into AES-256-GCM encryption and a fresh 0600
exclusive-create `.partial` file; this code never writes a plaintext dump file.
The input key must be 32 random bytes supplied by FD. The file contains an
authenticated magic header, random 96-bit IV, ciphertext and 128-bit tag.
Key generation, separate custody, backups, rotation and recovery are outside
this module. Use of a weak, reused or lost key can compromise confidentiality or
make the backup unrecoverable. OS swap, core dumps and trusted subprocess memory
may contain plaintext or key copies.

After dump exit, the candidate requires empty stderr, syncs the encrypted
file, authenticates a bounded in-memory snapshot before giving any plaintext to
`pg_restore --list`, and checks that the TOC contains schemas `app`, `private`,
`auth` and `storage`. It then promotes the file by a same-directory no-overwrite
hard link, removes the partial name and attempts to sync the containing
directory. `inspectSyntheticEncryptedBackup` repeats authenticated, offline
listing of an existing synthetic artifact. Inspection is limited to 8 MiB of
custom archive and 512 KiB of listing; it does not inspect all data blocks or
prove a complete or usable restore. It is not a database/Storage reconciliation
and it does not prove the archive originated from a particular production
project. The archive header itself does not record or bind a cloud project,
endpoint, database identity or verified CA fingerprint.

A failed or aborted dump is never intentionally promoted; cleanup removes only
the file that this process exclusively created and still identifies by device
and inode. A child `error` event is not treated as confirmed termination: the
supervisor waits for `close`, and it signals only a child still observed as
running. A timed-out inspector is sent termination and then kill if necessary,
and its close is awaited. If dump or inspection termination cannot be confirmed,
the encrypted partial is retained with the corresponding unconfirmed result.
Cleanup and identity failures
also fail closed. Process or host termination can leave an encrypted `.partial`
file, and a crash around promotion can leave one or two names or an uncertain
directory sync. Treat any such artifact as unverified until inspected; never
assume cleanup or durability from a missing acknowledgement. The result can
also report promotion cleanup, identity or directory-sync uncertainty.

The code checks caller-provided hashes for the launcher and wrapped executables,
but it does not pin their shared libraries, the OS loader or all dependencies;
resolving the fixture binary directory itself runs PostgreSQL's version command.
These and the caller-provided connector/FDs must be trusted. The artifact
and scratch directory remain subject to access by the owning user and
privileged actors. No use against managed data is qualified by these tests.

## Coverage and production gaps

Run from the repository root:

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 \
  scripts/supabase/managed-cloud-backup/synthetic-backup.test.mjs
```

The harness creates an owned PostgreSQL cluster, synthetic SCRAM password,
short-lived test certificates and loopback TLS proxies. It verifies CA/host
and executable hash failures, password-over-FD handling (including escaping),
read-only startup settings, wrong-password and abort cleanup, required-schema
checks, synchronous cipher-setup cleanup, error-versus-close handling, a killed/reaped hung inspector, AES-GCM
corruption and wrong-key rejection, and a full restore into a
second **owned synthetic database**. The server and test artifacts are removed
after confirmed shutdown. The backup's offline list alone does not prove that
full restore; the extra restore is part of the synthetic test.

### Coordinated prior-release recovery

The same test entry point also runs a prior-release recovery rehearsal across
two independently initialized local PostgreSQL clusters. To run just this case
from the repository root, use the same PostgreSQL 17 binary configuration as above.

```sh
node --test --test-name-pattern='one fenced prior-release restore' \
  scripts/supabase/managed-cloud-backup/synthetic-backup.test.mjs
```

1. The fixture applies the first nine reviewed October migrations to an owned
   source. It creates two test Auth identities, a domain principal link, one
   payment and ledger entry for 7,250 RWF, and a private evidence object.
   The application encryption and Storage journal write and verify the object
   against a file-backed test transport. The financial write clears the sealed
   pending payload through the original evidence trigger.
2. It drains the application fence and holds read locks on the captured identity,
   Storage, financial, fence and migration records while taking the encrypted dump.
   A fixture manifest binds the database, scoped PostgreSQL roles and separately
   captured object bytes to the observed fence and migration history. Missing or
   altered components and a different fence point fail before target setup.
3. It restores the five non-login roles and the reviewed membership on an empty
   peer, then runs `pg_restore --single-transaction --exit-on-error` with the
   archived owners and privileges. It checks identity links, totals, effective
   role access, row security and financial write refusal while fenced.
4. The object-transfer coordinator writes the encrypted evidence to an exclusively
   created private file. Through PostgreSQL row security and the application's
   Storage verification and decryption routines, the owner retrieves the original
   bytes and the other identity gets no file access. The fixture repeats these
   checks after applying the immediate Realtime successor with its reviewed
   synthetic platform interface.

The Auth and Storage provider tables are local test fixtures. The rehearsal
qualifies this October migration prefix and synthetic successor. Managed project
identity, provider sign-in and Storage endpoints, current release compatibility,
production-size recovery, independent key custody and an off-device restore each
require separate evidence.

The recorded run is on macOS with the bundled PostgreSQL wrappers and their
`.pg_dump-wrapped` and `.pg_restore-wrapped` executables. The current test
assumes those wrapped filenames; it has not been qualified for a plain Linux
PostgreSQL binary layout, and no Linux coverage is claimed.

A real full-database `pg_dump` may capture database schema and rows for the
four named schemas if the selected role has sufficient privileges, but it does
not capture PostgreSQL cluster-global roles/configuration, Supabase project or
Auth provider settings, Edge Function code/secrets, Realtime service state,
external object bytes, mobile/device state, physical WAL/PITR, or independent
provider-side effects. A dump is a database snapshot, not a coordinated
snapshot of external Storage or a verified source/target migration fence.
Managed schemas, extensions, owners and restore privileges may not be
restorable into a hosted project with an ordinary role. Listing schema names
does not establish table/row completeness, policy correctness, credential
custody, or practical recovery. A real adapter needs independently verified
project/host/CA identity and credential handling, adequate database read
privileges, safe production-sized streaming validation, trusted binaries,
durable encrypted key custody, separate object capture, coordinated freeze,
retention and recovery policy, and an independently tested managed-compatible
restore. No live backup, cloud write, or production cutover is performed here.
