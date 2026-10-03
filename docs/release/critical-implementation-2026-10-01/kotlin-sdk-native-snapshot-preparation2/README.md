# Private native snapshot controller preparation

This proposal is complete for independent root review. Actual app export, app
dependency restoration and Gradle/native execution remain unexecuted. ARC-09 and
production acceptance remain open. The original controller, maintained source,
SDKs, registers, checkpoint and other human chat files were preserved.

The derivative admits only `app-export`. It uses the original sealed preparation,
fixed private native root and passed startup predecessor. Root admission must
require strict comparisons and private snapshot ownership, and explicitly record
`source_scope_held_for_strict_export=false`, `source_lock_attested=false` and
`transient_write_and_restore_absence_attested=false`.

`controller-diff.patch` contains the 125-line comparison to the original
controller. Only `authorization` and `main` differ at function AST level; the
other 15 functions are unchanged. `configuration-diff.patch` contains the six
declared admission/configuration differences. `full-proposal.patch` also includes
the source helper, guard suite, unchanged original test relocation and bounded
receipt harness. The full patch has 881 lines.

`source_fence.py` records selected source hashes, sizes, modes, device/inode,
mtime/ctime and ownership, source directory identities, exact Git index identity
and hash, HEAD, selected membership, indexed absence and the separately excluded
upstream fixtures. A second capture verifies each selected/excluded leaf and
index/membership before producing a descriptor. The controller compares fresh
captures before and after the pinned strict exporter to a root-pinned descriptor.
It preserves the strict exporter command without `--retain-source-drift`, the
original SDK/lock validators, tool hashes, private environment, source readback
deadlines, process-group cleanup and 4 GiB live floor. All configuration keys must
equal the original configuration plus the declared admission changes.

The completed source-bound runs passed all 34 snapshot guards and all 31 original
guard regressions, with zero failures, errors or skips. Each run binds 42 source
and tool records before and after; those complete identities and hashes stayed
unchanged. The process receipts report exit zero, no timeout/headroom failure and
absence of their owned process groups. Synthetic source/index/path mutations
exercise refusal, private destination ownership, exact command configuration,
root receipts and predecessor checks. Guard tests executed fresh synthetic
fixtures. Previously retained negative fixtures stayed inert.

The initial read-only capture wrapper hit a report/receipt filename collision.
Its original source descriptor and logs remain, with a separate collision audit.
The corrected derivative separates capture and process receipt names, and an
actual capture-child regression covers that correction. The first bounded test
harness then refused macOS `/usr/bin/git` because the system executable has
multiple links. That pretest refusal is retained separately. The corrected
harness records the system tool's actual hash and complete identity; every
proposal/source leaf retains single-link enforcement.

All 28 non-fixture files matched the saved usage-limit checkpoint before
resumption. The historical prerequisite readback verified the original 33-leaf
preparation, 2-leaf plan and 47-leaf execution packets, the passed startup terminal,
absence of app/control destinations, exact tool hashes and 68,020 protected
metadata paths. `current-source-fence-capture3.json` is dated preparation evidence.
It captured 2,488 selected files and 41 excluded fixture paths. It must be
refreshed after root review before any real export admission.

## Root review and admission

1. Independently verify every declared packet leaf and the full diff/helper/tests.
   Verify the original immutable packets and current startup terminal
   `28468e2cbb49e40f7f25416cd28dcb6b133b2142fa00e2ad5bce64b44b646a45`.
   Recheck protected metadata, tool identities, private root mode, app destination
   and `.control/app-export` absence.
2. After review, create the separate owner-only root review directory
   `root-sdk-native-snapshot-review2`. Use the exact fresh descriptor command in
   `proposed-execution-matrix.json`, bounded to 300 seconds with retained stdout,
   stderr and process receipt. Independently validate that descriptor against
   current source. Preserve dated descriptors and any refusal.
3. Write `app-export-admission.json` in that review directory, binding the exact
   preparation manifest hash/all verified leaves, fresh `source-fence.json`
   hash and passed startup terminal. `proposed-root-admission.json` is an
   unissued template: root must set the exact digest/count and explicitly admit
   only app-export after completing review. Keep all three held/lock/transient
   absence claims false and production approval/promotion false.
4. Run the exact controller command from the execution matrix with those two
   independently verified manifest/receipt hashes. The derivative runs SDK
   readbacks, source comparisons, strict export and private candidate readbacks.
   A refusal preserves partial files and blocks reuse/automatic advancement.
5. Independently read back and seal any successful actual snapshot and its
   source/manifest/original lock binding. App pub and native work require their
   own later admissions against that actual immutable hash binding.

## Evidence limits

These fences establish observed source identity/byte/mode equivalence across
capture and readback. They do not establish an OS exclusive workspace lock or
absence of transient activity between observations. Snapshot immutability means
fixed authored hashes/modes/manifests and private ownership readbacks; OS immutable
flags and production freeze/approval are unasserted. Existing individual process
deadlines remain; this derivative adds no whole-stage outer deadline.

The packet seal explicitly excludes `negative-fixtures`, which contains inert,
untrusted synthetic failure material including symlinks and hardlinks. Its
inventory and exclusion are recorded in `negative-fixtures-exclusion.json`.
Do not execute those retained fixture programs or treat them as an app candidate.
All other top-level proposal files are hash-bound by `packet-files.json`.
