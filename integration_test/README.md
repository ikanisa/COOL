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

# Run all host-side smoke tests
flutter test test/integration_smoke
```

## Device-Backed Integration Suite

| File | Journey |
|---|---|
| `critical_journeys_test.dart` | Signed-out deep links, OTP validation, MoMo send validation, mobility degraded mode, and Rayon tickets |

These tests intentionally reuse the fake-backed harness from
`test/integration_smoke/` so they stay deterministic while still executing on a
real mobile runtime.

## Host-Side Smoke Suite

| File | Journey |
|---|---|
| `app_boot_test.dart` | Smoke: app boots without crashing |
| `auth_flow_test.dart` | Onboarding and OTP validation |
| `deep_link_test.dart` | Redirect preservation for signed-out deep links |
| `momo_flow_test.dart` | MoMo screen and send validation |
| `trip_offline_test.dart` | Mobility screen stays usable without location |
| `ticket_flow_test.dart` | Rayon tickets hub and purchase sheet |

## Writing New Tests

1. Put real device-backed suites in `integration_test/`
2. Keep host-side smoke tests under `test/integration_smoke/`
3. Prefer provider overrides and fake repositories over live Supabase/Firebase
4. Keep tests independent so each file can run in CI without shared state
