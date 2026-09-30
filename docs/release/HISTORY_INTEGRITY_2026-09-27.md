# Member history integrity — Increment 10

## Contract and scope

This increment builds on the filed Increment 09 source candidate. It changes the
history page model, history controller, and the existing history-reader response
check. It does not introduce a new endpoint, alter SQL, initiate a payment, open
USSD, replay an SMS, or post a ledger entry. The original backend permissions,
account validation in CollectRepository.fetchHistoryPage, and recovery safeguards
are retained. `revolut-design` remains the only design authority; no visual
redesign or alternative design approval is introduced.

The original migration 20260902100046_member_bounded_history_pages.sql was read
to confirm the transport and ordering rules. The RPC returns complete-match
aggregates and revision-bound {revision, after} cursors. It ranks amounts when
requested, then posted_at, then payment_id ascending. The client retains its
50-row request limit; the database accepts limits from 1 through 100.

## Implemented behavior

1. Decoded pages reject duplicate payment IDs, duplicate ownership IDs, blank or
   padded identifiers, invalid RWF records, and non-finite/inexact counts or
   amounts beyond 9,007,199,254,740,991. This is a native/web transport-precision
   boundary, not a member contribution limit. Existing int-only decoding is
   preserved; no strings or fractional values are coerced into numbers.
2. Incoming cursors are copied into an unmodifiable map containing only the two
   scalar fields consumed by the inspected RPC. The response map cannot later
   change the next anchor. Cursor revision/last-row anchor checks remain strict.
3. Wire windows are checked against the requested group, cursor revision, page
   limit, and the four server sort modes. An initial terminal page must contain
   exactly the advertised count. A partial/accumulated cache is not treated as a
   50-row wire response by the model factory.
4. Appends require a current continuation, stable revision, stable total count,
   identical aggregate maps, unchanged ownership IDs, and no duplicate records.
   A terminal cursor is accepted exactly when the accumulated count is complete.
   When a query is supplied, ordering is verified across the page boundary too.
5. The controller watches repository replacement as well as selected state. It
   checks both profile and authenticated account identity before requests and
   before publishing results. Disposed controllers and superseded completions do
   not publish. Duplicate refreshes are suppressed while an operation is active. Refresh may
   supersede a load-more operation; neither is claimed to cancel the HTTP request.
6. A revision/contract error retains the previously loaded page and requires a
   refresh before another continuation request. A transport error retains that
   page and permits retry. Existing safe messages and footer routing are reused.

The public const page constructor remains available for existing local fixtures.
Factory-decoded pages and appended pages are immutable snapshots. Directly
constructed objects are checked when they are appended or validated against a
request; this does not make arbitrary caller-owned constructor collections
immutable. Cached seed selection and the cache's existing exception policy are
not rewritten in this increment. Validation does not prove that an authorized
server returned every eligible row, nor does it independently recompute complete
aggregates from a partial page. RLS and backend integration testing remain
separate requirements.

## Tests and required application validation

Two new Dart suites cover page parsing, cursor immutability, stable aggregates,
query scope and ordering, continuation completeness, duplicate requests,
superseded completions, account changes, disposal, provider replacement and
search debounce. They are appended to scripts/qa/candidate_check_scope.json.
The Python member_history_source_test.py suite checks source wiring only.

On a complete checkout with the pinned SDK and locked dependencies:

```bash
python3 scripts/qa/verify_candidate.py --check
python3 scripts/qa/verify_candidate.py --run
flutter test --no-pub test/member_history_page_integrity_test.dart \
  test/member_history_controller_integrity_test.dart
bash scripts/qa/run_integrated_candidate_checks.sh
```

Additionally verify the real RPC using authorized test accounts: page more than
100 records; select each sort and a single group; change records or permissions
between pages; verify refresh rather than stale continuation; switch accounts
while a request is pending; check both native and web number boundaries. Do not
use production customer records for fixture tests or mutate a production ledger
as a test. No such backend execution is claimed here.

## Delivery

Deliver as NEW files under
COOL/Implementation_Delivery_2026-09-26/Increment_10_History_Integrity.
The cumulative source directory is a partial overlay, not a full repository.
Use the included hash-checked installer against the recorded prior candidate and
fresh original history files. Keep the package outside the checkout. Stop other
writers, run --check first, and stop on conflicts. The separate filing receipt
records actual Drive IDs/readback; passing a tooling suite or uploading the files
is not a Flutter build, runtime verification, deployment, or release approval.

## Primary references checked

- Supabase Dart RPC: https://supabase.com/docs/reference/dart/rpc
- Riverpod refs: https://riverpod.dev/docs/concepts2/refs
- Dart native/web number representation:
  https://dart.dev/resources/language/number-representation
- Dart Map.unmodifiable:
  https://api.dart.dev/dart-core/Map/Map.unmodifiable.html

No dependency version or API generation is changed. The Supabase markdown
changelog request was attempted but was not readable by the web tool. The
implementation retains the repository's current RPC interface.
