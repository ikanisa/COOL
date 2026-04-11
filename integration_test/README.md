# Integration Tests

This directory contains full device-backed integration tests.

## Running

The current project does not ship a supported desktop or web target, so
Flutter's `integration_test` runner still needs an attached mobile device or
emulator.

To keep CI and local release gates green, the host-only smoke suite lives under
`test/integration_smoke/` and runs with plain `flutter test` without an
emulator or live backend services:

```bash
# Run the device-backed critical journey suite on the default attached device
bash scripts/run_device_integration.sh

# Pick a device and production flavor explicitly
DEVICE=emulator-5554 FLAVOR=production bash scripts/run_device_integration.sh

# Run the Android inbox-sync device test with seeded SMS rows
DEVICE=emulator-5554 FLAVOR=staging bash scripts/run_momo_sms_device_integration.sh

# Run all host-side smoke tests
flutter test test/integration_smoke
```

## Device-Backed Integration Suite

| File | Journey |
|---|---|
| `critical_journeys_test.dart` | Signed-out deep links, group routes, and MoMo entry flows |
| `momo_sms_inbox_sync_test.dart` | Real Android SMS inbox sync with seeded M-Money rows, sync-state persistence, and manual overlap replay |

These tests intentionally reuse the fake-backed harness from
`test/integration_smoke/` so they stay deterministic while still executing on a
real mobile runtime.

## Host-Side Smoke Suite

| File | Journey |
|---|---|
| `app_boot_test.dart` | Smoke: app boots without crashing |
| `deep_link_test.dart` | Redirect preservation for signed-out deep links |
| `momo_flow_test.dart` | Legacy MoMo route redirect and wallet-route reachability |

## Writing New Tests

1. Put real device-backed suites in `integration_test/`
2. Keep host-side smoke tests under `test/integration_smoke/`
3. Prefer provider overrides and fake repositories over live Supabase/Firebase
4. Keep tests independent so each file can run in CI without shared state
