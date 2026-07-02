# Collect Release Gate Evidence - 2026-06-07

## Result

Status: NO-GO for production release.

The code-owned brand, artifact, admin web, live Admin PWA, and physical Android device checks have been refreshed. Production remains blocked by release-owner execution records and platform-scope evidence that cannot be completed by code changes alone.

## Passed Evidence

- Physical Android UAT on Pixel 4a `13111JEC215558`: passed.
- Device UAT target: `integration_test/app_uat_smoke_test.dart`.
- Device UAT log: `.cache/android_device_uat/20260607Tpost-patch/android_device_uat.txt`.
- Device UAT result: 5 integration checks passed on the physical device.
- Admin PWA build, manifest gate, and hosting gate: passed.
- Admin PWA live gate: passed for `https://cool-admin-212.pages.dev`.
- Admin PWA live gate log: `.cache/release_gate/2026-06-08-admin-live-gate.json`.
- Release artifact checksum manifest: `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-06-07.sha256`.
- Android release APK: `build/app/outputs/flutter-apk/app-production-release.apk`.
- Android release APK SHA-256: `12b585bfa74f90c9136b5e30efe585e440523c5d7443d193c1f3afdd346db968`.
- Android release AAB: `build/app/outputs/bundle/productionRelease/app-production-release.aab`.
- Android release AAB SHA-256: `abe249bbd0ea72f5a8f7b3e9160142adeef09966aee7e7928c46e2f5c25222d3`.
- Physical-device route evidence: `.cache/android_device_uat/20260607Tpost-patch/android_device_uat.txt`.

## Test Fix

The main app physical-device UAT assertion now checks for the current launch-screen value `038491` instead of the removed `Good morning` copy. This keeps the UAT smoke test aligned with the current Collect visual surface without weakening the admin/secret-boundary assertions.

## Remaining Release Blockers

- Product signoff for the corrected SMS-first Groups product definition.
- Real Android MoMo SMS ingestion/parser/allocation UAT approval.
- Android release signing / Play App Signing review approval.
- iOS release scope signoff or explicit Android-only out-of-scope decision.
- Release-owner signoff for the current evidence packet.
- Human UAT persona signoffs.

## Current Decision

Keep the release decision at NO-GO until the approval metadata above is complete.
