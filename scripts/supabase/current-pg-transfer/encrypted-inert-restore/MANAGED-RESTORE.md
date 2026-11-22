# Auth and Storage metadata inert restore candidates

These are two separately scoped entry points, sharing an encrypted-image
supervisor and a component-checked private child:

* `auth-managed-restore.py` authenticates only the pinned managed Auth result,
  ciphertext, snapshot, and separated key, then tests the Auth inert API.
* `storage-managed-restore.py` does the same for managed Storage **metadata**.

Both launchers are fixed to the exact historical project, RESULT path and SHA-256,
T7 ciphertext location and ciphertext SHA-256 listed in their source. Their
real mode also requires an independently reviewed source-manifest hash and the
snapshot hash recorded in the pinned receipt. Each RESULT is itself the
component's write receipt: its
top-level fields are authenticated by the independently recorded RESULT hash,
and its ciphertext hash is cross-checked against the independently checked T7
copy. The snapshot digest was extracted from the already pinned RESULT, so it is
not a separate live capture or independent snapshot observation. Both hashes are
also checked against authenticated decrypted content. Envelope archive and key identifiers,
scope, reference hash, row counts, component flags and project identity must
match. The key stays at the separate private path in that RESULT.

**Do not run against a real capture until the exact sources, manifests, input
paths and pins have received independent review.** Neither the launcher nor
this test suite connects to Supabase or the active local database. From the
physical checkout root, the invocation shapes after that review are:

```sh
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 scripts/supabase/current-pg-transfer/encrypted-inert-restore/auth-managed-restore.py \
  --real-capture --source-manifest-sha256 59749471b55e30e62e9ab1ed65bc7621bac12da36fdf3d5b3416e4107b75b0e2 \
  --capture-result '/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116/auth-ciphertext/capture-20261113/RESULT.json' \
  --capture-result-sha256 452674e3d5e5b0aeb601d82ef7a54360f04bb6c5d723d4fff84af78fb3ab554f \
  --ciphertext-copy '/Volumes/T7/Collect-Cloud-Recovery/production-auth-20261113/auth.encrypted.archive.json' \
  --ciphertext-sha256 b5f60e2ab6153d93eeaed42a6176e968e0af7ed778b7866d1e0d7c0dd4b1405d \
  --snapshot-sha256 5b47c4fb6230c819e0bbbbf644c73d06ca7dd34286c21a160952cd2a651a90e2

/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 scripts/supabase/current-pg-transfer/encrypted-inert-restore/storage-managed-restore.py \
  --real-capture --source-manifest-sha256 fed3d9911c17cb794099ebaa45fae1115558fa014da88f969b27af2abf693c3f \
  --capture-result '/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116/storage-v2-ciphertext/capture-20261113/RESULT.json' \
  --capture-result-sha256 a4d02e403e80b6ee75f8194fe636f4b59e0e949c5ab0c64977cc46e20fb42a01 \
  --ciphertext-copy '/Volumes/T7/Collect-Cloud-Recovery/production-storage-metadata-20261113/storage-metadata.encrypted.archive.json' \
  --ciphertext-sha256 63e01bc62cc07d46db3537d52dad43ee9352d6212c2aa883eef62905c9405977 \
  --snapshot-sha256 337de2b96f9172ac4f20d016a70fcea3a7a604b165a8ef7893db8beca6d62c1e
```

The selected ciphertext file must be a single-link, owner-owned 0600 or 0700
regular file in a physical private 0700 directory. Only ciphertext is staged
into the encrypted image. The RESULT and the separately held key must each be
single-link, owner-owned 0600 regular files in physical private 0700
directories; archive and key directories must be separated. No key bytes,
database passwords or cells belong in arguments, logs or environment variables.
The fixed RESULT path differs from the T7 ciphertext-copy path; the historical
RESULT pin and the copy's independent ciphertext pin must both match.

The supervisor checks the reviewed manifest and all selected executable hashes
before launching the PostgreSQL version probe; it rechecks the probe executable
afterward and checks relevant executables before each direct invocation. It
creates an AES-256 encrypted sparse image with an APFS filesystem and an owned,
random-credential loopback-only PostgreSQL 17 cluster, checks the mounted image
and PG identity, and runs the component's existing authenticated bundle reader
and native-cell inert restore API inside it. All PostgreSQL data, temporary files
and server logs reside on that image. Routine output is limited to status, the
RESULT hash, aggregate table and row counts, and boolean checks.

A successful run stops the owned child and PG process, confirms and detaches the
owned image, and removes its scratch directory. Controlled SIGTERM follows the
same cleanup. On an uncertain operation or cleanup, the scratch root and
sanitized `RECOVERY.json` are retained when possible; do not blindly delete or
detach them. The ephemeral image password is discarded at process exit, so a
preserved detached image cannot be reopened by this tool and is not a backup.
A hard kill, crash, power failure or interrupted disk operation may leave the
image mounted and accessible to the same user. Immutable source and a trusted
host remain necessary: checks cannot prevent a replace-and-restore race or
attest Python, system tools, dynamic libraries, OS paging, crash reports, memory
inspection, system logs or endpoint software.

The Auth API checks native columns, cell values, enums and inert sequence
metadata; it does not activate GoTrue, providers, sessions or a live sequence.
The Storage API checks native metadata columns, cell values and enums; it does
not read or restore object bodies, activate access controls, signed URLs,
tokens, multipart authority or an operational Storage service. These component
captures do not establish cross-service consistency, quiescence, independent
key custody, a complete recovery, or authorization for production restore.

Run the native suite using newly generated synthetic values only:

```sh
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 scripts/supabase/current-pg-transfer/encrypted-inert-restore/managed_restore_test.py -v
```

The generated synthetic snapshots use the libraries' real envelope shape with
`fixture: false` because the component bundle writers reject fixture envelopes;
all cells are generated inside the short-lived image, and the supervisor reports
the run as synthetic. The tests exercise both actual writer/read/restore APIs,
including native round trips, receipt and ciphertext tampering, key failure,
snapshot mismatch, source-pin refusal and controlled interruptions. They do not
open either real capture, key or production database.
