# Essential Admin exception corrections

The three Admin differences from native export 125 enable exception follow-up
and the recipient escalation inbox. This review covered those enabled flows.

## Corrected defects

- Both follow-up openers now use the existing shared motion adapter and the
  session dialog. Account/session replacement, capability departure and observed
  A-B-A invalidate the original dialog permanently. Keyboard Escape closes it;
  reduced-motion route durations are zero.
- Assignment checkpoints previously stored an operator UUID. Version 2 stores
  `self`; decoding requires a fresh authorized actor and verifies the actor and
  exception owner digest. Resolution retains a null assignee. Actor-bearing
  legacy/forged forms fail closed. Pending references are concealed while
  identity or read capabilities are unavailable.
- The follow-up review found that rejection alone left actor-bearing bytes in
  browser session storage. The load boundary now replaces rejected data with
  version 3 owner/exception and opaque original-request/action/revision references.
  It never converts this block into a submit-ready intent. Unknown or negative
  lookups preserve the block; only an exact durable recorded receipt may clear it.
  Malformed data retains a reference-free block. Replacement failure removes the
  rejected private bytes and keeps the current tab blocked.

## Verification

- [Dialog and common session packet](admin-session-current1/validation.json):
  **83 passed**, zero failures/skips/unfinished, selected analyzer and format pass.
  This is captured-source evidence before the checkpoint correction.
- [Affected checkpoint packet](admin-checkpoint-current3/validation.json):
  **12 passed**, zero failures/skips/unfinished, selected analyzer and format pass.
  Current runtime/test and export inputs were unchanged through this run. Shared
  confirmation/list changes made by the root were captured before invocation.
  This packet predates the subsequent recovery-load scrub correction.
- [Exact scrub/recovery packet](admin-checkpoint-scrub-current4/validation.json):
  **8 passed**, zero failures/skips/unfinished, selected analysis and formatting
  pass. Runtime/test and export inputs were unchanged through this run. It covers
  forged actor data, legacy reload, exact recorded receipt, expired negative
  lookup, malformed private payload, replacement failure and departing authority.
- The initial model analyzer caught a test-only `Map.single` typo; its failure
  remains in `admin-checkpoint-current2/selected-analysis.log`. It was corrected
  before the twelve selected tests executed.
- Existing exception lifecycle SQL acceptance has **41 passing cases**. Its nine
  recorded source hashes still match. This isolated, owner-normalized schema
  installation remains dated evidence; no SQL rehearsal or hosted installation
  was repeated.

## Source-backed control trace

SDK actions retain the shared request-session fence and make one mutation
attempt. Receipts must match request, exception, source/workflow revisions and
action, and deny false financial/send claims. In-flight session departure
suppresses old responses. Recipient opening requires the exact delivery ID,
valid timestamp and non-resolution acknowledgement. Errors remain generic.

The lifecycle migration checks current private actor authority; source and
workflow revisions are checked before mutation. Original requests, delivery
and read evidence are immutable. Workflow mutations create an audit record;
the private tables deny direct public/anonymous/authenticated/service access.
The unchanged SQL packet covers assignment, expiry, request collision/replay,
recipient loss/restoration, direct-table denial and financial preservation.

## Limits

This closes the identified exception defects; it does not close all E1 roster,
import/export, role or cross-group criteria. Rejected actor-bearing checkpoint
bytes are removed; opaque blocked references retain the original uncertain
operation without replay. The browser storage adapter is unchanged. Version 2
encoding and the new scrub/load boundary were verified through model/widget
tests using the same store contract, not a new browser build. No native build,
provider call or database deployment was performed here.

[Source hashes and scoped reuse record](admin-essential-review.json).
