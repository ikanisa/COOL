# Candidate5 bounded nonblocking IO correction

This private proposal fixes the concrete recovery4 stdin failure and the same
nonblocking readiness race on stdout/stderr. It has not executed recovery5.
Maintained source, canonical registers, earlier packets and actual outputs are
unchanged. Root owns scope review and any actual Docker/SQL recovery execution.

The retained recovery4 result is
`/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate4/docs/release/committed-recovery4/result.json`,
SHA-256 `c45b2065e944992dde7d26e03715d5eae27e254fa0058c1f34c988450ffecf4f`.
It failed with `[Errno 35] Resource temporarily unavailable` after 22 passing
cases, including complete restored predecessor catalog/effective ACL equality,
all18 committed projections and the wrong-ACL rollback negative. It replayed
45 original forward migrations through `20261001000200`; remaining forward
replay and final acceptance were not reached. Its elapsed time was
124.90146304200607 seconds. The result records both owned task containers
removed, with no cleanup errors. This is readback of retained cleanup evidence,
not a new Docker inspection. All193 actual4 files are preserved in the hash fence.

The original `Runner.call` selects nonblocking descriptors, then calls
`os.write` or `os.read` without handling a transient loss of readiness. An actual
write can therefore raise EAGAIN after the selector reports writable. The
minimal patch imports `errno` and catches `BlockingIOError` around those two
calls. Only EAGAIN/EWOULDBLOCK proceeds to the next selector iteration. It keeps
the descriptor registered and advances the write offset only after successful
OS writes. Other error numbers are raised unchanged. The only other rehearsal
change is the exact private candidate4-to-candidate5 path.

The original 600-second whole budget, 540-second execution/60-second cleanup
allocation, per-command monotonic deadline, .05-second selector call, 16KiB IO
chunks, input/output/error limits, BrokenPipe behavior, exit checks, SIGKILL
process-group cleanup, five-second wait and refusal receipts remain unchanged.
No new sleep or deadline extension is introduced. Under the deliberately forced
pipe race the selector can repeatedly report readiness; the original monotonic
guard still bounds retries. This proposal does not claim a CPU-performance change.
Catalog, effective ACL, durable dump, source removal, compatibility repair,
wrong-ACL rollback, all18 projection and final209 comparisons are unchanged.

Actual focused validation completed eight tests in1.598seconds under a
20-second outer bound: the two affected original Runner tests and six new IO
methods. The new methods use local Python children and real OS pipes:

- Actual competing writes fill nonblocking stdin after readiness. The corrected
  Runner observes errno35, handles1221 kernel short writes and returns the exact
  622,593-byte body with matching input/output hashes. The actual fixture observed
  93,062 retry errors; body equality is asserted, not inferred from counters.
- The unchanged original Runner on the same fixture reproduces the real errno35
  refusal; its process group is removed. Recovery4 remains a failed attempt.
- A competing read drains actual stdout between readiness and `os.read`, causing
  one genuine EAGAIN. Cached competing-reader bytes and later output reach the
  Runner exactly in order.
- Backpressured stdin reaches the original command timeout and group cleanup;
  the Runner's whole deadline is unchanged.
- A child exiting7 while stdin is blocked preserves BrokenPipe and both checked
  and unchecked nonzero-exit behavior.
- Injected EIO and non-retry EINPROGRESS remain fatal and preserve group cleanup.

The original two Runner cases additionally exercise concurrent input/output,
the output limit and wall deadline. All eight new-case child completions record
closed streams and absent process groups; the two outer supervisors also finish
with absent groups. Actual command inputs, output hashes, error numbers and
completion receipts are retained. No old SQL/parser/catalog suite was rerun.
Prior successful receipts are reused only for unchanged code/assertions/inputs;
all34 original test-file bytes and method ASTs are preserved.

Candidate5 contains the exact original222 input hashes:216 sources, including
209 migrations, and six references. The current216 source bytes, old candidate
inputs, all earlier retained preparations/failures and all193 actual4 originals
remain unchanged across932 fenced files. All source-scope JSON and prerequisite
SQL derivatives are byte-identical to preparation4. The command/authority matrix
preserves the original SQL and review schema, with new code/input/path bindings
and an explicit IO delta. It creates no review decision or shipping admission.

Review targets are `rehearsal.py.diff`, `test_runner_io.py`,
`affected-proof-summary.json`, `actual-io-observations.json`,
`final-invariant-review.json`, `retained-failure4-readback.json` and
`command-scope-matrix.json`. `inputs.json` binds the new private candidate.
Preparation5 code SHA is
`c5638cd21b30b5ac66c92682801ba9df01724a0c66423c9a462f28d9f67d6ec7`;
inputs SHA is
`96edb560734ec9d0b0a0bf3d4ddd63fded27b103e8866a818dd1759d34293fc3`.
Root must retain a separately reviewed code/input-bound local synthetic decision
before running the proposed command. Existing-output refusal preserves this
packet and candidate; no actual candidate5 recovery, provider, hosted, signed
package or full-system recovery acceptance is claimed.
