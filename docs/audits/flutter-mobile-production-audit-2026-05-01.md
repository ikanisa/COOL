# Flutter Mobile Production Audit

Date: 2026-05-01

Scope inspected: Flutter app boundary at `apps/mobile`, source under `lib/`,
tests under `test/` and `integration_test/`, Android/iOS project files, route
inventory, BioPay, MoMo, groups, auth, admin guards, shared widgets, l10n, and
release/build scripts.

## Architecture Map

- App shell: `lib/app.dart`, `lib/main.dart`, `lib/bootstrap/`
- Routing: `lib/core/router/` with `GoRouter`, auth redirects, and admin guards
- State: Riverpod providers under `lib/features/**/providers` and `lib/core/providers`
- Design system: `lib/core/theme/` plus shared widgets in `lib/shared/widgets`
- Backend: Supabase client/repositories, Edge Function clients, App Check-aware services
- Main domains present in mobile: auth/onboarding, groups/savings, MoMo wallet,
  BioPay QR/NFC/scan, profile, admin/operations
- Native shells: `android/`, `ios/`, `flavors/`

## Findings

P1 fixed in this pass:

- `TransactionStatusChip` collapsed external payment lifecycle statuses into
  broad labels, making instruction, paid, disputed, refunded, and cancelled
  states hard to distinguish in payment and ledger UI.
- `BiopayQrScreen` normalized phone/merchant-code input before error handling
  and generated QR data inside the modal builder, so invalid recipients or
  route templates could throw outside the intended user-facing error path.
- `TransactionAllocationSheet` swallowed group-member load failures and showed
  the same empty state as a truly empty member list.

P1/P2 remaining:

- Android build verification failed locally because the Gradle daemon
  disappeared during `assembleDebug`; this must be rerun on CI or a stable
  local daemon before release.
- iOS store-grade build/signing remains outside the verified path in this pass.
- Venue/table/order, mobility trip, football prediction/pool, and AI handoff
  flows are not present in the current Flutter route inventory; they need a
  separate product-scope decision before mobile verification can cover them.
- Several large admin/mobile files remain expensive to review and test
  surgically; continue additive section extraction rather than route rewrites.

## Changes Made

- Added explicit payment-state resolution for instruction, pending,
  manual-confirmed, paid, disputed, refunded, cancelled, failed/expired, and
  unknown statuses in `TransactionStatusChip`.
- Added localized status labels and a screen-reader status semantics label.
- Hardened BioPay QR generation so recipient normalization, amount parsing, and
  QR/USSD data generation fail through `CoolToast.error` instead of uncaught UI
  exceptions.
- Added an explicit member-load error state with retry to the transaction
  allocation sheet.
- Added widget coverage for the shared transaction status chip lifecycle labels
  and semantics contract.

## Verification

Passed:

- `cd apps/mobile && ../../scripts/dev/flutterw gen-l10n`
- `dart format lib/shared/widgets/transaction_status_chip.dart lib/features/biopay/screens/biopay_qr_screen.dart lib/features/groups/widgets/transaction_allocation_sheet.dart test/shared/widgets/transaction_status_chip_test.dart`
- `cd apps/mobile && ../../scripts/dev/flutterw analyze --fatal-infos`
- `cd apps/mobile && ../../scripts/dev/flutterw test test/shared/widgets/transaction_status_chip_test.dart`
- `cd apps/mobile && ../../scripts/dev/flutterw test --concurrency=1 test/shared/widgets/transaction_status_chip_test.dart test/features/momo/models/momo_qr_payload_test.dart test/features/biopay/biopay_dialer_service_test.dart test/features/biopay/biopay_register_screen_test.dart test/features/groups/group_detail_screen_test.dart test/features/groups/group_journeys_test.dart test/core/router/app_redirects_test.dart test/providers/auth_notifier_test.dart`

Failed:

- `cd apps/mobile && ../../scripts/dev/flutterw build apk --debug --dart-define-from-file=flavors/staging.json`
  - Result: Gradle daemon disappeared unexpectedly after `721.8s`.
  - No new APK artifact was produced by this run.

## Next Phase

- Stabilize Android build verification under CI or with `--no-daemon --stacktrace`
  on a clean local runner.
- Add widget coverage for BioPay QR invalid recipient and invalid amount paths.
- Split remaining large admin/group screens by stable sections.
- Add product-level route decisions for the critical flows absent from mobile.
