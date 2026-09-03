# Collect production technical-readiness decision — 3 September 2026

Decision: **NO-GO for public distribution**.

The production backend and Admin PWA technical cutovers are complete. The
current native candidate is rebuilt, signed and validated as `1.2.4+23`, but it
has not been installed on the connected Pixel, uploaded to either store, or
accepted for public distribution. The aggregate release gate is intentionally
fail-closed on exactly two accountable approvals:

1. `android_release_signing_review` for the exact APK/AAB hashes below and the
   distinct Google Play app-signing certificate.
2. `release_owner_signoff` for the current evidence packet.

Neither approval is inferred from build success, deployment authority or the
instruction to continue. After both are recorded, rerun
`./scripts/release_status.sh --json`; a `GO` result is authorization evidence,
not proof of store upload, provider acceptance or public availability.

## Exact native candidate

- Version: `1.2.4+23`, synchronized in `pubspec.yaml` and used by both native
  release wrappers without a second hard-coded version source.
- Android package: `app.cool.mobile`.
- APK SHA-256:
  `b6fc920ebf786fe1216e243a62ed235c73dbf3ecdd12300366a8c86dcacbb6b6`.
- AAB SHA-256:
  `21a473fa88cf8b24d18002a88fb6b328f681a151514e9285a6a49cc302bc285a`.
- IPA SHA-256:
  `e550c57d70f547972232961927c9fc4abff5b336c574726840b4fc5066d97eb1`.
- Android upload certificate matches the pinned Google Play upload
  certificate. The pinned Play app-signing certificate is intentionally a
  different certificate and still requires current reviewer acceptance.
- Android contains `RECEIVE_SMS` and excludes `READ_SMS`.
- iOS strict signing passes with production APNs, `get-task-allow=false`,
  bundle `app.cool.mobile`, iOS 15.5 minimum and the production backend
  embedded.
- No native artifact was installed, uploaded or store-accepted by this run.

Canonical native evidence:

- [signed artifact verification](SIGNED_NATIVE_ARTIFACTS_V3_2026-09-03.json)
- [Android signing preflight](ANDROID_SIGNING_PREFLIGHT_1.2.4_23_2026-09-03.json)

## Production platform readback

- Supabase is healthy at 120 production migrations with no pending, missing or
  remote-only migration. Three historical migration-name differences are
  recorded; the versions and deployed SQL lineage remain reconciled.
- Eleven Edge Functions are active. The five hybrid functions were deployed in
  guarded dependency order and independently downloaded byte-for-byte:
  `verify-play-integrity` v4, `ingest-payment-sms` v5,
  `parse-payment-sms` v6, `prepare-roster-import` v1 and
  `collect-notification-operator` v1.
- All eleven Edge endpoints reject an unauthenticated empty POST with HTTP 401.
- The hybrid privilege cutover, linked production rollback UAT and
  production-copy restore/upgrade rehearsal pass. The linked UAT ended in
  `ROLLBACK`, sent no provider message and left protected production data and
  identity/control counts unchanged.
- All five hybrid rollout flags remain OFF, including direct USSD allocation.
  Disabled functionality is not represented as production-accepted behavior.
- The Admin PWA production version
  `871850eb-a270-489a-b400-b9facf6b5532` serves 100% of traffic and its live
  custom-domain asset/header gate passes at `https://admin.collect.ikanisa.com`.
- The temporary database rule `129.222.149.205/32` was removed. The original
  four IPv4 restrictions are unchanged and no IPv6 rule is present.
- An encrypted database archive was captured and restore/upgrade rehearsed.
  Supabase reports WALG enabled but managed PITR disabled and no listed managed
  backups; the release owner must accept that recovery posture or separately
  authorize a PITR plan before final signoff.

Canonical platform evidence:

- [final Supabase readback](SUPABASE_CONTINUATION_PREFLIGHT_V5_2026-09-03.json)
- [privilege cutover readback](HYBRID_PRIVILEGE_CUTOVER_READBACK_2026-09-03.json)
- [Edge cutover readback](HYBRID_EDGE_CUTOVER_READBACK_2026-09-03.json)
- [unauthenticated Edge smoke](HYBRID_EDGE_UNAUTHENTICATED_SMOKE_2026-09-03.json)
- [linked production rollback UAT](LINKED_PRODUCTION_ROLLBACK_UAT_2026-09-03.json)
- [restore and upgrade rehearsal](PRODUCTION_COPY_UPGRADE_REHEARSAL_V23_2026-09-03.json)
- [encrypted backup and network cleanup](ENCRYPTED_PRODUCTION_DATABASE_BACKUP_V2_2026-09-03.json)
- [live deployments](LIVE_DEPLOYMENTS.json)

## Verification completed

- `flutter analyze`: no issues.
- `flutter test`: 557/557 pass.
- Android production-debug unit tests and production-release lint: pass; 767
  Gradle tasks completed in the final gate.
- Local Edge shared tests: 54/54 pass; all five deployed entrypoints type-check.
- Combined SQL contract: 13 runs / 82 assertions pass.
- Clean migration replays pass through all 120 migrations.
- Twenty canonical Minitest files pass.
- Hosted advisor warning gate matches the reviewed inventory and performance
  has zero warning-level findings. Remaining password-protection advice relates
  to password authentication while this product uses WhatsApp phone OTP.
- `git diff --check`: pass.

Existing Kotlin/Android Gradle and CocoaPods migration notices are future
toolchain maintenance items, not failures in this candidate. They should not be
silently converted into release acceptance.

## Accountable approval commands

After reviewing the exact hashes and Play App Signing configuration, record the
Android approval with the real reviewer identity and a concise decision note:

```sh
make record-release-approval ARGS="--key android_release_signing_review --reviewer '<reviewer>' --evidence-reference docs/release/RELEASE_STATUS.md --notes '<approved 1.2.4+23 APK/AAB hashes and distinct Play App Signing configuration>' --sanitized-evidence --no-production-customer-data --no-signing-keys-exposed"
```

Only after that gate passes, record the final owner decision:

```sh
make record-release-approval ARGS="--key release_owner_signoff --reviewer '<release owner>' --evidence-reference docs/release/RELEASE_APPROVAL_PACKET.md --notes '<final 1.2.4+23 go/no-go decision>' --sanitized-evidence --no-production-customer-data"
```

Then rerun:

```sh
./scripts/release_status.sh --json
```

Store upload, submission, controlled rollout and public-availability checks are
separate state-changing steps and require explicit release authority after the
gate returns `GO`.
