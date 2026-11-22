# Native lease history: isolated PostgreSQL contract

This test uses a pinned schema-only synthetic 032 fixture and the reviewed 033
migration inputs. It starts an owned, networkless PostgreSQL container with no
host mounts or published ports, applies 303–308, and removes only that container.
The test creates synthetic users, sources, grants and jobs; it never connects to
the live database. A real lease expiry takes approximately 30 seconds.

Set these environment variables before running `python3 -B
scripts/supabase/testing/native-lease-history/run.py` from the repository root:

* `COLLECT_NATIVE_HISTORY_FIXTURE_DIR`: absolute path to the pinned
  `schema-only.dump` and `synthetic-roles.sql` files. Their SHA-256 hashes are
  checked by the runner.
* `COLLECT_NATIVE_HISTORY_PREDECESSOR_MIGRATIONS`: absolute path to the reviewed
  033 migration directory; its first 52 migration hashes must match this repo.
* `COLLECT_NATIVE_HISTORY_DOCKER_CONTEXT`: an explicit isolated Docker context
  containing the pinned PostgreSQL image; the runner never pulls an image.
* `COLLECT_NATIVE_HISTORY_EVIDENCE_DIR`: an absolute, new directory under an
  existing parent, created privately for the result JSON.
* `COLLECT_NATIVE_HISTORY_RESERVE_PATHS`: JSON array of absolute paths for all
  relevant storage volumes. The runner checks each path, the inputs, evidence
  parent, repo and root for at least 3 GiB plus a 48 MiB stop reserve.

The seed stubs the native source snapshot, so this test alone does not prove
end-to-end capture, carrier confirmation, beneficiary eligibility, or posting.
Pre-install lease versions remain unknown. The financial worker and retention
operations must remain held until their separate requirements are qualified.
