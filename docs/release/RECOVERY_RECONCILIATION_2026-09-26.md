> Historical Increment 05 branch record. For the combined candidate and new group-summary behavior, see GROUP_SUMMARY_INTEGRITY_2026-09-26.md. Earlier test counts refer to their original run, not this increment.

# Increment 05 — reconcile the two recovery branches

`revolut-design` is the only design authority. This is an integration candidate,
not new visual approval, a full repository, or a production release.

## Source decisions

The Drive-filed Recovery Integrity branch contains 63 inspected source paths.
The previously pending Recovery Lists branch contains 65. Their union contains
73 paths; 55 are present in both and 53 of those match byte-for-byte. Two differ:

- `lib/features/status/connection_recovery_screens.dart`: keep the Drive branch's
  repository-derived recovery state, guarded data refresh, account/repository
  ownership checks, SMS warning, and no-op/error handling. Make the existing
  `syncPendingSms: false` default explicit at the call site. A completed Future
  alone is not reported as successful sync or payment confirmation.
- `lib/features/payments/contribution_flow_screen.dart`: keep the Lists branch's
  prefixed `forms.CollectFormViewport` import/use. Retain the legacy exported
  viewport type and all payment methods.

Bring in the Lists branch's lazy group selection, shared list parameters, and
namespace test. Retain the Integrity branch's recovery and disabled-action tests.
The older plural-named recovery test file now exercises the current messages and
real fixture repository instead of overriding a provider no longer used by the
screen. Its eight availability/navigation cases are retained, not skipped.
Update its two static recovery assertions from the obsolete navigation-only
implementation to the guarded, data-only refresh implementation. Historical
Lists prose is marked superseded for recovery behavior.

## Validation entrypoint

Run `bash scripts/qa/run_integrated_candidate_checks.sh` only inside the full,
pinned-SDK, dependency-resolved checkout. This checks required inputs and both
regression suites, compares Flutter with `.fvmrc`, checks that the Dart executable
matches Flutter's reported bundled Dart, checks formatting without editing source,
then runs whole-checkout `flutter analyze --no-pub` and `flutter test --no-pub`.
It does not narrow analysis to the overlay or select only one branch's tests.
Any missing prerequisite or failed stage stops the command. No dependency upgrade,
package fetch, migration, build upload, or deployment occurs.

The Python runner tests use disposable fake SDK executables to test orchestration.
They are not Dart compilation, Flutter runtime tests, or visual acceptance.
The execution receipt states separately whether the real application command ran.

## Installation

Use the manifest matching the checkout: original inspected baseline, Drive
Recovery Integrity branch, or Lists branch. Do not apply the two old branches
on top of each other. Each installer is read-only by default, checks exact source
hashes, makes backups on explicit application, and stops on unreviewed changes.
All source files outside its reviewed scope are left alone. Do not apply any
installer to a Google Drive delivery folder or mistake the partial `source/`
tree for a complete checkout.

## References consulted

Dart import prefixes: https://dart.dev/language/libraries
Read-only formatting checks: https://dart.dev/tools/dart-format
Flutter testing layers: https://docs.flutter.dev/testing/overview

## Filing and scope

All delivered source, test, runner, manifest, and validation files belong in the
COOL Drive delivery workspace. Uploading a candidate is not applying it to the
original repository. Preserve previous delivery history and keep the main index
pointing to the latest verified candidate. The latest source manifest and filing
record, not an older branch receipt, determine this increment's status.
