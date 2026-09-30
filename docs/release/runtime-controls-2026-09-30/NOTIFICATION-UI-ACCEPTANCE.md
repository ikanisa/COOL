# Notification preference recovery UI

Actual current widget/SDK acceptance is recorded in
`notification-ui-runtime-attempt2/validation.json`: six tests passed, the two
owned files analyze cleanly, and captured source hashes remained unchanged.
The packet contains immutable source copies, exact commands, toolchain output
and stdout/stderr hashes. Run it with `scripts/tests/notification_ui_gate.py`.

The screen requires an acknowledged fresh server revision before editing.
After an uncertain/conflicting write it retains all four intended preferences,
offers a read-only refresh, displays saved-versus-intended values, and requires
an explicit save or local discard. Refresh and discard send no save request.
The verified retry uses the newly acknowledged revision while retaining the
original intended values; it does not silently merge or retry.

Errors use stable inline live-region text in the scrollable content. A
transient error overlay could cover the compact discard control in the earlier
test setup. The inline correction and actual hit-testable controls are covered
at320x568 and doubled text size. Old refresh failures after A→B and A→B→A
produce no stale error or private diagnostic text.

The initial failed packet `notification-ui-runtime-attempt1` is preserved.
Intermediate tool-recorded diagnostics corrected a missing host Scaffold,
double disposal, null-bodied no-argument RPC fixtures, HTTP request binding,
real SDK scheduling and lazy scroll/settling in the test setup. These setup
corrections are not represented as production defects or passing evidence.

This is local widget execution with synthetic HTTP/Auth responses through the
real pinned Supabase SDK. Actual PostgreSQL147 acceptance is the separate
110-check/11-race packet. Provider delivery, deployed sessions, actual browser
rendering and whole-goal acceptance are not established by these six tests.
