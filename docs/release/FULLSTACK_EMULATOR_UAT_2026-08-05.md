# Full-stack emulator UAT — 2026-08-05

## Decision

**Application and emulator UAT: PASS WITH FOLLOW-UP. Production go-live: NO-GO.**

The current Collect mobile source, representative Admin PWA routes, local API/function contracts, Android production artifacts, native permissions, network recovery, and accessibility states were exercised successfully. The live end-to-end notification path and protected reviewer/admin authentication paths are not deployable yet because required remote migration/configuration is absent. Provider-authorized MoMo traffic, physical-device accessibility, store submission, and accountable release approval are outside what emulator evidence can prove.

## Test target

- Device: `emulator-5554` / `sdk_gphone64_arm64`
- Platform: Android 16, API 36
- Display: 1080 × 2340, density 440
- Flutter/Dart: Flutter 3.44.4, Dart 3.12.2
- Mobile flavor/package: `production` / `app.cool.mobile`
- Data handling: synthetic fixtures and masked values only; no production customer data, raw SMS content, OTPs, signing material, or secret values retained

## Acceptance results

| Area | Result | Evidence |
|---|---:|---|
| Static analysis | PASS | `.cache/fullstack_emulator_uat/20260805-final/flutter_analyze_final.log` — no issues |
| Complete Flutter tests | PASS | `.cache/fullstack_emulator_uat/20260805-final/flutter_test_post_visual_fix.log` — 457/457 |
| Mobile route/prototype matrix | PASS | `.cache/android_device_uat/20260805-route-matrix-current-final3/summary.json` — 36/36 routes and screenshots |
| Accessibility/material states | PASS | `.cache/android_device_uat/20260805-material-states-current-final3/summary.json` — 17/17 states and screenshots at 200% text, high contrast, reduced motion |
| Camera permission journey | PASS | `.cache/android_camera_permission_dialog_uat/20260805-fullstack-final3/summary.json` — deny, education, retry, grant, scanner recovery; four screenshots |
| Notification permission journey | PASS | `.cache/android_permission_dialog_uat/20260805-fullstack-final3/summary.json` — deny, retry, settings recovery |
| Offline/network recovery | PASS | `.cache/android_network_restoration_uat/20260805-fullstack-final/summary.json` — radio loss, stale-cache UI, restored authoritative resync; three screenshots |
| Performance scenarios | PASS WITH FOLLOW-UP | `.cache/android_device_uat/20260805-performance-current-final/summary.json` and log — 6 scenarios, 512 frames |
| Edge Function auth contract | PASS | `.cache/fullstack_emulator_uat/20260805-final/collect_edge_auth_contract_uat.log` |
| Notification source readiness | PASS | `.cache/fullstack_emulator_uat/20260805-final/notification_readiness_gate.log` |
| Local migration validation | PASS | `.cache/fullstack_emulator_uat/20260805-final/validate_supabase_migrations.log` |
| Linked Supabase readiness | FAIL CLOSED | `.cache/fullstack_emulator_uat/20260805-final/supabase_production_readiness.log` — project healthy and advisor errors clean, but local 61 / remote 60 migrations |
| Authenticated Admin PWA render matrix | PASS | `.cache/admin_pwa_authenticated_render_smoke/20260805-fullstack-uat/summary.json` — 23 routes × 3 viewports = 69 screenshots, plus six critical visual captures |
| Fresh Admin PWA release build | BLOCKED BY CONFIG | `.cache/fullstack_emulator_uat/20260805-final/admin_pwa_release_build.log` — `COLLECT_ADMIN_WHATSAPP_PHONE` absent |
| Protected reviewer login | BLOCKED BY CONFIG | `.cache/android_device_uat/20260805-review-auth/summary.json` — protected reviewer phone/OTP build defines absent; no credentials fabricated |
| Android release APK/AAB | PASS | `.cache/fullstack_emulator_uat/20260805-final/mobile_release_gate_post_visual_fix.json` — fresh and signature-verified |

## Current artifact identity

- APK: `build/app/outputs/flutter-apk/app-production-release.apk`, 77,138,509 bytes, SHA-256 `87ce22be23d42d3c0ac7be101abb6a5fc9fad45f476b9c2223a19fa63ccc0d7a`
- AAB: `build/app/outputs/bundle/productionRelease/app-production-release.aab`, 68,338,415 bytes, SHA-256 `e08d85dd7e4a2f836318dc93771e4305d1abf203ec5e26dbed661237a17b2383`
- Mobile release gate: PASS; no blocker or failure keys; APK v2 and AAB JAR signatures verified

## Defects found and corrected during UAT

