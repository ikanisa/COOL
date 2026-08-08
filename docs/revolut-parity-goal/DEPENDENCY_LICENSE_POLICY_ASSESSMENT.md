# Dependency, Licence, Vulnerability, and Store-Policy Assessment

## Assessment boundary

- Evidence date: 2026-08-01
- Repository: `/Volumes/PRO-G40/COOL`
- Flutter/Dart: Flutter 3.44.4, Dart 3.12.2
- Package evidence: resolved `pubspec.lock`, `flutter pub deps --json`,
  `flutter pub outdated --json`, package licence files, Flutter analysis/tests,
  Android merged-manifest inspection, production APK/AAB rebuilds, Admin PWA
  rebuild, and the retained iOS generic-device Release archive
- Policy evidence: current official Apple Developer and Google Play policy
  pages linked below

This is a local engineering and policy-readiness assessment. It is not legal
advice, store approval, a production release decision, or evidence that store
forms were submitted.

## Executive conclusion

The resolved Flutter dependency graph is locally acceptable for continued
engineering:

- all compatible package upgrades were applied;
- `file_saver` was intentionally advanced from 0.3.1 to the controlled
  `0.4.0+collect.1` fork for Android
  path-traversal hardening, modern iOS/macOS packaging, and current platform
  compatibility;
- all 19 direct third-party runtime packages carry permissive licences;
- the current package resolver reports no package affected by a published
  advisory, discontinued, or retracted;
- formatting and static analysis pass;
- the complete post-update automated suite passes 438 tests at 78.79% line
  coverage;
- Android production APK/AAB compilation and the Admin PWA wrapper pass
  against the assessed lockfile; the retained unsigned iOS Release archive
  predates this Android-only fork and remains non-distributable evidence.

This does not close store readiness. Final production artifacts, store
declarations, privacy answers, financial-feature classification, permission
dialog UAT, signing, and accountable approval remain separate gates.

## Resolved direct runtime dependencies

| Package | Resolved | Licence disposition |
|---|---:|---|
| `app_links` | 7.2.1 | Apache-2.0 |
| `country_picker` | 2.0.28 | MIT |
| `crypto` | 3.0.7 | BSD-3-Clause |
| `cupertino_icons` | 1.0.9 | MIT |
| `file_saver` | 0.4.0+collect.1 controlled path fork | BSD-3-Clause; upstream licence and provenance retained |
| `flutter_local_notifications` | 22.3.0 | BSD-3-Clause |
| `flutter_riverpod` | 2.6.1 | MIT |
| `go_router` | 16.3.0 | BSD-3-Clause |
| `image_picker` | 1.2.3 | BSD-3-Clause plus bundled Apache-2.0 notice |
| `intl` | 0.20.2 | BSD-3-Clause |
| `logger` | 2.7.0 | MIT |
| `mobile_scanner` | 7.4.0 | BSD-3-Clause |
| `permission_handler` | 12.0.3 | MIT |
| `qr_flutter` | 4.1.0 | BSD-3-Clause |
| `share_plus` | 13.3.0 | BSD-3-Clause |
| `shared_preferences` | 2.5.5 | BSD-3-Clause |
| `supabase_flutter` | 2.17.1 | MIT |
| `url_launcher` | 6.3.2 | BSD-3-Clause |
| `uuid` | 4.6.0 | MIT |

No direct package has a missing licence file, copyleft obligation, or
commercial-use restriction in the reviewed package sources. Copyright and
licence notices must remain available through Flutter's generated licence
registry and any distribution notices required by bundled components.

The bundled Inter variable typeface remains separately governed by its OFL
notice at `assets/typefaces/OFL-Inter.txt`.

## Upgrade and vulnerability disposition

`flutter pub upgrade` refreshed 44 resolved packages before the explicit
`file_saver` 0.4.0 upgrade. The Supabase initialization call was migrated from
the deprecated `anonKey` parameter to `publishableKey` while retaining the
existing environment-field name for configuration compatibility.

Current unresolved direct-version differences:

