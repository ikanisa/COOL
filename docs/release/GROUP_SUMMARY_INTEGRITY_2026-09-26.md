# Group summary integrity — 26 September 2026

## Current candidate and authority

Increment 06 combines the local Integration and Drive-filed Reconciled Increment
05 variants. Both earlier deliveries are historical baselines, not alternative
instructions to apply in succession. `revolut-design` is the only design
authority. Existing tokens and components are reused; no new design authority or
visual approval is introduced.

## New runtime behavior

The contribution group selector reads `CollectState.collectionSummaries` directly.
It no longer asks the legacy `collectionSummariesProvider` to synthesize group
aggregates from locally loaded activity. A page of contributions cannot establish
a complete group total. Missing aggregate data remains absent.

Both `GroupListPanel` and `GroupListSliver` pass a nullable summary to their shared
internal row instead of constructing a zero-valued summary. The row shows
**Not available** and announces **Group total unavailable** when its summary is
absent. Its contributor count is also unavailable, not zero. An actual supplied
zero aggregate remains zero. A supplied amount with an unknown count retains its
amount and the existing unavailable-count semantics. Amount formatting for known
summaries is unchanged. The unavailable message wraps and is not scaled down by
a FittedBox.

No summary is derived from a pending intent, payment SMS, or one activity page.
No network requests, new database calls, permission changes, payment confirmations,
ledger writes, cache deletion, or SMS replay are added by the display change.
Staleness signaling continues to belong to the existing scaffold/state.

## Merge decisions

Retain the Drive-filed recovery code with explicit
`loadInitial(syncPendingSms: false)` and its stronger stale-group fixture tests.
Retain the local namespace fix, lazy lists, strict candidate preflight runner,
scope manifest and CI integration. Keep the Drive whole-suite validation runner
and its tests as a separate, explicit full-checkout validation option. Neither
runner authenticates SDK binaries merely by comparing their version output.
The existing CI full unit/widget test command remains present.

Historical reconciliation reports are preserved and marked superseded. Earlier
local pending-upload records are archived unchanged; separate filing receipts
state their actual current upload status. Never infer filing or source application
from the existence of a local package.

## Regression coverage

`test/group_summary_integrity_test.dart` authors fourteen widget cases: eager and
lazy missing, zero, positive, unknown-count, enlarged-text and removal states,
plus two contribution-selector tests contrasting loaded and derived summaries.
These fixtures are synthetic and do not access live services.

`scripts/tests/group_summary_source_test.py` executes eight source-content checks.
Those checks are not a Dart compiler, runtime test, screen rendering or visual
acceptance. The new widget suite is declared in candidate_check_scope.json for
both format checking and targeted test execution.

## Validation commands on the complete checkout

After the correct hash-checked installer has been applied to a complete authorized
checkout with its locked dependencies resolved:

```bash
python3 scripts/qa/verify_candidate.py --check
python3 scripts/qa/verify_candidate.py --run
bash scripts/qa/run_integrated_candidate_checks.sh
```

The first command is preflight only. The second checks declared formatting targets,
whole-checkout analysis and declared delivered widget suites. The third retains
the Drive branch's full unit/widget suite behavior. The actual result of each
stage must be recorded; no missing SDK, missing checkout or failed stage is a pass.

## Deliberately unchanged and remaining scope

The summary model, repository loader/state and aggregate parser are not changed.
Other screens that use summaryFor or the legacy summary provider, and model-level
legacy JSON zero defaults, are outside this scoped change and still need review.
This increment does not certify all financial display paths, currency conversion,
backend aggregate correctness, cache freshness, complete asset pruning, complete
repository scan coverage, or 60 FPS performance.

Original Drive source files outside the delivery workspace are not overwritten by
filing this candidate. This is a partial source overlay, not a complete checkout.
No deployment, live database change, Flutter/device execution or visual acceptance
is implied by upload, archive integrity or source-content tests.

## Documentation references checked

Dart null safety and local-variable promotion:
https://dart.dev/null-safety/understanding-null-safety

Flutter Text constructor (softWrap, style and semantics options):
https://api.flutter.dev/flutter/widgets/Text/Text.html

These references support API usage, not execution of the pinned application SDK.
