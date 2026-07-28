# Dependency, Licence, Vulnerability, and Store-Policy Assessment

## Assessment boundary

- Evidence date: 2026-07-25
- Repository: `/Volumes/PRO-G40/COOL`
- Flutter/Dart: Flutter 3.44.4, Dart 3.12.2
- Package evidence: resolved `pubspec.lock`, `flutter pub deps --json`,
  `flutter pub outdated --json`, package licence files, Flutter analysis/tests,
  Android merged-manifest inspection, Android integration build, and iOS
  generic-device Release archive
- Policy evidence: current official Apple Developer and Google Play policy
  pages linked below

This is a local engineering and policy-readiness assessment. It is not legal
advice, store approval, a production release decision, or evidence that store
forms were submitted.

## Executive conclusion

The resolved Flutter dependency graph is locally acceptable for continued
engineering:

- all compatible package upgrades were applied;
- `file_saver` was intentionally advanced from 0.3.1 to 0.4.0 for Android
  path-traversal hardening, modern iOS/macOS packaging, and current platform
  compatibility;
- all 17 direct third-party runtime packages carry permissive licences;
- the current package resolver reports no package affected by a published
  advisory, discontinued, or retracted;
- formatting and static analysis pass;
- the complete post-update automated suite passes 412 tests at 77.83% line
  coverage;
- Android dev compilation and the final unsigned iOS Release archive pass
  against the final assessed lockfile.

This does not close store readiness. Final production artifacts, store
declarations, privacy answers, financial-feature classification, permission
dialog UAT, signing, and accountable approval remain separate gates.

## Resolved direct runtime dependencies

| Package | Resolved | Licence disposition |
|---|---:|---|
| `country_picker` | 2.0.28 | MIT |
| `crypto` | 3.0.7 | BSD-3-Clause |
| `file_saver` | 0.4.0 | BSD-3-Clause |
| `flutter_local_notifications` | 22.1.0 | BSD-3-Clause |
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
| `supabase_flutter` | 2.16.0 | MIT |
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

`file_saver` is no longer deferred: 0.4.0 retains the Collect call shape and
was adopted because its security and platform fixes outweigh the controlled
major-version change.

The vulnerability result is bounded to advisories exposed by the current Dart
package resolver. A zero count is not proof that every transitive native
component is vulnerability-free; the scan must be rerun on the final lockfile
at release time.

## Built-in Kotlin compatibility

The local compatibility gate reports six resolved Android plugins that still
apply the legacy Kotlin Gradle Plugin:

1. `file_saver`
2. `image_picker_android`
3. `mobile_scanner`
4. `share_plus`
5. `shared_preferences_android`
6. `url_launcher_android`

The current Flutter build emits the warning for directly detected build-path
plugins and still compiles. This is an upstream forward-compatibility risk, not
a present compile failure. Blindly removing Gradle declarations from cached
packages is not an acceptable fix. Closure requires upstream built-in-Kotlin
releases or reviewed, controlled vendor forks, followed by the compatibility
gate and Android build matrix.

Flutter's official migration guidance:
<https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers>

## Android permission and Google Play assessment

The upgraded dev APK is `app.cool.mobile.dev`, targets SDK 36, and declares:

- `ACCESS_NETWORK_STATE`
- `CAMERA`
- `INTERNET`
- `POST_NOTIFICATIONS`
- `VIBRATE`
- the application-scoped dynamic-receiver protection permission

It does not declare `READ_SMS`, `RECEIVE_SMS`, `SEND_SMS`, Call Log, broad
photo/video, or storage permissions. `file_saver` 0.4.0 initially introduced
legacy external-storage declarations during manifest merging; Collect now
removes both explicitly because QR export uses app-specific storage. A
regression test and rebuilt APK permission inspection prove the removals. The
production source manifest also excludes restricted SMS permissions.

`READ_SMS` and `RECEIVE_SMS` are isolated to the separately suffixed
`internal_receiver` flavor. That flavor is controlled UAT infrastructure and
must never be uploaded to a public Google Play track. Google restricts SMS and
Call Log permissions and requires an approved core use and declaration when
they are present:
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
- complete Camera and Notification allow/deny/recovery UAT;
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
| Production restricted SMS permissions absent | Source/test evidence passes | Inspect final signed production APK/AAB |
| Broad photo/video permission absent | Upgraded dev APK passes | Inspect final production artifact |
| Camera/notification purpose and recovery | Source/widget coverage partial | Native allow/deny/retry screenshots and logs |
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