| Package | Current | Newer | Disposition |
|---|---:|---:|---|
| `flutter_riverpod` | 2.6.1 | 3.3.2 | Major framework migration. No advisory or discontinuation requires an emergency jump. Defer to a dedicated provider/API migration with full state, navigation, and widget regression testing. |
| `go_router` | 16.3.0 | 17.3.0 | Major navigation migration. Defer until the complete 35-route and deep-link matrix can be rerun on native devices. |
| `intl` | 0.20.2 | 0.20.3 | Not currently resolvable within the Flutter SDK/localization graph; retain the SDK-compatible version. |

`file_saver` is no longer deferred: the controlled `0.4.0+collect.1` path fork
retains the Collect call shape, licence, and platform source while migrating
its Android Gradle configuration away from unconditional KGP application.
`third_party/file_saver/COLLECT_FORK.md` records the upstream hashes and the
three Collect-owned changes.

`app_links` is now a direct dependency rather than an incidental Supabase
transitive. Collect uses its Android/iOS stream explicitly so a shared-group
link is validated and durably retained before navigation; Flutter's competing
native router handoff is disabled on those platforms. Version 7.2.1 was
already resolved in the assessed graph and is Apache-2.0 licensed.

The vulnerability result is bounded to advisories exposed by the current Dart
package resolver. A zero count is not proof that every transitive native
component is vulnerability-free; the scan must be rerun on the final lockfile
at release time.

## Built-in Kotlin compatibility

The corrected compatibility gate distinguishes classpath declarations and
compiler DSL from actual Kotlin-plugin application. Against the current AGP 8
graph it reports two conditional fallbacks: `mobile_scanner` while built-in
Kotlin is disabled and `share_plus` while AGP is below 9. All 14 resolved
Android plugins are source-ready for the future built-in-Kotlin graph; there
are zero unconditional future blockers.

The controlled `file_saver` fork removes the prior unconditional
`kotlin-android` application and replaces `kotlinOptions` with
`kotlin.compilerOptions`. Current production APK/AAB builds pass and Flutter's
warning is reduced from `file_saver` plus `mobile_scanner` to
`mobile_scanner` only.

This is a source-migration closure, not platform enablement. Flutter 3.44.4 is
the governed repository toolchain, while Flutter's current guidance requires
Flutter 3.47 or later before `android.builtInKotlin=true` can be enabled and
validated. RT-037 therefore remains partially open for a controlled Flutter
upgrade, actual built-in-Kotlin build, and full Android regression matrix.

Flutter's official app and plugin migration guidance:
<https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers>
<https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors>

## Android permission and Google Play assessment

The upgraded dev APK is `app.cool.mobile.dev`, targets SDK 36, and declares:

- `ACCESS_NETWORK_STATE`
- `CAMERA`
- `INTERNET`
- `POST_NOTIFICATIONS`
- `VIBRATE`
- the application-scoped dynamic-receiver protection permission

It does not declare `READ_SMS`, `SEND_SMS`, Call Log, broad
photo/video, or storage permissions. Upstream `file_saver` 0.4.0 initially
introduced legacy external-storage declarations during manifest merging; Collect now
removes both explicitly because QR export uses app-specific storage. A
regression test and rebuilt APK permission inspection prove the removals. The
production source manifest declares receive-only `RECEIVE_SMS` for the
prominently disclosed SMS-based money-management feature.

`internal_receiver` remains controlled UAT infrastructure. Production also
contains `RECEIVE_SMS` but never `READ_SMS`; it must not be uploaded to a public
Google Play track until Google accepts the restricted SMS Permissions
Declaration. Google restricts SMS and Call Log permissions and requires an
approved core use and declaration when they are present:
<https://support.google.com/googleplay/android-developer/answer/10208820>

The absence of broad photo/video permissions aligns with Google's minimum-scope
picker policy:
<https://support.google.com/googleplay/android-developer/answer/16558241>

Remaining Google Play actions:

