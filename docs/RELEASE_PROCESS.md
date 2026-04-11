# Release Process

> Last updated: March 2026

## Release Cadence

| Channel | Cadence | Audience | Purpose |
|---|---|---|---|
| Internal (Staff) | On-demand | Team members | Feature validation, QA |
| Beta | Weekly | Beta testers | Stability validation |
| Production | Bi-weekly | All users | Stable release |

## Release Flow

```
feature branch → main → tag v*.*.* → release-candidate gate → signed Android APK + AAB → Firebase App Distribution / Play upload
```

### Step-by-step

1. **Merge to `main`**: All PRs must pass CI (analyze, test, M-Money SMS contracts, size gate)
   - Route changes must also update `docs/ROUTE_INVENTORY.md`
   - New routes must satisfy `docs/SCREEN_BUDGETS.md`
   - If store or deep-link identifiers changed, update `deeplinks/release_metadata.json` and regenerate the hosted association files
2. **Tag a release**: `git tag v1.2.3 && git push origin v1.2.3`
3. **CI builds automatically**: `release.yml` triggers on `v*` tags
   - `momo-sms-rollout-verify.yml` can also run nightly and on demand to verify the Supabase M-Money SMS rollout when `SUPABASE_DB_URL` is configured
   - `momo-sms-device-integration.yml` runs nightly and on demand to verify the real Android SMS inbox sync path on an emulator
4. **CI pipeline**:
   - Reads Flutter version from `.fvmrc`
   - Syncs hosted Supabase Edge Function secrets when `SUPABASE_PROJECT_REF` and `SUPABASE_ACCESS_TOKEN` are configured
   - Decodes signing keystore from secrets before store-grade artifact builds
   - Runs `bash scripts/run_release_candidate.sh`
   - This enforces:
     - `RUN_ANDROID_MINIFY_CANARY=1`
     - `RUN_REMOTE_SMOKE=1`
     - `RUN_MOMO_SMS_ROLLOUT_VERIFY=1`
   - It also verifies:
     - deep-link release metadata against the configured signing metadata
     - Firebase App Check provider registration for the Android production app
     - hosted Supabase contract smoke against the production project
     - M-Money rollout verification against the target Supabase database
   - Builds signed release APK and signed release AAB
   - Uploads to Firebase App Distribution (staff group)
   - Archives APK and AAB as build artifacts
5. **Play Store**: upload the signed AAB artifact from CI to Play Console unless and until direct Play publishing is automated

## Release Candidate Command

Run this before approving any broad Android release:

```bash
RUN_ANDROID_MINIFY_CANARY=1 \
RUN_REMOTE_SMOKE=1 \
RUN_MOMO_SMS_ROLLOUT_VERIFY=1 \
bash scripts/run_release_candidate.sh
```

This command is intentionally stricter than `scripts/release_readiness.sh`. It
adds production-signing metadata validation, Firebase App Check provider
verification, hosted Supabase smoke, and store-grade Android artifact builds.

## Platform Scope

- Android tagged-release automation is in scope and must produce both a signed
  APK and a signed AAB.
- iOS store release automation is explicitly de-scoped in the current repo.
  The repo supports iOS validation builds, but it does not yet have a signed
  TestFlight / App Store lane. Do not treat iOS as broad-launch ready until
  that lane exists and is verified on macOS CI.

## Critical Build Blockers

> **⛔ MANDATORY — These environment variables MUST be set for every APK and AAB
> build. Builds without them will produce non-functional artifacts.**

| Variable | Purpose | Enforcement |
|---|---|---|
| `SUPABASE_PRODUCTION_URL` | Production Supabase project URL baked into the binary via `--dart-define` | Shell scripts abort with contract validation; Dart runtime validates the derived project ref |
| `SUPABASE_PRODUCTION_ANON_KEY` | Production Supabase anon key baked into the binary via `--dart-define` | Shell scripts abort with contract validation; Dart runtime validates startup config |
| `SUPABASE_STAGING_URL` | Optional staging Supabase project URL for QA/debug flavor builds | Required only when you intentionally maintain a separate staging backend |
| `SUPABASE_STAGING_ANON_KEY` | Optional staging Supabase anon key for QA/debug flavor builds | Required only when you intentionally maintain a separate staging backend |

