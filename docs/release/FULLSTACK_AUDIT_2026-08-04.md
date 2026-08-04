# Collect full-stack completion and go-live audit

Audit date: 2026-08-04  
Repository: `ikanisa/COOL`  
Audited revision: `dc87acf1af987de52aa6027d6c364d6e686a651f` plus the code-owned fixes listed below  
Current app version: `1.2.2+10`

## Decision

**NO-GO for a new production release.** The repository has strong automated
coverage and the public website is healthy, but the release is not complete.
Production Android signing material and current artifacts are absent, the
deployed Admin PWA is behind the source tree, linked Supabase verification is
not available in this environment, the ten-persona UAT manifest has no signed
evidence, and release approvals refer to `1.2.2+9` rather than `1.2.2+10`.

No deployment, store submission, production database mutation, or human
approval was inferred or performed during this audit.

## Current evidence

| Area | Status | Current evidence |
| --- | --- | --- |
| Flutter source quality | Pass | Pinned Flutter `3.44.4` / Dart `3.12.2`; formatting clean; `flutter analyze --no-pub` has no findings. |
| Automated tests | Pass | `443/443` Flutter tests pass with `78.75%` line coverage (`9,675/12,286`). |
| Mobile rendered routes | Pass | `35/35` routes render nonblank at `390x844`; evidence is in `.cache/mobile_route_render_smoke/20260804-audit`. |
| Visual regression | Pass | Fourteen approved surfaces pass. The comparator permits only `0.05%` pixel drift for host-specific subpixel rasterization; geometry, viewport, and baseline membership remain exact. |
| Accessibility and adaptive UI | Pass in automation | Contrast, 44/48 dp targets, reduced motion, high contrast, large text, compact phone, tablet, and route semantics are covered. Physical TalkBack/VoiceOver approval is not current. |
| Public website | Pass live; external completion evidence open | Static gate `55/55`, live gate `34/34`, four browser viewports pass. Lighthouse mobile: performance `0.96`, accessibility `0.96`, best practices `1.00`, SEO `1.00`; desktop: `1.00`, `0.96`, `1.00`, `1.00`. |
| Admin PWA source build | Pass | Current local manifest and hosting gates pass; current live-config render smoke passes at `.cache/admin_pwa_render_smoke/current-live-config`. |
| Admin PWA deployment | Fail | `https://admin.collect.ikanisa.com` is missing the official 512 px icon, uses stale favicon/manifest references, and its Flutter bootstrap does not register the current custom service worker. This is deployment drift; the source build already contains the required assets. |
| Supabase migrations | Pass locally | Migration validator passes; all ten Edge Function entrypoints type-check; the Edge auth contract passes. |
| Supabase production state | Blocked | No `SUPABASE_ACCESS_TOKEN` or linked-project session is available and the local Docker runtime is not running. Linked migration parity, advisors, RLS positive/negative paths, WhatsApp OTP, SMS allocation, and rollback UAT are therefore not current. |
| Stripe webhook | Fixed and tested | Webhook verification now enforces a five-minute signed timestamp window, accepts overlapping `v1` signatures during secret rotation, and uses constant-time comparison. Four Deno tests and the Flutter Supabase contract suite pass. |
| Tracked secret hygiene | Pass | The tracked-file fallback secret scan passes. `gitleaks` is not installed, so this is not equivalent to a full history scan. |
| Android build tooling | Source fix complete | The canonical Gradle wrapper was missing from Git and is now restored. Android SDK 36, build tools, licenses, NDK, Gradle 8.14, and Java 17 resolve. |
| Android signing/artifacts | Blocked | The redacted Gradle preflight confirms no production keystore, alias, or passwords are configured. Current `1.2.2+10` signed APK/AAB artifacts are missing or stale. The code correctly refuses a production build rather than using a debug key. |
| Android future compatibility | Warning | `mobile_scanner` and `share_plus` still apply conditional Kotlin Gradle Plugin paths under the current AGP graph. The repository gate says all plugins have a future built-in-Kotlin path, but enabling it requires the later Flutter toolchain identified by that gate. |
| iOS | Out of current Android release scope | The recorded scope is Android-only. Full Xcode is not installed on this audit host, so no current iOS archive or device evidence exists. |
| UAT evidence | Blocked | `UAT-01` through `UAT-10` are all pending, with no evidence files, persona signoffs, owner name, owner timestamp, or GO decision. |
| Release approvals | Blocked | Product and prior Android SMS approvals exist, but Android signing and release-owner approvals are for `1.2.2+9`; current version is `1.2.2+10`. |
| Aggregate release gate | Blocked | `scripts/release_status.sh --json` returns `NO-GO` for Android artifacts, signing review, Admin PWA live gate, linked SMS-first Supabase UAT, and release-owner signoff. |