- inspect the final signed production APK/AAB, not only the dev artifact;
- complete and approve Data Safety answers against actual Supabase, notification,
  camera, profile-image, support, and payment/contribution data handling:
  <https://support.google.com/googleplay/android-developer/answer/10787469>;
- keep an in-app deletion path and public deletion-request URL operational:
  <https://support.google.com/googleplay/android-developer/answer/13327111>;
- complete the Financial features declaration. Every published app must answer
  it, and Product/Legal must classify Collect's group contributions and MoMo
  handoff accurately:
  <https://support.google.com/googleplay/android-developer/answer/13849271>;
- repeat the completed controlled-emulator Camera and Notification
  allow/deny/recovery sequences on an approved physical device and final
  production package;
- verify the final privacy policy identifies the developer, data categories,
  purposes, sharing, security, retention, deletion, and contact route;
- ensure the store title, icon, screenshots, description, and in-app surfaces
  cannot imply affiliation with Revolut. Google prohibits misleading
  impersonation:
  <https://support.google.com/googleplay/android-developer/answer/9888374>.

## Apple App Store assessment

Collect already exposes privacy and terms routes, an in-app auditable account
deletion request, and public account/data deletion resources. Their existence
supports the current Apple requirements, but backend execution, retention
rules, production URLs, and legal wording still require controlled validation
and approval.

Remaining App Store actions:

- approve and publish an accurate privacy policy identifying collection, use,
  third-party access, retention/deletion, consent, and revocation;
- complete App Privacy responses for data collected by Collect and every
  integrated SDK, and keep them current:
  <https://developer.apple.com/app-store/app-privacy-details/>;
- prove that in-app account deletion initiates deletion and that legally
  required retention is explained:
  <https://developer.apple.com/support/offering-account-deletion-in-your-app/>;
- provide App Review with a safe demo account or approved demo mode, accessible
  backend, sample QR/materials, and complete review notes;
- submit under the appropriate legal entity if Collect is classified as a
  regulated financial service in the target territories;
- provide a compatible Associated Domains provisioning profile and complete a
  signed distribution archive;
- keep Collect branding, iconography, metadata, and distinctive visual identity
  independent of Revolut. Apple Guideline 4.1 rejects copycats and misleading
  brand use; Revolut references are interaction-quality evidence, not a licence
  to reproduce protected brand assets:
  <https://developer.apple.com/app-store/review/guidelines/>.

## Store-policy checklist

| Control | Local status | Remaining proof |
|---|---|---|
| Privacy policy routes | Implemented locally | Legal approval, production URL, browser/device verification |
| In-app account deletion request | Implemented locally | Controlled-backend negative/positive path and retention evidence |
| Public deletion resource | Implemented locally | Production deployment and store-link verification |
| Production receive-only SMS scope | `RECEIVE_SMS` present; `READ_SMS` and `SEND_SMS` absent | Inspect final signed APK/AAB and obtain Google Play declaration acceptance before public distribution |
| Broad photo/video permission absent | Upgraded dev APK passes | Inspect final production artifact |
| Camera/notification purpose and recovery | E-054/E-056 controlled-emulator native allow/deny/retry/recovery evidence passes | Physical-device and final-production-package confirmation |
| Google Data Safety | Not submitted in this goal | Product/Privacy/Release approval and Play Console evidence |
| Google Financial features declaration | Not submitted in this goal | Product/Legal classification and Play Console evidence |
| Apple App Privacy | Not submitted in this goal | Product/Privacy/Release approval and App Store Connect evidence |
| Review account/backend/materials | Not prepared as final pack | Sanitized reviewer credentials and review notes |
| Non-impersonation/IP review | Collect branding is distinct in source | Final screenshot, metadata, icon, and legal review |
| Android upload/signing identity | External gate | Controlled certificate pin and owner approval |
| iOS distribution signing | External gate | Associated Domains-capable profile and signed archive |

## Closure decision

RT-030 is **completed locally for the current dependency graph and policy
assessment**. It must be refreshed if the graph or store rules change before
release. Store submission compliance remains open under RT-031, RT-032,
RT-035, RT-036, RT-042, RT-043, and RT-048.