**Why this is critical:**
- These values are compiled into the Flutter binary at build time via `--dart-define`.
- If missing or empty, the app cannot initialize Supabase and will either crash or
  display a full-screen configuration error (`ConfigErrorApp`).
- This applies to **all build targets**: APK, AAB, staging, production, QA, iOS.
- This applies to **all build methods**: local scripts, CI/CD, manual `flutter build`.

**How to provide them:**
1. Export the flavor-specific pair:
   `export SUPABASE_PRODUCTION_URL=https://... SUPABASE_PRODUCTION_ANON_KEY=...`
   for production, or the `SUPABASE_STAGING_*` pair for staging
2. `.env` file at repo root (auto-loaded by build scripts)
3. `.env.json` with `--dart-define-from-file=.env.json`
4. CI secrets (GitHub Actions `release.yml` prefers
   `secrets.SUPABASE_PRODUCTION_URL` and
   `secrets.SUPABASE_PRODUCTION_ANON_KEY`)
5. Legacy `SUPABASE_URL` / `SUPABASE_ANON_KEY` remain as a transitional fallback
   only and should mirror production until removed

Production-only release mode is supported. If `SUPABASE_STAGING_*` is omitted,
release validation skips staging and treats production as the only required
backend target.

If repo-local env files still contain `SUPABASE_STAGING_*`, force the same
production-only behavior with `COOL_SKIP_STAGING_BACKEND_VALIDATION=1`.


## Versioning

Format: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes, major feature launches
- **MINOR**: New features, significant improvements
- **PATCH**: Bug fixes, performance improvements

Version is set in `pubspec.yaml` → `version` field.

## Rollback Playbook

### Severity 1 (Crash loop, data loss)
1. **Immediate**: Activate kill-switch in Firebase Remote Config
2. **Within 1h**: Revert to last known-good tag, push hotfix
3. **Within 4h**: Ship hotfix via Firebase App Distribution

### Severity 2 (Feature broken, UX regression)
1. **Within 4h**: Evaluate kill-switch vs hotfix
2. **Within 24h**: Ship fix via normal release flow

### Severity 3 (Minor issue, cosmetic)
1. Include fix in next scheduled release

## Kill-Switch Emergency Procedure

If a shipped feature is causing issues:

1. Go to Firebase Console → Remote Config
2. Set the relevant kill-switch to `true`:
   - `kill_momo_payments` — disables MoMo payment flows
   - `kill_credit_features` — disables credit/loan features
3. Publish changes (takes effect within 4 hours or on next app restart)
4. Verify: force-close app → reopen → feature shows "temporarily unavailable"

## Rollout Governance

Remote Config no longer serves only kill-switches. Each governed surface can
carry:

- a kill-switch
- a rollout stage (`live`, `pilot`, `internal`, `disabled`)
- an optional admin-only restriction

Current governed Flutter surfaces:

- MoMo
- Credit

When introducing a new governed surface, update both:

- `lib/core/models/engagement_feature_flags.dart`
- `docs/ROUTE_INVENTORY.md` and `docs/SCREEN_BUDGETS.md` if user-facing

## Beta Ring Progression

```
Staff (internal) → Beta (1-2 weeks soak) → Production
```

- Staff build goes out immediately on tag
- Beta promotion: manual decision after 3+ days of staff testing with no P0/P1 bugs
- Production promotion: after 1 week of beta with crash-free rate > 99.5%

## Required Secrets (GitHub Actions)

