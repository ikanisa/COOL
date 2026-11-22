# A04.3 — reviewed Collect source intake

**Candidate:** 0.20.0-a04.3. **Parent:** 0.20.0-a04.2. **Date:** 9 November 2026.

## Implemented boundary

A04.2 consolidated runtime safeguards but `apply_to_collect.py --apply` did not require
an approval artifact bound to the previous dry run. A04.3 requires an exact review plan
and a separately recorded SHA-256 before the CLI will write. A fresh ordinary dry run
still lists changes; it is not, by itself, authorization to apply them.

`collect_intake.py` verifies the entire candidate against its file manifest, checks the
explicit import manifest against the installer's actual selection, and binds a review to:

- Candidate version, complete source inventory, file manifest and import manifest hashes.
- Exact checkout root, Git directory, HEAD, branch, index and working-file fingerprints.
- Every import target's original bytes/mode and desired bytes/mode, including unchanged targets.
- The existing database-adapter file and exact pinned receiver inputs, even when Git ignores them.

This is an engineering content gate, not a cryptographic signature, personnel approval
system or production-acceptance certificate. Review the plan and retain the displayed digest
through an independent trusted channel; recomputing a digest from an untrusted replacement
plan is not review. Plans contain paths and hashes, not file contents, tokens or Git remote URLs.

## Read-only preparation and verification

From this candidate's root, using an existing parent directory outside both trees:

```sh
python3 scripts/apply_to_collect.py --collect-root /path/to/Collect \
  --plan-out /path/to/review/burimunsi-a04.3-plan.json
```

The command prints `plan_sha256`. Inspect the JSON before recording that digest. It uses
local Git inspection only: no fetch, checkout, index refresh, add, commit, database call or
deployment. A fresh Git worktree is supported. Nested checkout paths, fake `.git` directories,
unmerged indexes, active Git operation markers, submodules, links and case collisions are
refused. Candidate and checkout must be separate trees. Existing output plans are never overwritten.

```sh
python3 scripts/apply_to_collect.py --collect-root /path/to/Collect \
  --approved-plan /path/to/review/burimunsi-a04.3-plan.json \
  --plan-sha256 RECORDED_SHA256
```

This verifies the exact review again without writing. A changed HEAD, index, tracked file,
non-ignored untracked file, protected input, candidate or import target invalidates it.
Unrelated ignored files are deliberately outside the Git snapshot. No claim is made about
files outside that declared scope. Pathological changes while inspection is underway fail
closed where observed; this is not a simultaneous filesystem snapshot.

## Explicit application

Stop other checkout writers and review the plan before adding `--apply` to the verification
command. The command revalidates after acquiring an exclusive importer lock. It freezes the
approved source bytes, opens directory components without following symbolic links, creates
new entries without overwriting concurrent entries, writes via temporary files, syncs each
file and directory, and checks written bytes and modes. Existing files still require an
exact known prior-source hash; no force-overwrite option was added.

Caught failures trigger reverse-order rollback only where the entry still matches this
invocation's written bytes and mode. Foreign edits and unsafe replacement paths are left
untouched and reported for manual review. Recognized prior bytes and modes are restored via
atomic replacement, not an in-place truncate/write. An importer lock serializes cooperating
invocations; a replaced foreign lock is not removed.

**This is not a crash-atomic multi-file transaction.** A process kill, host crash or power loss
may leave a partial import and a lock in the worktree's Git directory. Inspect the affected
paths and compare them with the plan before removing a stale lock. Generate a new review
for the remaining work; the old pre-import plan will no longer match. Empty directories
created before a caught failure may remain. Do not automatically delete those directories
or recovery evidence. Non-cooperating concurrent writers must be stopped; the lock is not
an operating-system filesystem transaction or a sandbox against a hostile process.

## Verification and unchanged safeguards

Tests create real temporary Git repositories and worktrees and synthetic receiver/adapter
files. They exercise stale and altered reviews, partial manifests, Git/index drift, source
changes, symlinks, case collisions, exclusive-create races, failure after each written file,
mode restoration, foreign edit preservation and lock ownership. The existing full-candidate
import test now performs review -> approved apply -> idempotent re-plan instead of bypassing
review. No actual Collect checkout is modified by the test suite.

Canonical authentication, native session authority, the command journal, owner-bound recovery,
financial validation, SMS reliability and UI runtime code are byte-identical to A04.2. Only
Android version metadata advances to versionCode 22/versionName 0.20.0-a04.3; no APK is claimed.
The seven original input streams and all parent files remain in the merge/continuation ledgers.

## Remaining external acceptance

Actual Collect checkout review/application, real PostgreSQL reconciliation, hosted canonical
services, pinned Android compilation and installed instrumentation, carrier/SIM/reboot/Keystore
qualification, installed UI/TalkBack and fluent Kinyarwanda review remain outstanding. Production
promotion remains blocked and the receiving-upload hold is unchanged. The supplied local
`efficient-codex` path is not mounted in this environment. Other project conversations are not
silently treated as merged inputs; this lineage is the seven named source archives plus A04.1,
A04.2 and this A04.3 continuation.

## Reproducing this continuation's metadata and archives

The authoring-only command below rebuilds A04.3 metadata from the exact pinned A04.2
archive. It verifies that parent archive and its complete file inventory, refuses
unexplained changes to parent paths, preserves original bytes, and seals every current
file. It is not a way to certify modified source or reuse old test results. Run it
before fresh regression; changing any source afterwards invalidates the evidence.

```sh
python3 scripts/seal_a04_continuation.py \
  --parent-archive /path/to/BuriMunsi_Complete_Source_v0.20.0-a04.2.zip --write
python3 scripts/run_a04_regression.py --output ../A04.3_Evidence_new_run
python3 scripts/package_a04.py \
  --parent-archive /path/to/BuriMunsi_Complete_Source_v0.20.0-a04.2.zip \
  --evidence ../A04.3_Evidence_new_run --output ../A04.3_delivery_new_run
```

The packaging validator requires the exact eight declared checks, their actual exit
statuses, distinct hash-verified logs and a complete source snapshot. Required local
checks must pass. Native prerequisites may be explicitly blocked, never silently
counted as passed. A production designation or removed receiving hold is refused.
These bindings detect stale or altered evidence; they do not authenticate who ran the
commands or substitute for independently witnessed external acceptance.
