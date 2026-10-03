# Private SDK phase-artifact correction

This packet proposes a minimal correction for independent root review. It executes
no real exporter, SDK, Flutter, Gradle, database or provider operation. Original
preparation1 and snapshot-preparation2 seals and leaves remain intact. Maintained
source, registers, actual SDK/app/control state and the relocated generated
test-cache recovery archive were untouched by this preparation.

Actual attempt1 failed. Its strict export child exited zero in 74.499 seconds,
and its before/after source fences passed, but the final SDK startup readback tried
to create the initial `SDK-readback-startup.stdout` again. The resulting
`FileExistsError` caused `stage_pass=false`. Child success does not admit the stage,
accept the candidate or permit advancement. `attempt1-failure-readback.json`
retains the failure and observed log hashes; root must preserve the complete
failed candidate/control files separately before any fresh attempt.

The controller changes only the fresh root review directory, `source_readback`
and its two callers. A fixed `before` or `after` observation now separates all
SDK logs, process receipts and JSON output names. Both app-export reader commands
still verify phase `startup`, use the original verifier with `-I -B`, retain
300-second bounds and the 4 GiB live floor, and require original process success.
Invalid observations are refused. A repeated identical observation still fails
exclusive creation and cannot overwrite or reuse artifacts. The failure diagnostic
reader keeps its separate existing names.

`controller-diff.patch` and `configuration-diff.patch` contain the exact delta
from snapshot-preparation2. Reversing the allowlisted changes reproduces its exact
controller bytes. Fifteen other function ASTs, including `authorization`,
`protected_metadata`, `run_process` and `require_pass`, are unchanged.
`source_fence.py` is byte-identical. The only configuration change is
`root-sdk-native-snapshot-review3`; all exporter arrays, tool hashes, environment,
private roots, locks and resource bounds remain exact.

Five focused tests passed with zero failures, errors or skips. Real Python children
under small physical `/private/tmp` fixtures proved distinct before/after startup
artifacts and genuine exit-23 reader failures. Both failure positions exercised
the controller exception/terminal branch: failed terminal, preserved partial
files, no export binding, no promotion, approval or next-stage admission. The
terminal tests explicitly replace unrelated admission/source/export boundaries
with synthetic fixtures; they certify this naming change and failure handling,
not real export or SDK acceptance. Test fixtures were removed. Retained reports
include the real process records and logs. The parent process exited zero in
12.048 seconds with its owned group absent and no timeout/headroom failure.

`guard-inheritance-proof.json` revalidates all 42 current source/tool identity rows
against each earlier source-bound passed receipt. The original 31 and snapshot 34
cases and their inputs are unchanged. Their suite passes remain historical;
no fresh combined 65-case run is claimed. The changed reader behavior has its own
five-case proof. Original immutable packets were also reverified: 33 preparation,
56 snapshot, 2 plan and 47 prior execution leaves. A focused independent reviewer
found no material defect and made no writes.

Root must independently verify every final packet leaf, the exact delta/helper,
tests and prior seals. After separately preserving failed attempt1, both original
`app-source` and `.control/app-export` paths must be absent. Recheck the private
root, exact tools, passed startup predecessor and all 68,020 protected metadata
paths. The historical failed-attempt diagnostic reported them unchanged; this
proposal does not substitute that observation for the new admission check.

Create the fresh owner-only `root-sdk-native-snapshot-review3` directory and use
the exact capture argv in `proposed-execution-matrix.json`, with distinct child
`source-fence.json` and process `source-fence-process` names, a 300-second bound
and 4 GiB live floor. Independently validate and pin that fresh descriptor after
review. `proposed-root-admission.json` is an unissued template; root must fill the
final manifest digest, verified leaf count and fresh fence digest, then separately
admit only a full fresh app-export using the passed startup predecessor. The exact
controller argv in the matrix has explicit root digest placeholders. No receipt
or review directory is created by this packet.

All three claims remain false: `source_scope_held_for_strict_export`,
`source_lock_attested` and `transient_write_and_restore_absence_attested`. The full
strict exporter, SDK lock/readback, before/after source comparisons, private
candidate and final protected metadata checks remain required. Observation fences
do not attest an OS source lock, absence of transient writes, OS immutable flags
or production freeze. Existing per-process bounds remain; no whole-stage outer
deadline is added or claimed.

Every other stage remains unadmitted. A successful fresh export would require its
own independent actual readback and seal before any later app-lock/native admission.
There is no automatic advancement, lock upgrade/download, SDK/candidate promotion
or production approval. ARC-09 and release acceptance remain open.

`packet-files.json` seals every safe top-level proposal leaf; `sha256sums.txt` also
includes the manifest digest. No fixture, symlink, hardlink, nested directory or
mutable external artifact is part of this packet.
