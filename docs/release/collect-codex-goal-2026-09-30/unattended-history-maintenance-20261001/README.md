# T13: durable scheduler history maintenance

The runner and scheduler now resolve one shared append-only history index instead
of stopping after1,000 claim links. Every segment records128 closed transitions,
bound to the original principal/key/root, exact plan/step/closure hashes and its
predecessor index digest. The selected segment's source records, predecessor
binding and current head are reread before use. Original requests, signatures'
digests, outcomes, run plans, overlap claims and closures are never overwritten
or evicted. A segment certifies closed claim transitions; its tail may still be
unresolved and is never represented as completed business work or delivery.

Numbered segments use the existing private canonical store's exclusive,
fsynced, hard-link publication and readback. Concurrent maintenance accepts only
the identical published segment. The original per-tail step hard link remains
the overlap CAS, so an index cannot grant a second local claim. Observed malformed
or missing predecessor proofs, source substitutions and invalid chronology refuse
progress. Index failure refuses the invocation before a new transport begins;
a fresh process can validate/reuse an intact segment after failure. A genuine
crash leaving a multiply-linked temporary record remains a store integrity refusal
requiring manual local recovery; this slice does not delete orphan evidence.

Index discovery uses bounded exponential/binary search. Routine resolution reads
one selected128-transition source segment plus the unindexed tail, rather than
the entire archive. Legacy migration performs at most4,096 transitions and32
segment publications per invocation, retaining completed work before returning
`UNATTENDED_HISTORY_MAINTENANCE_REQUIRED`. A subsequent invocation continues from
those proofs without replaying a business request. Sequence numbers are bounded
at1,000,000,000. This is history indexing, not whole-archive revalidation, deletion,
retention approval, sender-journal compaction or authenticated protection against
a malicious owner who controls all local source/evidence files.

The current combined eight-file unattended-client regression passed146/146 with
zero failures/skips/cancellations, and TypeScript validation exited0. All82
captured source inputs and the pinned Node/TSC entrypoint hashes were unchanged
before/after; all82 source copies were separately hashed and read back. Exact
commands, environment keys and raw stdout/stderr are in `checks-final`.

The new21 history cases include1,101 schema-valid synthetic historical closed
batches followed by a next runner transition, restart/no original replay, bounded
indexed reads, an unresolved tail, before/after-link and directory-fsync faults,
concurrent index publishers, canonical source/index/root substitutions, missing
predecessor and cyclic sources, scheduler backoff/concurrent ticks/recovery, and
bounded continuation over4,130 historical batches. Historical seed records are
synthetic local inputs, not1,101 or4,130 executed database batches. Existing actual
Edge-handler/P-256/strict-contract tests ran in the same combined scope with
injected RPC responses; no real backend was contacted.

The existing fixed plan-relative deadline, unstarted recovery, original UUID
retention, unknown-outcome reconciliation and backoff remain in use. No Admin,
profile/enrollment, launchd preparer, dependency lock, installed MCP allowlist,
Keychain, hosted configuration or live sender was changed. Earlier sealed client
and scheduler scopes remain historical independent packets; counts are not added.

The packet proves this local source-bound slice only. Hosted deployment, actual
key enrollment/activation, supported unattended execution, storage capacity and
retention, physical Android/SIM/carrier behavior and production acceptance remain
separate. No reviewed/current source freeze or artifact-specific approval is
inferred. Earlier preliminary checks and their single repaired failure are retained
as transcript observations in `development-checks.json`, without invented raw logs.
