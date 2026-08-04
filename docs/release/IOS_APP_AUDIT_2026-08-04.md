# iOS app audit and release assessment

Status date: 2026-08-04  
Scope: Collect member iPhone/iPad app, current uncommitted source  
Decision: **NOT READY FOR APP STORE RELEASE**

## Current result

The Flutter/iOS source, store artwork, metadata, privacy declaration, and release
automation are materially improved and pass the new local package gate. A current
iOS binary, simulator run, signed archive, TestFlight build, physical-device UAT,
VoiceOver review, and App Store Connect state were not produced or verified.

The active Xcode path is a broken link to the disconnected `PRO-G40` volume. The
current simulator harness therefore fails before launch with no available
`simctl` runtime. The previous July unsigned archive and simulator route evidence
remain useful historical evidence, but they do not certify this changed source.

## Implemented in this pass

- Detail, utility, confirmation, and modal routes now use `CupertinoPage` on iOS.
  The widget contract verifies that a detail route exposes the native interactive
  back-swipe gesture. Primary-tab and entry transitions retain the existing
  product motion.
- Store screenshot generation now enables the actual iOS product boundary. The
  iPhone Home artwork shows `Groups`, not the Android-only `Create` action.
- All five iPhone and five iPad screenshots were regenerated from the current
  reviewed fixture routes. Their sizes are `1242x2688` and `2048x2732`, both
  accepted Apple screenshot sizes, and none contains an alpha channel.
- Removed the unnecessary alpha channel from all 15 iOS icons. RGB pixel hashes
  were compared before and after; visible pixels are unchanged.
- Fixed the Fastlane screenshot lane so a clean CI checkout uses the reviewed
  tracked screenshots instead of deleting them and failing on ignored local
  output.
- The iOS workflow now uses Ruby 3.3, the lockfile, Bundler, and pinned Fastlane
  `2.228.0` instead of installing an unbounded latest Fastlane release.
- App Privacy now includes the linked install-level `DEVICE_ID` used for
  notification registration and `PAYMENT_INFORMATION` used by contribution
  records. The matching app-level `PrivacyInfo.xcprivacy` is included in the
  Runner resources and declares eight linked, non-tracking data types used for
  app functionality.
- The production Fastlane lane now fails closed unless the production Supabase
  URL and anonymous key are supplied. It includes those values in the IPA while
  keeping deterministic reviewer credentials isolated to seeded local fixture
  data; ordinary customers still use the production repository.
- OTP entry exposes iOS one-time-code AutoFill. Share sheets now receive a valid
  source rectangle, avoiding the missing-popover-origin failure on iPad.
- The Runner explicitly supports mixed Flutter/iOS localizations, retains the
  `FlutterSceneDelegate` lifecycle migration, and the CI workflow now rejects an
  iOS SDK older than 26.0 before building.
- Corrected the App Store support URL from the privacy page to the public Collect
  site, which exposes the existing support channels.
- Added `scripts/ios_app_store_readiness_gate.sh` and wired it into the iOS
  workflow before any build or upload step.

## Screen and journey review

| Surface | Current source result | Current native proof |
| --- | --- | --- |
| Auth and OTP | Clean member flow; large-text and reduced-motion contracts retained | Open |
| Home | Platform-correct iOS actions; current store artwork reviewed | Store artwork only |
| Groups and search | Search works; compact cards and long-name handling retained | Store artwork only |
| Group detail, members, ledger | Clean hierarchy; native iOS back gesture enabled | Widget contract only |
| Contribute and MoMo return | Existing feedback and safe error handling retained | Open physical iPhone |
| QR and camera recovery | Usage string and guarded recovery flow present | Open current simulator/physical iPhone |
| Activity | Dense-list blur removed in the prior UX pass | Open current iOS profile trace |
| Profile and settings | Reduced copy, legal/privacy access, notification recovery retained | Open VoiceOver/physical iPhone |
| Offline and sync | Primary action remains above floating navigation | Open live transition test |
| iPad | Responsive rail layout and current accepted-size artwork present | Open native iPad runtime |

## 2026 native-platform assessment

