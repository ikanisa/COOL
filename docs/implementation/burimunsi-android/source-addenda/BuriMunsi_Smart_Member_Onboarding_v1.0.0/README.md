# BuriMunsi Smart Member Onboarding v1.0.0

A separate source-code extension for the native Android Staff app and the existing Collect backend, with MoMo payer suggestions, name/last-three-digit search, verified manual enrollment, OCR-assisted import and a reviewed bulk-registration queue.

Start with `docs/INTEGRATION.md`. Backend code: `backend/src/`. Native Compose screen: `android/src/main/java/com/ikanisa/burimunsi/onboarding/SmartOnboardingScreen.kt`. Local tests: `backend/test/`.

**Source candidate only** — local Node tests pass; not yet merged into app source, compiled against Android, connected to the real Collect database, or used with real member data. Production acceptance remains required.
