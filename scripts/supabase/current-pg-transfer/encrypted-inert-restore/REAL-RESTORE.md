# Reviewed encrypted-image capture restore

This is a **separate** launcher from `qualify.py`. It authenticates an existing
Collect app/private capture and tests an inert native-cell restore using a new,
short-lived PostgreSQL 17 cluster. It does not connect to Supabase, the active
local database, or any other PostgreSQL server. A successful result is evidence
for the selected archive's app/private cell values only; it is **not** a full
recovery, a managed Auth or Storage restore, or authorization to restore into
production.

The operator must independently obtain and review the exact SHA-256 of the
capture's `RESULT.json` and the exact SHA-256 of `REAL-SOURCE-PINS.json`. The
manifest pins this launcher, its child, the archive code used, the `pg` package
tree and selected dependency trees, the lockfile, the Node executable, and the
four PostgreSQL executables. The result pins the receipt and summary, which in
turn pin the source snapshot, project, archive ciphertext and the separated
private-key path. A hash acquired from the same untrusted source as a modified
file is not an independent integrity check.

The selected ciphertext may be a copy. Its hash and length must exactly match
the pinned receipt. A private 0700 directory and an owner-owned, single-link
0600 or 0700 regular ciphertext file are required. Only the ciphertext is
staged into the encrypted image; the archive reader then authenticates it with
the existing key at the receipt's path, which must be in a separate private
0700 directory and be an owner-owned, single-link 0600 regular file. The result,
receipt, and summary are also required to be private 0600 files in private 0700
directories. All paths must be absolute physical paths without symlinks. The
launcher never writes an unencrypted copy of the archive, key, database
credentials, or PostgreSQL data outside the image.

From the physical checkout root, **after independent source and pin review**:

```sh
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 scripts/supabase/current-pg-transfer/encrypted-inert-restore/real-restore.py \
  --real-capture \
  --source-manifest-sha256 'REVIEWED_MANIFEST_SHA256' \
  --capture-result '/ABSOLUTE/PHYSICAL/PATH/RESULT.json' \
  --capture-result-sha256 'INDEPENDENTLY_RECORDED_RESULT_SHA256' \
  --ciphertext-copy '/ABSOLUTE/PHYSICAL/PATH/SELECTED-CIPHERTEXT'
```

Do not put the key contents or database passwords in command arguments, shell
history, logs or environment variables. A local process running as the same user
can still inspect the process or alter its files; run on a trusted, controlled
host. The source manifest and all pinned executable hashes are checked before
the first PostgreSQL version probe; that binary is checked again after the probe
and before use. The relevant executable is checked again before each direct
invocation, and the source set is checked before launching the archive child and
after the restore. These checks do not make the mutable checkout immutable,
prevent a replace-and-restore race, attest dynamic libraries, system tools,
Python, OS services or hardware, or replace an independently controlled,
immutable source and trusted-execution environment. A manifest is meaningful
only if its hash and the hashes it binds have been independently reviewed.

The image is an AES-256 encrypted sparse disk image containing an APFS
filesystem. The launcher checks the image metadata and the exact mount/device
binding, creates an authenticated loopback-only cluster with unique random
credentials, and verifies the owned PostgreSQL identity before each connection.
All PostgreSQL data, temporary files, and the server log are inside the image.
Routine output contains only the pinned result hash, aggregate counts and
boolean checks; PostgreSQL statement/error logging is disabled or minimized.
The launcher does not intentionally write plaintext cells, credentials or key
bytes elsewhere. It cannot guarantee the behavior of OS paging, crash reports,
memory inspection, system logging, endpoint security tools, or other software.

On verified success, the owned child and server are stopped, the exact image is
detached, and the owned scratch directory is removed. A controlled SIGTERM uses
the same cleanup. If cleanup or any operation is uncertain, the launcher keeps
its own scratch root and a sanitized `RECOVERY.json` where possible; do not
blindly delete or detach anything. The ephemeral image password is discarded at
exit. Therefore a preserved but detached image cannot be reopened using this
tool; it is diagnostic evidence rather than a backup. A hard kill, host crash,
power loss, or interruption of a disk operation cannot guarantee cleanup; an
image may remain mounted and accessible to the same user until independently
identified and safely detached. The original ciphertext and key are not
modified by this launcher.

Limits include a 1 GiB sparse image, at least 2 GiB free on the scratch volume,
bounded archive/cell counts, a five-minute child timeout and a PostgreSQL 17
requirement. A larger valid capture may fail without invalidating the original.
Independent key custody, Auth identities and secrets, object bodies, database
roles, policies, functions, triggers, extensions, network services, application
behavior and a full disaster recovery remain untested by this workflow.

Run the end-to-end tests using newly generated synthetic data only:

```sh
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 scripts/supabase/current-pg-transfer/encrypted-inert-restore/real_restore_test.py -v
```

The test suite exercises actual encrypted image creation and detachment,
PostgreSQL restore and comparison, a 0700 ciphertext file, five kinds of
tampering, an incorrect manifest pin, a changed PostgreSQL binary that must not
execute, version-probe rechecking, real-mode test-injection rejection and
controlled SIGTERM during child creation and after synthetic decryption. It also
tests rejection of mismatched or ambiguous device and PostgreSQL PID bindings.
It does not open a real capture or key. A successful synthetic test does not
establish that any particular real capture or its custody paths are valid.
