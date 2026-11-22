# Synthetic encrypted inert restore qualification

This is a **macOS synthetic fixture**, not a production backup or restore
operator. It accepts no archive, data, credential, project, connection, SQL or
database input. The Node child constructs only the fixed checked-in synthetic
archive fixture, checks its exact seed hash, and invokes the existing
`current-archive/restore.mjs` native inert restore. A real cloud capture or key
is never opened. The resulting check is not a managed Auth or Storage restore,
not an operational database, and not whole-system recovery acceptance.

The supervisor creates one new 256 MiB sparse APFS image in an owned 0700
`/private/tmp` child. It requests AES-256 with a fresh random image passphrase
through `hdiutil` standard input and verifies the reported encrypted backing and
sparse format. It identifies the mounted device through the exact created image
path and mount point, and confirms that the mount uses a distinct filesystem.
It creates a fresh PostgreSQL 17 cluster and unique credentials inside the image;
local TCP is limited to `127.0.0.1`, host authentication uses SCRAM, and local
socket authentication is rejected. The parent checks the actual server PID,
data directory, port and socket in `postmaster.pid`. A child receives its
ephemeral PostgreSQL credential only over a pipe, restricts connections to the
generated loopback identity and database names, and checks the reported cluster
name, data directory and consistent PostgreSQL system identifier on each
connection. The identifier is learned from the first connection; it is not an
independent host attestation.

The library checks a one-row, four-column synthetic native-cell roundtrip and
the inert-only receipt. Normal completion and a confirmed SIGTERM after server
readiness stop the owned PostgreSQL process, verify its stopped state, check the
same mounted image/device binding, detach that device, verify the image is no
longer attached, and remove only the original owned scratch directory. An
unconfirmed disk operation, server stop, mount identity or detach prevents
scratch deletion. A failed synthetic run writes a bounded 0600 `RECOVERY.json`
with stage and resource-state metadata when possible; it includes no password
or fixture row values. The random image passphrase is discarded on exit, so a
detached preserved synthetic image is intentionally not recoverable afterward.
A hard kill, machine failure or terminated system helper can leave an attached
image or running process; inspect the retained owned root and host before any
manual cleanup. An immediate kill cannot be guaranteed to run cleanup.

Passwords are absent from arguments, environment and routine output; the
temporary PostgreSQL password file is created only inside the encrypted image
and removed after successful initialization. Buffer clearing is best effort:
JavaScript/Python strings, OS memory, swap, crash dumps, the same-user host,
system binaries, trust boundaries and filesystem metadata are not fully
protected. The passphrase and synthetic fixture are not independent key
custody. The design must receive independent review and separate capability,
credential, current-snapshot, confidentiality and failure-path work before any
real archive is considered. Do not adapt the fixture to real data merely by
changing a flag. Use a trusted Python interpreter and launch it with a clean
environment; child-process environment filtering cannot undo a preload or
Python import hook that executed before the supervisor started.

## Run

From the repository root, with the pinned Node 24 runtime and PostgreSQL 17
tools installed at their configured physical paths:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v \
  scripts.supabase.current-pg-transfer.encrypted-inert-restore.qualify_test
```

`COLLECT_SYNTHETIC_PG_BIN` may specify another absolute **physical** PostgreSQL
17 binary directory. The test includes actual macOS encrypted-image creation,
an owned synthetic PostgreSQL roundtrip, SIGTERM cleanup after the server is
ready, preservation of an injected failure receipt, refusal of real-mode
arguments, and exact image/device/PID identity checks. Its three image/PG cases
are skipped on non-macOS hosts; a Linux or hosted run does not establish this
macOS behavior. The command creates no Supabase staging service, contacts no
network other than owned loopback PostgreSQL, and does not use an existing local
database.
