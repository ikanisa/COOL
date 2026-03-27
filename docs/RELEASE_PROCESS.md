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
feature branch → main → tag v*.*.* → CI release → Firebase App Distribution → Play Store
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
   - Runs `bash scripts/release_readiness.sh`
   - This includes Flutter analysis/tests, deep-link asset validation, Deno checks, and flavor verification
   - When optional `SUPABASE_DB_URL` is configured in CI, it also runs `scripts/verify_momo_sms_supabase_rollout.sh` with `TRIGGER_MIGRATION_CHECK=1` against the target Supabase environment
   - Decodes signing keystore from secrets
   - Builds signed release APK
   - Uploads to Firebase App Distribution (staff group)
   - Archives APK as build artifact
5. **Play Store**: Manual upload from Firebase App Distribution or CI artifact

## Critical Build Blockers

> **⛔ MANDATORY — These environment variables MUST be set for every APK and AAB
> build. Builds without them will produce non-functional artifacts.**

| Variable | Purpose | Enforcement |
|---|---|---|
| `SUPABASE_URL` | Production Supabase project URL baked into the binary via `--dart-define` | Shell scripts abort with `:?` check; Dart runtime shows config error screen |
| `SUPABASE_ANON_KEY` | Production Supabase anon key baked into the binary via `--dart-define` | Shell scripts abort with `:?` check; Dart runtime shows config error screen |

**Why this is critical:**
- These values are compiled into the Flutter binary at build time via `--dart-define`.
- If missing or empty, the app cannot initialize Supabase and will either crash or
  display a full-screen configuration error (`ConfigErrorApp`).
- This applies to **all build targets**: APK, AAB, staging, production, QA, iOS.
- This applies to **all build methods**: local scripts, CI/CD, manual `flutter build`.

**How to provide them:**
1. Export: `export SUPABASE_URL=https://... SUPABASE_ANON_KEY=...`
2. `.env` file at repo root (auto-loaded by build scripts)
3. `.env.json` with `--dart-define-from-file=.env.json`
4. CI secrets (GitHub Actions `release.yml` uses `secrets.SUPABASE_URL` and `secrets.SUPABASE_ANON_KEY`)


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
   - `kill_ticket_purchase` — disables ticket purchasing
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
- Ticket purchase

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
| `SUPABASE_URL` | Production Supabase project URL passed via `--dart-define` |
| `SUPABASE_ANON_KEY` | Production Supabase anon key passed via `--dart-define` |
| `FIREBASE_ANDROID_PRODUCTION_API_KEY` | Android production Firebase API key |
| `FIREBASE_ANDROID_PRODUCTION_APP_ID` | Android production Firebase app id |
| `FIREBASE_ANDROID_PRODUCTION_MESSAGING_SENDER_ID` | Android production Firebase sender id |
| `FIREBASE_ANDROID_PRODUCTION_PROJECT_ID` | Android production Firebase project id |
| `FIREBASE_ANDROID_PRODUCTION_STORAGE_BUCKET` | Android production Firebase storage bucket |
| `FIREBASE_APP_ID` | Firebase Android app ID |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase service account JSON |
| `COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT` | Final Google Play app-signing SHA-256 fingerprint |
| `COOL_IOS_TEAM_ID` | Apple Developer Team ID for the production bundle |
| `COOL_IOS_APP_STORE_ID` | Production App Store listing ID |
| `SUPABASE_DB_URL` | Optional remote database connection used to enable M-Money SMS Supabase rollout verification during release readiness |

## Native Release Inputs

Production iOS validation is intentionally fail-fast now. Before cutting a release,
ensure all of the following are present locally or in CI:

- `FIREBASE_IOS_PRODUCTION_API_KEY`
- `FIREBASE_IOS_PRODUCTION_APP_ID`
- `FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID`
- `FIREBASE_IOS_PRODUCTION_PROJECT_ID`
- `FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET`
- `FIREBASE_IOS_PRODUCTION_BUNDLE_ID`
- `COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT`
- `COOL_IOS_TEAM_ID`
- `COOL_IOS_APP_STORE_ID`

Client `GOOGLE_MAPS_ANDROID_API_KEY` and `GOOGLE_MAPS_IOS_API_KEY` are optional
in this repo. If absent, the app still ships, but embedded
`google_maps_flutter` widgets fall back to non-map route summary states while
`maps-gateway` continues to use the server Google/Gemini credential path.