| Secret | Purpose |
|---|---|
| `KEYSTORE_BASE64` | Base64-encoded signing keystore |
| `KEY_ALIAS` | Keystore alias |
| `KEY_PASSWORD` | Key password |
| `STORE_PASSWORD` | Store password |
| `SUPABASE_PRODUCTION_URL` | Preferred production Supabase project URL passed via `--dart-define` |
| `SUPABASE_PRODUCTION_ANON_KEY` | Preferred production Supabase anon key passed via `--dart-define` |
| `SUPABASE_STAGING_URL` | Optional staging Supabase project URL for QA/debug builds |
| `SUPABASE_STAGING_ANON_KEY` | Optional staging Supabase anon key for QA/debug builds |
| `SUPABASE_URL` | Deprecated fallback production Supabase URL |
| `SUPABASE_ANON_KEY` | Deprecated fallback production Supabase anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Edge Function secret sync and hosted smoke |
| `SUPABASE_ACCESS_TOKEN` | GitHub Actions access token used to sync hosted Supabase function secrets |
| `SUPABASE_PROJECT_REF` | Hosted Supabase project ref used for secret sync and remote smoke |
| `FIREBASE_ANDROID_PRODUCTION_API_KEY` | Optional Android production Firebase override; native config ships in `android/app/src/production/google-services.json` |
| `FIREBASE_ANDROID_PRODUCTION_APP_ID` | Optional Android production Firebase override |
| `FIREBASE_ANDROID_PRODUCTION_MESSAGING_SENDER_ID` | Optional Android production Firebase override |
| `FIREBASE_ANDROID_PRODUCTION_PROJECT_ID` | Optional Android production Firebase override |
| `FIREBASE_ANDROID_PRODUCTION_STORAGE_BUCKET` | Optional Android production Firebase override |
| `FIREBASE_APP_ID` | Firebase Android app ID |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase service account JSON reused for App Distribution and Supabase function sync when `FIREBASE_SERVICE_ACCOUNT_JSON` is unset |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Preferred explicit Supabase/App Check Firebase service account JSON |
| `COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT` | Final Google Play app-signing SHA-256 fingerprint |
| `COOL_IOS_TEAM_ID` | Apple Developer Team ID for the production bundle |
| `COOL_IOS_APP_STORE_ID` | Production App Store listing ID |
| `COOL_REQUIRE_IOS_RELEASE_METADATA` | Set to `1` when validating an iOS release so deep-link tooling requires iOS Team/App Store metadata |
| `COOL_IOS_RELEASE_ENABLED` | Keep `0` while iOS store release automation is de-scoped. Set to `1` only when a signed iOS release lane exists. |
| `SUPABASE_DB_URL` | Optional remote database connection used to enable M-Money SMS Supabase rollout verification during release readiness |

## Native Release Inputs

Production iOS validation is intentionally fail-fast now. Before cutting a release,
ensure the checked-in native Firebase configs are present:

- `ios/Runner/GoogleService-Info.plist`
- `ios/Runner/GoogleService-Info-staging.plist`
- `android/app/src/production/google-services.json`
- `android/app/src/staging/google-services.json`

The `FIREBASE_IOS_PRODUCTION_*` values remain optional override inputs; the
build now falls back to `ios/Runner/GoogleService-Info.plist` when they are
omitted.

- `FIREBASE_IOS_PRODUCTION_API_KEY`
- `FIREBASE_IOS_PRODUCTION_APP_ID`
- `FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID`
- `FIREBASE_IOS_PRODUCTION_PROJECT_ID`
- `FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET`
- `FIREBASE_IOS_PRODUCTION_BUNDLE_ID`
- `COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT`
- `COOL_IOS_TEAM_ID`
- `COOL_IOS_APP_STORE_ID`
- `COOL_REQUIRE_IOS_RELEASE_METADATA`

Client `GOOGLE_MAPS_ANDROID_API_KEY` and `GOOGLE_MAPS_IOS_API_KEY` are optional
in this repo. If absent, the app still ships, but embedded
`google_maps_flutter` widgets fall back to non-map route summary states while
`maps-gateway` continues to use the server Google/Gemini credential path.
