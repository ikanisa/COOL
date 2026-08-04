# App Store Readiness

Status date: 2026-08-04

Current active iOS/App Store readiness should be read from the latest build,
signing, screenshot, App Privacy, and App Store Connect checks. Dated readiness
reports were removed from active source after consolidation.

Current assessment: `docs/release/IOS_APP_AUDIT_2026-08-04.md`.

Known current boundaries:

- The source and App Store package gate pass locally, including platform-correct
  screenshots, opaque icons, metadata, plists, and privacy JSON.
- Xcode 26.6 is available. Current native evidence passes 35/35 routes on an
  iPhone 17 iOS 26.5 Simulator, both controlled Camera permission phases pass,
  and a production-scheme unsigned `1.2.2 (10)` archive with dSYM was built.
- App Store submission still requires Associated Domains-capable distribution
  provisioning, a signed archive/export, current App Store Connect inspection,
  physical-iPhone/VoiceOver UAT, uploaded-build processing, and recorded human
  approval.
- Do not submit or alter App Store records without explicit recorded owner
  approval.

Current SDK source of truth: `docs/ENVIRONMENT.md`.
