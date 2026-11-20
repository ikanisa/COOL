# Production-bound encrypted-dump preparation

This directory contains **synthetic preparation only**. Production dispatch is
an unconditional `managed_execution_closed` error, before reading inputs. The
implemented test executor forces its first TCP hop to loopback. A caller-controlled
local proxy can forward the connection to another database, so loopback alone
does not establish the ultimate server's identity or make real access impossible.
Use only an owned fixture, synthetic credentials and a trusted fixture proxy.
Independent review and a separate, explicitly implemented production adapter
are required before live use.

The immutable intended binding is host
`db.rrlduytparvsjfmegalh.supabase.co`, port `5432`, database `postgres`, role
`postgres`, and provider-root certificate DER SHA-256
`807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa`.
`checkPinnedProviderRoot` validates the already supplied **public** PEM using
the existing certificate helper; it does not connect to Supabase. The test
executor uses that hostname for TLS hostname verification but forces the
network address to `127.0.0.1`, supplies a separately pinned synthetic CA, and
uses an ephemeral fixture port. The loopback TLS proxy terminates TLS before
forwarding to its owned Unix-socket PostgreSQL fixture. These tests do not
verify the live project's current certificate, DNS, authentication, privileges,
network route or cloud project identity.

## Protected inputs and artifacts

The synthetic executor reads its password and 32-byte encryption key from
separate caller-named private files using short-lived, independently supervised
child processes. A child requires a regular file owned by the current user,
mode 0600, one link, no symlink, and a directly containing directory owned by
the user with no group/other access. It checks the inode before and after open,
limits the password to 4096 bytes, requires a key of exactly 32 bytes, and
rejects password NULs or line breaks rather than silently changing the
password. The password path is sent over the child's private stdin; password
bytes return over a private pipe. Passwords and keys are never put into argv,
environment variables or logs. A test-only stalled child is terminated after a
bounded wait; if closure cannot be confirmed, `input_stop_unconfirmed` is
reported and no dump is started. This does not eliminate risk from privileged
or same-user actors, process memory, swap, core dumps, filesystem snapshots, or
all ancestor-directory races. Secret-file compatibility with the user's real
file has not been tested.

The synthetic `pg_dump` child receives an immediately unlinked, 0600
scratch-backed passfile at `/dev/fd/3` and fixture CA at `/dev/fd/4`. PostgreSQL
17 libpq requires its passfile to be a private regular file; a pipe is not a
substitute. Unlinking the scratch passfile does not guarantee secure deletion
of filesystem blocks or snapshots. The dump uses `sslmode=verify-full`, GSS
transport disabled, a read-only transaction default, custom format and a
bounded lock wait. Tool wrapper and wrapped-executable digests are checked
against supplied values, but the shared libraries, OS loader and initial
fixture-binary resolution are not pinned; callers must trust the runtime.

The dump is streamed to a fresh exclusive 0600 `.partial` file through a
single standard AES-256-GCM stream; it does not write a plaintext dump file.
Its header contains `COLLECTPGGCM2`, a random 96-bit IV, and a SHA-256 digest
of a fixed **synthetic-purpose** context plus the intended binding above. The
whole header is authenticated as AAD; the final 128-bit GCM tag follows the
ciphertext. The archive is explicitly synthetic and the context hash does not
prove that its content came from the cloud project. Keys must be randomly
generated, separately held and recoverable; key creation, escrow, rotation and
retention are outside this preparation.

The implementation permits at most 100 GiB of archive plaintext and processes
data in stream-sized chunks, without an archive-sized plaintext allocation.
The verified tests cover a 16 MiB byte stream and a compressed PostgreSQL dump
greater than 8 MiB, not 100 GiB or an actual managed database. A full first
pass verifies the GCM tag before `pg_restore --list` is started. A second
read-only pass streams decrypted bytes to the parser and is authenticated again;
if the parser closes its input early, another full authentication pass must
match the original ciphertext digest. A private scratch directory and
independent exclusion of concurrent file writers remain necessary: a changed
file during the second pass can reach the parser before its second tag check.
The final artifact is not promoted unless verification succeeds and the TOC
lists `app`, `private`, `auth` and `storage`. After linking the final name, the
candidate reopens that inode, authenticates it again and checks its digest
against the inspected snapshot before returning success. A link-time mismatch
retains the final and partial names as unconfirmed; they are not a completed
backup. This readback is point-in-time evidence and cannot prevent changes after
the check, so independent writer exclusion is still required. TOC presence is
not a full data, object, policy, permission or restore check.

Timeouts terminate and wait for dump and inspection children where possible.
An unconfirmed child stop retains the encrypted partial and reports an
unconfirmed outcome; a crash can also leave a partial. Fresh final names use
no-overwrite hard links, and promotion or directory-sync ambiguity is reported
separately. There is no durable dispatch journal or independent outer process
governor. Async filesystem I/O or filesystem sync can stall despite in-process
timers, and a killed/unconfirmed subprocess or privileged actor requires
separate investigation. These are open requirements for any production
executor. The module does not automatically retry uncertain attempts.

## Tests and remaining recovery work

From the repository root, with the bundled macOS PostgreSQL 17 wrappers:

```sh
node --test --test-concurrency=1 \
  scripts/supabase/managed-cloud-backup-preparation/*.test.mjs
```

Tests use owned synthetic PostgreSQL and loopback TLS, a synthetic SCRAM
password and temporary certificates. They check the project binding and hard
managed-mode closure, input-file permissions and child timeout, hostname/CA and
password refusal, dump timeout, streaming/tamper/early-consumer handling, a
stalled inspector's termination, and a synthetic restore of 250,000 rows plus
private, Auth and Storage fixture tables. The observed wrapper layout is macOS
specific; plain Linux PostgreSQL binaries have not been qualified. All test
fixtures are disposable and no production connection is made.

Even a successful database dump does not capture external object bytes,
cluster-global roles/configuration, provider Auth settings, Realtime state,
Edge Function code/secrets, device/offline state, physical WAL/PITR or a
coordinated source-and-Storage snapshot. Hosted Supabase extension, role,
owner, permission and restore compatibility need separate proof. [Supabase's
backup and restore guidance](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
describes CLI-based role, schema and data handling and special treatment for
managed migration history and Auth/Storage schemas. Raw `pg_dump` plus a TOC
listing does not perform or prove that managed recovery. A real
production operation still requires independently confirmed endpoint/CA and
password-file access, trusted runtime and toolchain, external key custody,
full-source privilege and object inventory, coordinated writer exclusion,
backup retention, an independently governed timeout/uncertain-outcome journal,
and a tested managed-compatible recovery path. Nothing here constitutes a
live backup, authorization to cut over, or a successful production migration.
