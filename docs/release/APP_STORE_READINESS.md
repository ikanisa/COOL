# App Store Readiness

Status date: 2026-08-04

Current active iOS/App Store readiness should be read from the latest build,
signing, screenshot, App Privacy, and App Store Connect checks. Dated readiness
reports were removed from active source after consolidation.

Current assessment: `docs/release/IOS_APP_AUDIT_2026-08-04.md`.

Known current boundaries:

- The source and App Store package gate pass locally, including platform-correct
  screenshots, opaque icons, metadata, plists, and privacy JSON.
- Current native build/runtime evidence is blocked because the active Xcode path
  points to a disconnected external volume and no iOS Simulator is available.
- App Store submission still requires current Apple credentials, signing,
  screenshots, App Privacy details, uploaded build evidence, and recorded human
  approval.
- Do not submit or alter App Store records without explicit recorded owner
  approval.

Current SDK source of truth: `docs/ENVIRONMENT.md`.
