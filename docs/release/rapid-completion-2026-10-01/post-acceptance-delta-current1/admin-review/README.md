# Captured Admin delta review

**Scoped acceptance: 322 passing VM cases across ten affected cohorts.** This
accepts the captured application inputs plus the explicitly proposed private
resource correction. It does not accept the changing live repository, a new
production browser bundle, or the complete database installer.

## Concrete correction

The canonical browser checkpoint store reads `window.sessionStorage` without a
size bound. The new workflow card decoded that string before its model limits.
Bookmark and quarantine helpers also allocated the complete UTF8 buffer before
checking its size. The runtime-only patch first checks code-unit length, then
bounded UTF8 byte length, then decodes. Recovery, sanitized quarantine and
original-request proof rules remain intact.

- [Runtime-only patch](runtime-resource-admission.patch): exactly two production files.
- [Expected source hashes](runtime-patch-bindings.json): require these bytes before integration.
- [Private widget proof](resource-admission-widget-proof.patch): two oversized ASCII/multibyte recovery and reload cases; bounded sanitized metadata, blocked actions and no lookup.
- [Findings](findings.json): exact source/function and evidence limits.

No live production or peer test file was edited. An owner must integrate the
runtime correction against their current source; the dated fixture patches must
not overwrite later peer work.

## Executed scope

| Cohort | Accepted cases |
| --- | ---: |
| Entity audit links | 34 |
| Entity audit page | 32 |
| Assignment dialog and recovery | 44 |
| Followup SDK | 23 |
| Followup DTOs | 45 |
| Joined history DTOs | 29 |
| Joined history SDK | 30 |
| Workflow SDK | 39 |
| Workflow and inbox consumers | 35 |
| Inbox DTOs | 11 |

[Named executed cases](named-cases.json) and [accepted union](accepted-union.json)
bind the 311 unchanged cases from the ten-file run to the corrected eleven-case
inbox run. The only change between those executions was one negative test UUID
inside `main()`; imported fixture helpers, runtime, SDK and package inputs match.
The fixture had supplied the original delivery UUID while expecting rejection.
[Its isolated test correction](inbox-fixture-correction.patch) is separate from
the runtime proposal.

The affected SDK tests exercise the actual locked Supabase client with synthetic
HTTP responses through `MockClient`: exact RPC/body/Bearer, one dispatch on
denial/fault/timeout, original request fingerprint, late session replacement,
logout and sticky A→B→A suppression. Production widget tests exercise current
permission/role/session loading, directory paging, cancellation, checkpoint
corruption, lost responses and original-proof recovery. These named executions
establish their specific behavior, not an exhaustive state cross product.

Twelve added decoder cases consume unchanged observed JSON from the parent's
[current 100-case SQL subset](../sql-current/readback.json): eight joined-history
responses and four current-recipient inbox responses, preserving timestamps,
actors, event/delivery IDs and paired cursors. They distinguish available,
unavailable, retained and incomplete history without inventing source resolution
or delivery authority. This review made no SQL calls. That retained server proof
uses an isolated schema153 plus additive subset and synthetic API claims; its
ordinary-installer and hosted limitations remain applicable.

## Integrity and failures retained

[Consumed inputs](consumed-inputs.json) conservatively binds 952 application,
test, asset, fork and fixture inputs from the frozen composite. SDK and all 168
resolved package scopes remained unchanged. The private copied source remained
unchanged during each execution. Selected analysis used `--fatal-infos`, and
selected nonwriting formatting passed on the private derivative.

- Original formatting findings in eight files are retained in `original-selected-format.log`; formatting was performed only in the private copy.
- `prepare-failed1.json` retains an unrelated MCP symlink-copy admission failure, corrected by copying declared files only.
- `attempt1-preparation-failure/` retains the added bridge enum typo and missing cached package graph. No cases executed in that attempt.
- `attempt2-ten-cohorts/` retains the actual 321 pass / 1 false-negative fixture failure.
- The final inbox selection passed eleven cases; its raw `validation.json` still reports the broader composite guard failure truthfully.

The parent updated `20261001200000_exception_inbox_audit_v2.sql` in the composite
after the copy. That single **nonconsumed SQL source drift** is retained in both
raw validations. It does not change the copied Flutter inputs or observations;
the scoped union excludes a whole-composite/live-current claim. Later peer
features outside the captured delta remain unverified here. No browser, native,
theme or live-source changes were made by this review.
