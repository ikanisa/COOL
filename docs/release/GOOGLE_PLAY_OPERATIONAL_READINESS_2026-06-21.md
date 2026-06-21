# Google Play Operational Readiness

Generated: 2026-06-21

Package: `app.cool.mobile`

## Purpose

This packet closes the repo-owned operational surfaces that sit around the Play
Console submission: metadata export, vitals/reporting retrieval, Play Integrity
rollout design, testing-track use, distribution review, and monetization status.

## Official Sources

- Store listing setup and limits: https://support.google.com/googleplay/android-developer/answer/9859152
- Store listing best practices: https://support.google.com/googleplay/android-developer/answer/13393723
- Managed publishing: https://support.google.com/googleplay/android-developer/answer/9859654
- Testing tracks: https://support.google.com/googleplay/android-developer/answer/9845334
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Sensitive permissions: https://support.google.com/googleplay/android-developer/answer/16558241
- Play Integrity overview: https://developer.android.com/google/play/integrity/overview
- Play Integrity setup: https://developer.android.com/google/play/integrity/setup
- Play Integrity standard requests: https://developer.android.com/google/play/integrity/standard
- Play Integrity verdicts: https://developer.android.com/google/play/integrity/verdicts
- Play Developer Reporting API: https://developers.google.com/play/developer/reporting/reference/rest
- Crash rate metric set: https://developers.google.com/play/developer/reporting/reference/rest/v1beta1/vitals.crashrate
- ANR rate metric set: https://developers.google.com/play/developer/reporting/reference/rest/v1beta1/vitals.anrrate
- Error count metric set: https://developers.google.com/play/developer/reporting/reference/rest/v1beta1/vitals.errors.counts

## Implemented Repo Automation

| Surface | Repo control | Current status |
| --- | --- | --- |
| Main listing metadata | `scripts/google_play_metadata_export.sh --json` writes fastlane-compatible `fastlane/metadata/android/en-US/{title,short_description,full_description,changelogs/9}.txt` from the Console audit packet. Feature graphic and phone screenshots are exported under `fastlane/metadata/android/en-US/images/`. | Ready for review/upload after Play credentials work. |
| Fastlane supply | `fastlane/Supplyfile` and `fastlane/Fastfile` define non-secret local validation and production upload lanes using `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` from the environment. | Ready after credentials work. |
| Release upload | `scripts/google_play_production_upload.sh --json` validates the AAB and `--submit` performs Android Publisher upload when scoped credentials are available. | Dry-run pass; submit auth blocked. |
| Policy/app content | `scripts/google_play_console_audit_packet.sh --json` validates public policy URLs, Data safety categories, production permission scope, and app-content prompts. | Pass. |
| Deep links | `scripts/google_play_optimization_gate.sh --json` validates manifest App Links and live `assetlinks.json`. | Pass. |
| Play Integrity | Native Android `collect/play_integrity` MethodChannel requests standard Play Integrity tokens when `PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` is configured. `lib/core/security/play_integrity_service.dart` builds request hashes and calls `verify-play-integrity`. `supabase/functions/verify-play-integrity` verifies tokens with Google using `PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON` from Supabase secrets. | Implemented, deploy/config blocked until Play/Cloud secrets are available. |
| Android vitals/reporting | `scripts/google_play_reporting_snapshot.sh --json` queries crash rate, ANR rate, slow start rate, slow rendering rate, excessive wakeup rate, stuck background wakelock rate, and error count metric sets when the Play Developer Reporting scope is available. | Auth blocked until Play reporting credentials are available. |
| Evidence index | `scripts/release_evidence_index.sh --json` includes the Google Play goal, submission evidence, surface matrix, and Console audit packet. | Document section pass. |

## Play Integrity Strategy

Current Play Console evidence says Play App Signing and automatic protection are
enabled. The repo now includes the backend verification path, and the native
client stays disabled until the Play/Cloud project number is injected at build
time.

Production rollout plan:

1. Enable and link the Play Integrity API to the app's Google Cloud project in
   Play Console.
2. Add a backend endpoint for high-risk actions only: account recovery,
   payment/reference review, group ownership changes, suspicious support
   actions, and SMS/payment evidence submission.
3. The Android app requests a standard integrity token through
   `collect/play_integrity` immediately before the high-risk server call.
4. The `verify-play-integrity` Edge Function decodes/verifies the token with Google, checks package name,
   certificate digest, request hash/nonce, app verdict, device verdict, account
   licensing where available, and recent timestamp.
5. The backend records only coarse pass/challenge/deny decisions and non-secret
   verdict categories needed for abuse analysis. It must not log raw tokens,
   customer payment identifiers, raw SMS, or service-account material.
6. Fail closed only for abuse-prone write actions. Keep read-only and account
   support recovery paths available with step-up review so legitimate users are
   not locked out by device compatibility issues.

Repo status: client channel, Flutter service, and backend verification function
are implemented. Production activation remains pending until the Google Cloud
project number and Play Integrity service-account secret are configured.

## Vitals And Reporting Strategy

`scripts/google_play_reporting_snapshot.sh --json` is the repeatable reporting
entrypoint. It requires either:

- `PLAY_DEVELOPER_REPORTING_ACCESS_TOKEN`, or
- `PLAY_DEVELOPER_REPORTING_ACCESS_TOKEN_CMD`, or
- a gcloud/ADC credential already authorized for
  `https://www.googleapis.com/auth/playdeveloperreporting`.

The script writes `.cache/google_play_optimization/google_play_reporting_snapshot.json`
and intentionally omits tokens, credential paths, cookies, signing keys,
service-account material, and customer data.

## Testing Tracks

- Internal testing: use for every smoke AAB before production if Publisher auth
  is available.
- Closed testing: use for invited savings-group operators or support staff
  before material workflow changes.
- Open testing: only use when the default listing and support process are ready
  to be public to non-customer testers.
- Production: release `1.2.2+9` is the current intended production update after
  upload/auth is unblocked.

## Distribution And Device Catalog

After the AAB is uploaded, record:

- Device reach and excluded device families.
- Android API coverage and any new SDK warnings.
- Form-factor compatibility including tablets, ChromeOS, and foldables where
  Play reports them.
- App size and delivery split results.
- Countries/regions and managed publishing state.

## Monetization

No Play Billing dependency is present in `pubspec.yaml`, and the Console audit
packet declares the current product as non-IAP. Do not enable Play Billing or
subscriptions unless the product scope changes to paid digital goods or
subscriptions and Data safety, tax, support, and refund flows are updated first.

## Remaining External Blockers

- Android Publisher API auth is unavailable for upload/commit.
- Play Developer Reporting API auth is unavailable for live vitals snapshots.
- Browser upload remains blocked by Chrome file chooser/file-access behavior.
- Live Console evidence still needs to be captured after the AAB is uploaded:
  publishing overview, production track, app content, store listing, deep links,
  vitals, pre-launch report, app integrity, device catalog, testing tracks,
  monetization, and reporting exports.