1. Android network restoration harness had no local TCP listener, so its connectivity assertion could not be authoritative. A bounded local probe server and exact radio restoration checks were added.
2. Camera permission UAT incorrectly attempted an iOS-only screenshot API on Android. Platform guarding and package/focus verification were added.
3. Notification/camera harnesses could be contaminated by another app flavor or package replacement. They now force-stop conflicting packages and verify the tested package, native permission state, and foreground system UI.
4. The device UAT wrapper did not fail closed on material-state screenshot totals. It now records and enforces `state_expected`, `state_passes`, and exact screenshot counts, including filtered runs.
5. The 200% text audit found the formatted contribution value horizontally clipped. The display-sized numeric line is now bounded while its explicit text-field semantics, label, and explanatory content retain accessibility scaling. Final capture shows the complete `RWF 12,345` value.
6. QR/camera controls, authentication actions, destructive-account dialogs, financial review surfaces, and state feedback were normalized for large text, reduced motion, contrast, semantics, and current Collect design tokens.
7. Android notification/SMS lifecycle contracts were hardened with receive-only permission scope, encrypted queued SMS read/ack handling, FCM registration/delivery support, and explicit subscription disposal.

## Visual review

The 36-route matrix covers authentication, home, groups, QR scan, invitation/share links, contribution entry/review, activity, profile/settings, notification/security/account/privacy/help/legal routes, compatibility redirects for invalid/expired share URLs, and the new app-permissions screen. The 17-state stress matrix covers empty/valid/invalid auth, OTP, group/activity empty states, contribution entry/review, account deletion, offline/sync recovery, and missing-group handling.

The final large-text amount capture is clean and fully readable. The OTP recovery page remains vertically scrollable at 200% text while keeping primary/change/resend actions available. No legacy blue/purple Collect chrome, legacy phone-entry split field, legacy OTP boxes, or legacy QR gradient card was observed in the recertified route/state screenshots.

## Performance observations

- Dense groups scroll: 0 over-budget frames; build p90 2.51 ms.
- Dense activity scroll: 0 over-budget frames; build p90 2.56 ms.
- Startup, route transition, and modal open/close had isolated warm-up/transition outliers in debug instrumentation.
- Amount entry plus IME remains the hotspot: build p90 33.26 ms and 8 of 46 UI frames over 16.67 ms. This is debug/emulator evidence, not release-mode physical-device proof. Profile this path in release/profile mode on representative low/mid-range Android hardware before go-live.

## Backend and configuration gaps

1. **Remote migration drift:** local migration `20260805120000_android_fcm_push_delivery.sql` is not applied to the linked Supabase project (`61 local / 60 remote`). The readiness run stopped fail-closed before claiming full schema/function readiness.
2. **Push secrets:** none of the five expected notification secret names are present remotely: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY_BASE64`, `FCM_SERVICE_ACCOUNT_JSON`. Only secret-name presence was inspected; no values were read or retained.
3. **Admin build identity:** `COLLECT_ADMIN_WHATSAPP_PHONE` is absent, so a fresh production Admin PWA artifact was not built. Existing authenticated evidence-mode routes pass but are not a new deployable production artifact.
4. **Reviewer auth:** protected `APP_REVIEW_AUTH_PHONE` and OTP defines were not supplied, so the real reviewer login path correctly failed closed. Synthetic authentication state tests pass.
5. **Build compatibility:** `mobile_scanner` still applies the legacy Kotlin Gradle Plugin path and must be upgraded/migrated before a Flutter version that requires Built-in Kotlin. Release builds also warn that the Cupertino icon font is referenced but not bundled.

## Gates emulator UAT cannot close

- Provider-authorized real MTN/Airtel MoMo SMS ingestion, parser, allocation, reconciliation, and duplicate/retry behavior
- Google Play restricted-SMS declaration acceptance and authenticated Play Console submission
- Real APNs/FCM delivery after secrets and migration deployment
- Physical Android/iPhone reliability, camera behavior, TalkBack/VoiceOver, keyboard, screen-reader order, haptics, poor-network behavior, battery/background lifecycle, and device-specific performance
- Flutter 3.47 compatibility validation
- App Store/Play Store authenticated inspection, screenshots, metadata, submission, review, and release
- Named release-owner/product/security/operations approval

## Required next execution order

1. Review and apply the pending FCM migration through the controlled Supabase production-change path.
2. Configure APNs/FCM secret values without exposing them, deploy `dispatch-notifications`, and run sanitized real push-delivery UAT.
3. Supply protected reviewer/admin build configuration through the approved secret/config channel; rebuild and rerun those two paths.
4. Optimize/profile amount entry with the IME in profile/release mode on representative hardware.
5. Execute provider-authorized MoMo/SMS UAT and physical TalkBack/VoiceOver/device UAT.
6. Resolve the Kotlin/plugin and Cupertino-font warnings, validate on the mandated Flutter 3.47 toolchain, then rebuild artifacts.
7. Complete authenticated store inspection/submission and accountable approvals.
