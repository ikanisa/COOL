# Synthetic backup governor and verified-read boundary

This is an **owned-fixture implementation**. Every exported execution route
rejects managed mode before reading other inputs. The composed test uses a
synthetic loopback dump adapter, but loopback is only the first TCP hop: a
caller-controlled proxy can forward to another database. Use only an owned
fixture, synthetic credentials and a trusted fixture proxy. This does not
authorize a live backup; a production executor, trusted deployment and
independent review are still required.

## Single trusted-root attempt record

The journal uses one owner-only, 0700 trusted root. It exclusively creates a
single `active-attempt` file, a per-operation journal and a one-use dispatch
permit. It flushes the active record and directory and records and flushes the
`dispatch_intent` **before** the synthetic backup operation starts. Competing
cooperating processes using that same root cannot obtain two permits. A
completed or unknown outcome is appended and flushed, and the active record
is retained in either case. Clearing or resetting it is intentionally not
implemented. A missing response is never permission to retry; an independently
supervised read can report the recorded outcome without starting a dump.

This is a **single trusted-root gate**, not project-wide exclusion: another
machine, alternate root, noncooperative process or privileged actor can act
independently. The journal's hash chain catches selected accidental alterations,
but is not signed, tamper-resistant or protected from its owning user. The
fixture trusts the code that reports a completed synthetic artifact; it does not
independently attest a real backup. `fsync` and directory sync are requested,
but sudden-power-loss persistence, disk firmware and remote filesystems have
not been tested. Failed or uncertain record writes retain whatever active state
exists and must be inspected rather than reset automatically. No production
operator override or recovery procedure is supplied.

## Independent deadline and uncertain outcomes

The outer synthetic supervisor starts a detached worker process and sends it
only configuration, paths and a public fixture certificate. Password/key bytes
are read later by supervised private-input children; they are not passed in
argv, environment or logs. The parent enforces a bounded deadline even if the
worker's JavaScript event loop is blocked. It sends termination to the owned
process group, escalates if needed, awaits the worker's `close` event and checks
whether the group has disappeared. A deadline remains an **unknown outcome**
even when termination is confirmed. If the group cannot be shown gone, the
result is `group_stop_unconfirmed`; do not delete the attempt or assume its
children stopped. The tests retain an uncertain synthetic fixture rather than
cleaning it up.

This is not a proof against descendants that deliberately escape the process
group, PID/process-group reuse, an uninterruptible kernel I/O operation,
parent/supervisor termination, compromised executables, or another machine.
The hard deadline is a prototype control, not a replacement for an independently
governed production process, durable external journal and verified global
actor exclusion. Journal and encrypted-artifact roots must be separate and
non-overlapping. The synthetic gate remains closed after success as well as
failure.

## Authenticated parser input

The composed synthetic backup uses the standard single AES-256-GCM archive
from the preparation module. Before launching `pg_restore --list`, it verifies
the full archive. A second full verification computes SHA-256 hashes for
bounded 1 MiB ciphertext blocks, using at most roughly 3.2 MiB of hash map at
the 100 GiB fixture ceiling. During the parser pass each block is compared to
that authenticated map **before** it is decrypted or delivered. Header and tag
are pinned, the complete second GCM pass is checked, and a changed block is
refused before its plaintext reaches the parser. This is a content-integrity
boundary; it does **not** prevent a process from writing the scratch file, and
it does not establish global actor or writer exclusion. Real cutover still
needs an independently established actor/writer exclusion boundary for the
full operation. Privileged process injection, a stolen key and corruption of
the running process are outside this fixture's proof.

The block map uses standard SHA-256 and the preparation's single GCM stream;
it is not a replacement encrypted file format. It never writes a plaintext
dump file. A detected change before linking, interrupted parser or failed
authentication prevents a successful result. After linking, the candidate
reopens and reauthenticates the final inode and compares its digest to the
inspected snapshot. A link-time mismatch retains both names as unconfirmed.
This readback is point-in-time evidence: it cannot stop modification after the
check, so independent writer exclusion remains required. Async reads, writes,
locks and filesystem sync can still become
uninterruptible at OS level; if the outer process cannot establish termination,
the outcome stays unconfirmed. The secret passfile is immediately unlinked
but scratch-backed, so secure erasure of its blocks is not established.

## Synthetic tests and remaining gaps

```sh
node --test --test-concurrency=1 \
  scripts/supabase/managed-cloud-backup-governor/*.test.mjs
```

The owned PostgreSQL 17/macOS wrapper fixture exercises the synthetic TLS and
SCRAM boundary, a compressed dump over 8 MiB, 250,000 restored fixture rows,
authenticated block checks, password and host failures, same-root concurrent
dispatch, blocked-worker deadlines, and a deliberately lost acknowledgement
for a real synthetic dump followed by independent journal readback. Separate
unit tests modify ciphertext between passes and show the changed block is
withheld. These tests do not establish production-size performance, restore of
managed Supabase internals, writer exclusion or live provider behavior.

A database custom dump does not contain external Storage object bytes,
cluster-global roles and configuration, Auth provider settings, Edge Function
secrets, Realtime state, device/offline state, physical WAL/PITR or a coordinated
cross-system snapshot. The production path remains hard-disabled pending
independent review, verified endpoint/CA and role privileges, a trusted
production process and key-custody setup, actual global actor exclusion,
object capture, a managed-compatible restore test, and a release procedure
that handles uncertain backup and cleanup outcomes. No live backup, production
write or cutover is performed here.