| Native area | Implemented source state | Evidence boundary or next action |
| --- | --- | --- |
| Build baseline | iOS 15.5 minimum deployment; CI requires the iOS 26 SDK | Fresh Xcode 26 archive is open |
| App lifecycle | Flutter `UIScene`/`FlutterSceneDelegate` configuration is present | Background/foreground restoration needs a current native run |
| Navigation | `CupertinoPage` detail routes and interactive back-swipe contract | Confirm on iPhone and iPad with VoiceOver running |
| Input and keyboard | International phone input, OTP content type, one-time-code AutoFill, keyboard-safe forms | Verify AutoFill using a real WhatsApp code on device |
| iPad adaptation | Responsive rail, accepted 13-inch screenshots, anchored share popovers | Run split view, rotation, multitasking, pointer, and hardware-keyboard UAT |
| Accessibility | 44-point target contracts, large text, high contrast, reduced motion, semantics tests | Complete every common task with VoiceOver and approve App Store accessibility labels |
| Privacy | App privacy answers and Runner privacy manifest cover current declared data; tracking is false | Inspect the built archive's aggregated first- and third-party manifests |
| Permissions | Camera/photo purpose strings are scoped; Contacts, NFC, add-only Photos, and remote-push entitlements are absent | Verify deny/retry/Settings recovery on a physical iPhone |
| Universal Links | Associated Domains entitlement and live `.well-known` AASA file agree on team ID and app ID | Replace the wildcard provisioning profile and validate installed-app routing |
| Sharing | Native share sheet with iPad source rectangle | Confirm installed-app share targets and cancellation paths |
| Notifications | Local notification runtime is implemented and does not claim APNs | Decide separately whether remote push is a product requirement |
| Camera and QR | Native camera flow and permission recovery exist | Current simulator and physical-device proof is open |
| Performance | Dense-list visual blur was removed; profile harness exists | Capture launch, animation, memory, thermal, and scrolling traces on current source |
| App icon and materials | Opaque complete icon set; Flutter surfaces retain legible product hierarchy | Dark/clear/tinted iOS 26 icon variants need approved layered brand assets; do not synthesize them |
| Store review | Reviewer access is deterministic, seeded, and separated from live customer authentication | Human review notes, credentials, legal entity, age rating, trader status, and final submission remain open |

## Evidence completed

- `flutter analyze --no-pub`: pass after iOS changes.
- Full Flutter suite: 449 tests pass. Fresh line coverage is 78.81%
  (`9719/12332`); `coverage/lcov.info` SHA-256 is
  `d626c6b89a9cf69be0a3494b0078babffe00b58b299782a02bb81e3e66d5770a`.
- `scripts/ios_app_store_readiness_gate.sh`: pass; 10 screenshots, 15 icons,
  four plists, eight metadata fields, eight privacy-manifest data types, and App
  Privacy JSON validated.
- `ruby -c fastlane/Fastfile`, shell syntax, Runner/Xcode project property-list
  parsing, and App Store export-options parsing: pass.
- Live `https://collect.ikanisa.com/.well-known/apple-app-site-association`,
  `/privacy/`, and `/account-deletion/`: HTTP 200 on 2026-08-04. The AASA file
  identifies `63STJ5N27W.app.cool.mobile` and the app's supported link paths.
- Fastlane generated-output path: pass.
- Fastlane clean-checkout fallback path: pass with ignored screenshot output
  temporarily absent.
- Current screenshot manifest:
  `output/app_store/ios_screenshots/manifest.json`, SHA-256
  `b12be1daebd1527b222945b4d052a5ecbc21aa27c4324907e6a7794610c2f131`.
- Current native attempt:
  `.cache/ios_simulator_route_uat/20260804-ios-focus-current/summary.json`,
  SHA-256
  `e15aaa2b9c5ecbd4bb038c1737a6f7c2913860d6c5c17a90b3cf5744dcc537aa`.
  Result: fail before runner start because full Xcode/simulator tooling is
  unavailable.

## Open release gates

1. Reconnect or install full Xcode, select it with `xcode-select`, and rerun the
   current iPhone/iPad simulator route, camera, lifecycle, accessibility, and
   profile-performance harnesses.
2. Run current physical-iPhone journeys: install, launch, background/resume,
   camera deny/retry/Settings recovery, network loss/restoration, large text,
   reduced motion, VoiceOver, and back-swipe navigation.
3. Obtain an Associated Domains-capable provisioning profile for
   `app.cool.mobile`; the prior wildcard profile is incompatible with
   `com.apple.developer.associated-domains`.
4. Produce a new signed Release archive and exported IPA from the exact approved
   revision, validate entitlements/privacy manifests/symbols, and distribute only
   after recorded owner approval.
5. Verify App Store Connect directly: app/version state, age rating, agreements,
   DSA/trader information where applicable, privacy answers, build processing,
   review credentials, screenshots, and TestFlight smoke results.
6. Confirm the legal/product classification of Collect's contribution and money
   management features, the submitting legal entity, and any licensing or
   regulated-service requirements before review submission.
7. Complete the common-task VoiceOver audit before publishing Apple's
   accessibility labels. Approve any optional iOS 26 dark, clear, or tinted icon
   variants from real brand source artwork.
8. Record human product, privacy, security, UAT, and release-owner approval. No
   upload or submission was attempted in this pass.

## Current Apple gates used

- Apple accepts the generated screenshot dimensions and prohibits screenshot
  alpha channels:
  <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>
- Since 2026-04-28, iOS uploads must be built with Xcode 26 and the iOS 26 SDK:
  <https://developer.apple.com/news/upcoming-requirements/>
- App Privacy must include actual first- and third-party collection practices:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy>
- Privacy manifests describe collected data and required-reason API use in the
  app bundle: <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>
- Apple requires accurate review access, truthful metadata, privacy handling,
  and appropriate legal entities for highly regulated services:
  <https://developer.apple.com/app-store/review/guidelines/>
- Accessibility labels must be based on testing all common tasks:
  <https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/>
- iOS 26 materials and icon treatments should preserve hierarchy and legibility:
  <https://developer.apple.com/design/human-interface-guidelines/materials>
  and <https://developer.apple.com/design/human-interface-guidelines/app-icons>
