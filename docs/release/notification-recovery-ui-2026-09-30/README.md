# P07 notification registration recovery — local evidence

Date: 30 September 2026. This packet extends the repository session-fencing
implementation with observable member recovery. P07 production acceptance remains
open; these are local checks with synthetic identities and mocked native/network
boundaries.

## Implementation

- The notification service exposes distinct checking, permission-denied,
  unavailable, connection-retry, fresh-sign-in and connected states. Phone
  permission and server registration are separate facts. Raw provider errors,
  tokens and account details are excluded from recovery text.
- Registration captures the owner, Auth session and operation generation before
  awaits. Old account/session errors and responses cannot replace newer status.
  Direct Auth events reset same-user replacement sessions; token renewal within
  the same JWT session keeps its identity.
- A connected state requires a valid UUID acknowledgment from the registration
  RPC plus the repository's current-session acknowledged provider/token tuple.
  Null, numeric, object, list, empty and malformed responses fail closed. A
  deliberate no-op or superseded repository call cannot claim connection.
- Permission checks, provider-token retrieval and registration each have a
  20-second recovery timeout. The OS permission prompt remains user-controlled.
  Timeout does not cancel already-sent work. Retries reuse the current token;
  native token callbacks and authenticated app resume use the same registration
  path. Resume also refreshes denial/unavailability after permission revocation.
- App permissions shows guidance and Retry, Phone settings or Sign in again.
  The sign-in action signs out through the fenced repository before navigating,
  and leaves a newer live session in place. Status changes use a live region.
- Permission sheets await registration instead of sending a false success
  notification immediately after permission grant. Pending primary actions are
  disabled. Dismissed sheets do not later close another route or show a stale
  recovery sheet. Account changes suppress the old request's feedback.
- Existing recipient checks, serialized notification clearing/display, event
  identifiers and generic private previews remain covered by regression tests.

## Checks and artifacts

Pinned runtime: Flutter **3.44.4**, Dart **3.12.2**. Commands use the existing
isolated `.cache/pub-cache-qa-20260929` cache with `--no-pub`. Exact executable,
commands, exit codes and source/manifest hashes are in `verification.json`;
runtime revision is in `runtime.json`.

The combined test command covers:

| Test file | Scope |
|---|---|
| `test/core/notification_registration_recovery_test.dart` | 19 service/widget checks: denial, unavailable provider, failed/stalled connection, unchanged-token retry, stale-session guidance, late errors, replacement sessions, native APNs callback and resume, settings, sign-in navigation, sheet acknowledgment/dismissal and enlarged text |
| `test/shared/repository_session_fencing_test.dart` | 31 real mocked HTTP checks, including strict UUID acknowledgment and a pending sign-out invalidating the connected tuple |
| `test/shared/member_history_pagination_test.dart` | 11 existing cache/history/auth-change regressions |
| `test/core/notification_account_isolation_test.dart` | Existing recipient, ordering, tap and generic-preview privacy checks |
| `test/features/runtime_component_contract_test.dart` | Shared UI, typography, permission-sheet and accessibility contracts |
| `test/security_hygiene_test.dart` | Existing source/security contracts, updated to reject permission-only success claims |
| `test/app_shell_test.dart` | Existing startup, lifecycle and navigation checks |

Final result: **181 tests passed** and scoped analyzer **no issues**. Logs are
retained verbatim. `verification.json` records unchanged fingerprints across the
final checks. The source graph includes current app integration, manifests and the
concurrent Admin typography correction exercised by the shared contract test.

## Design evidence

Sole authority: the selected `revolut-design` skill. Relevant references read:
brand adaptation, design overview, mobile patterns, screen typologies and
component/journey contracts. Inspected comparator images: September 2026 native
Dark · Glow **LIVE-006** grouped settings and **LIVE-023** permission primer.
These are pattern comparators; Collect retains its own content and capability.
The light state is the existing Collect shared-theme adaptation.

Implementation uses existing `CollectCard`, `CollectButton`, shared spacing,
typography, colors, responsive permission rows and bottom-sheet primitives.
No new design authority, product palette or source branding is introduced.

- `settings-dark.png`: 390 × 844, normal text, connection-retry state.
- `settings-large-light.png`: 390 × 844, 1.6× text, the same recovery state.
- Widget checks also exercise 320-pixel width at 2× text and a working sign-in
  action. Captures use the bundled Inter and Material Icons fonts; both were
  visually inspected for readable content, wrapping and reachable actions.

These captures are test-renderer evidence, not physical-device screenshots or a
claim of complete source fidelity. No source-private screenshot is copied here.

## Remaining acceptance

- Deploy and verify server migration 141, its session ordering/revocation
  guarantees and exact-session unregister against the real Auth lifecycle.
- Verify signed Android/iOS builds, real permission prompts, APNs/FCM delivery,
  token rotation, cold start, process death, account switching, offline recovery
  and background/foreground transitions on physical devices.
- Verify screen-reader speech, complete route/theme state comparison and the
  configured production provider/environment. Widget semantics and screenshots
  do not close these checks.
- No provider, live Auth, database mutation, deployment or delivery call was
  made. Best-effort cleanup and client timeouts cannot cancel an in-flight RPC;
  server ordering and session revocation remain required.

The earlier `repository-session-fencing-2026-09-30/` packet is preserved intact
as its original 35-test snapshot. This packet supersedes its current-source
fingerprints and its note that visible recovery was unimplemented. Other dirty
working-tree changes are not attributed to this task. SHA256SUMS inventories this
packet; no binaries or dependency archives are included.
