# Admin session/action local verification — 30 September2026

**Scoped local result: PASS. Full24-item local acceptance remains open.**

## Implemented and checked

- Generic Admin repositories/providers use the original actor/session and Auth generation. Requests pin their starting authorization token and reject stale success/errors, including A→B→A. Same-session token refresh stays supported.
- Auth stream errors/closure and token expiry invalidate authorization and pending requests. Reconciliation UI scopes also include generation, so coalesced A→B→A cannot revive an earlier modal or selection.
- Session changes clear private reason dialogs and sensitive state. The detail provider avoids accidental request restart during reason-dialog/keyboard rebuilds. Operation-specific acknowledgements reject null, malformed, wrong-ID/status and unreviewed responses before success feedback.
- Freshness resets on replacement login/logout. A disposed overview cannot mark a new workspace successfully refreshed after its old asynchronous batch completes.
- The error corpus includes synthetic secrets, phone/receipt data, SQL messages and nested SDK/provider failures. Only allowlisted recovery text is rendered.320px at1x/2x checks include text/semantics leakage and an actionable Retry control.
- Shared Revolut-authorized typography replaced the roster dialog's raw text-style sites. No complete visual/reference parity claim is made.

## Evidence

`attempt5-integrated/validation.json` binds280 passing tests,15-item clean analysis, the pinned Flutter3.44.4/Dart3.12.2 version output and214 unchanged runtime/test/font/lock inputs. The complete tested source snapshot is retained alongside logs. Tests use mocked Auth/HTTP and synthetic identities; no database/provider/hosted calls occurred.

`attempt1` retains the earlier333-pass/one-typography-failure output. `attempt2-session-controls` retains84passes/one direct-SDK fixture-map typing failure. The fixture was corrected with typed metadata maps. `attempt3-integrated` is the earlier268-pass/14-analysis source set. `attempt4-integrated` retains280 passing tests plus one prefer-const analyzer finding in the new error fixture. That fixture was corrected and attempt5 reran the recorded scope. Counts have overlapping scopes and are not summed.

## Reproduce

Run `python3 scripts/tests/verify_admin_session_actions.py --flutter /absolute/pinned/flutter/bin/flutter --pub-cache /absolute/pinned/pub-cache --output /new/empty/evidence/directory` from the checkout. The runner refuses to overwrite prior evidence and fails if source changes during the run. It never updates golden references.

## Remaining scope

Every Admin operation's complete route/action/state/audit matrix, actual local multi-tab/browser lifecycle,144 reload runtime, final frozen migration/source integration and all other24-item requirements remain. Later roster/OTP/database edits require their own source-bound evidence; this dated packet preserves its tested bytes. Production acceptance remains separate.