## Code-owned fixes implemented

1. Restored and tracked `android/gradlew`, `android/gradlew.bat`, and the
   canonical `gradle-wrapper.jar`; removed the ignore rules that made fresh
   clones non-buildable.
2. Pinned the Supabase Edge client import to `@supabase/supabase-js@2.112.0`
   instead of a floating major version and added a contract test against
   dependency drift.
3. Hardened Stripe webhook verification against replay and signing-secret
   rotation failure, with dependency-free Deno tests.
4. Updated compatible packages within the existing dependency constraints and
   regenerated `pubspec.lock`; deliberately did not force Riverpod, router, or
   permission-handler major migrations into a release audit.
5. Made golden comparisons tolerant only of bounded subpixel drift and removed
   48 generated failure images from version control; future failures are
   ignored and regenerated locally.
6. Formatted the vendored Dart source and the previously unformatted Play
   Integrity Edge Function so repository-wide format checks are clean.
7. Repaired the audit host's stale Flutter/Android paths and upgraded the local
   Supabase CLI to `2.111.0`. These host changes are not repository artifacts.

## Remaining release blockers

| Priority | Blocker | Completion condition |
| --- | --- | --- |
| P0 | Production Android signing and artifacts | The release owner supplies the registered upload keystore through ignored `android/key.properties` or `COOL_ANDROID_*` environment variables; rebuild APK/AAB `1.2.2+10`, verify signatures and checksums, then record fresh signing approval. |
| P0 | Admin PWA deployment drift | An authorized operator deploys the already-passing local Admin PWA build, then reruns the live gate against `https://admin.collect.ikanisa.com`. |
| P0 | Linked Supabase state unknown | An authorized linked session runs production readiness, migration parity, advisors, Edge negative/positive probes, WhatsApp OTP, and SMS-first allocation/rollback UAT without exposing credentials or customer data. |
| P0 | Physical UAT absent | Run and sanitize evidence for all ten personas, including real Android SMS consent, background/killed/offline recovery, parse/allocation/exception/ledger behavior, accessibility, and the supported devices. |
| P0 | Current release approval absent | After the current artifacts and evidence packet exist, record `1.2.2+10` signing and release-owner approvals and rerun the aggregate gate. |
| P1 | Public-site external proof | Attach Google Search Console evidence, Bing Webmaster evidence or an explicit owner deferral, and Play Console privacy-URL evidence or an explicit owner deferral. |
| P2 | Major dependency migration | Plan Riverpod 3, go_router 17, permission_handler 13, and built-in Kotlin compatibility as a separately tested change set rather than mixing them into release closeout. |

## Release-owner sequence

1. Provide linked Supabase authorization and the Android upload key through the
   documented secret-safe mechanisms.
2. Run the linked backend and physical-device UAT packs; attach only sanitized
   evidence and complete all ten persona signoffs.
3. Build and verify the signed `1.2.2+10` Android artifacts.
4. Deploy the current Admin PWA build and rerun its live gate.
5. Record current-version approvals, rerun `scripts/release_status.sh --json`,
   and proceed only if it returns `GO` with no blockers.

The public site can remain online while these application-release blockers are
closed. This report is a readiness assessment, not approval to deploy or submit.
