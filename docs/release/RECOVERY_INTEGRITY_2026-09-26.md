# Recovery integrity — 26 September 2026

## Implemented candidate

The connection and data-sync routes use the existing repository state instead of
assuming that a route name proves a network outage, durable local storage,
queue protection, or successful synchronization. `revolut-design` remains the
sole design authority. This change uses existing Collect components and tokens;
it introduces no parallel visual standard and grants no design acceptance.

The former secondary status card and its static Saved / Protected / Masked
badges are removed. One recovery panel contains a data-refresh action and a
groups navigation action. The privacy route remains reachable. The last data
refresh is shown from the actual timestamp, or as Not available. A profile alone
does not imply that groups are loaded. Timestamp formatting uses the active
Flutter locale and local time preferences; it does not estimate freshness.

## Data refresh, not payment execution

The refresh calls the existing `CollectRepository.loadInitial()` method without
requesting SMS replay. It does not create payment intents, open USSD, resubmit
payments, clear cached data, confirm contributions, or write ledger entries.
The existing repository's read/cache behavior is unchanged.

Future completion alone is insufficient: the screen reports a successful data
refresh only when the repository and account still match, loading has ended,
there is no error or stale-cache fallback, and the recorded successful refresh
time is present and newer than the pre-request timestamp. A missing backend
configuration can cause the existing loader to return without doing work; that
no-op is not presented as success. A successful empty response can count as a
data refresh without claiming that groups were found.

This is not a connectivity monitor. The UI cannot distinguish offline transport,
server outage, authorization failure, or another failed load from the existing
state alone. It therefore uses neutral recovery language, never an inferred
network diagnosis. Raw backend exceptions are not rendered to the member.

## Lifecycle and concurrent actions

The callback blocks repeated taps immediately, before a widget rebuild, and
refuses to start alongside an already-active repository load. A widget keyed to
the repository instance and account identity resets its transient status after
an account or repository change. Mounted and ownership checks protect completion
and exception handling. The repository's own generation checks remain unchanged.
Navigating away does not cancel the underlying repository request; it prevents
its completion from changing the disposed screen. No cancellation is claimed.

A later external data refresh can clear an obsolete local failure display. It
does not receive this screen's own success acknowledgement automatically.
SMS queue-overflow / attention flags remain visible after a successful data
refresh, with access to Settings. Data refresh does not claim to fix SMS sync.

## Existing disabled-action protection

The inspected shared danger-button tokens already prioritize disabled state
before pressed state, using the existing neutral background and muted foreground.
They remain byte-for-byte unchanged. Regression tests check both themes, combined
interaction states, the missing callback, and the absence of tap semantics.
No repository-wide claim is made about other independently styled controls.

## Validation boundary

`test/connection_recovery_screen_test.dart` defines 19 widget cases covering
empty/profile-only/loaded states, no-op and empty success, handled and thrown
errors, stale or backward timestamps, repeated taps, existing loads, SMS attention,
account/repository replacement, navigation, external refresh, and compact
320-by-568 views with a 220-pixel keyboard and 2x/3x text. Three additional widget
cases cover existing disabled destructive buttons. These cases must be run on
the complete, SDK-equipped checkout; authoring a test is not executing it.

```bash
bash scripts/qa/run_recovery_checks.sh
```

The runner verifies tool availability, complete-checkout inputs, the `.fvmrc`
Flutter pin, formatting, targeted analysis, and the two widget suites. It stops
on the first failure and uses `--no-pub` rather than silently changing dependency
resolution. The eight Python runner tests exercise fake SDK commands in isolated
temporary directories; they test shell orchestration only, not the application.

See the filed implementation receipt and actual validation logs for this run's
results. No Flutter execution, device testing, visual approval, deployment,
production configuration change, or original-file in-place application is implied
by a successful tooling test or Google Drive upload.
