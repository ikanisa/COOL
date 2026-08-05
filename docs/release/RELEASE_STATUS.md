# Collect Release Status

Status date: 2026-08-05
Canonical machine-readable inputs:

- `docs/release/RELEASE_APPROVALS.json`
- `docs/release/UAT_EVIDENCE_MANIFEST.json`
- `docs/release/RELEASE_APPROVAL_PACKET.md`
- `docs/release/LIVE_DEPLOYMENTS.json`

## Current Summary

The release documentation previously mixed Android Play approval records, UAT
signoff manifests, old NO-GO audit reports, and dated implementation evidence.
This file is the readable current status; machine gates remain authoritative.

Current release-owner status is `GO`; third-party processing status remains
separate:

- Latest `./scripts/release_status.sh --json` result: `GO`, `pass`, with no
  approval blocker keys. The native mobile accessibility, UAT evidence, and
  release-approval evidence gates also pass.
- The production APK/AAB are current for `1.2.2+10`. Their SHA-256 values are
  `341272d66716fd6ef6e6950c07d476632481c66f5f5b75bc1e58b31181d9f115`
  and `68507fe84c9038cce11dbcdd19f83c666004c8b8e45ace9020e8dadb2e29442c`.
  The upload-certificate preflight and Android signing review are approved for
  that exact version without exposing signing material. The current release
  owner approval is tied to `1.2.2+10`.
- The member app and authenticated Admin PWA have completed the E-083 legacy-
  design eradication. Retired gradient/glass/media chrome is removed, the
  three obsolete runtime images are deleted, and the current visual system is
  accepted across iPhone, iPad, Android, Admin, accessibility, material-state,
  and golden matrices. Fastlane contains 5 current iPhone, 5 iPad, 6 Android
  phone, 5 seven-inch, and 5 ten-inch screenshots; the iOS readiness gate and
  all Play screenshot count/hash/dimension checks pass.
- iOS is now approved in scope. Xcode automatically resolved the production
  signing assets, archived `1.2.2 (10)`, and exported a distribution-signed
  App Store IPA. The IPA SHA-256 is
  `3d9172c453699126524892b9c826abb0759c69df5a67b43837bf1d64022f3a2c`.
  An authenticated Apple upload attempt established that App Store Connect
  already contains build `10`; the duplicate was therefore rejected. The
  existing build still requires authenticated UI inspection and submission.
- The physical iPhone was paired, unlocked, and accepted the final staging
  build, install, launch, and driver attach. The current E-083 run passed 3/35
  routes before CoreDevice invalidated its wireless connection on Home; the
  fail-closed harness rejected it for missing completion and 32 route markers.
  Summary/log SHA-256 values are
  `2bf4f708a3cf6cb2e4bae7e72a25cf79068cef0b5d6d4c4a6d5c0b15b1afb861`
  and `46ebd77c8fe0bde096fe11132396cbc4ad31e4990c5ce5766325f534078fdde2`.
  Prior accepted E-075 physical route evidence remains valid.
- `docs/release/UAT_EVIDENCE_MANIFEST.json` records all ten persona scenarios
  as owner-waived (not human-tested) and the release-owner decision as `GO`.
- Public and Admin Cloudflare deployments are recorded in
  `docs/release/LIVE_DEPLOYMENTS.json` with live gate status `pass`.
- Google Play Console is authenticated. The live app is on production
  `1.2.1 (8)`, with no unpublished changes and no reportable crash/ANR values.
  A production draft is ready for the current `1.2.2 (10)` AAB; browser upload
  awaits file-URL permission for the ChatGPT Chrome extension.
- The extended cross-platform manifest passes 24/24 locally buildable files for
  public, Admin, Android, and iOS. GitHub-hosted CI is unavailable: recent pushes
  and current push run `30954970376` fails before job creation as `startup_failure`,
  requiring organization-level Actions administration.
- Production schema/RLS/migration, linked SMS/Admin UAT, and error-level advisor
  checks pass. The full strict Supabase command still fails closed on the four
  absent APNs token/configuration secret names; no placeholder values were set.

Treat any older dated NO-GO/GO report as historical unless a current gate
reproduces it.

## Current Required Checks

Before making a new release or public go-live claim, rerun:

```sh
make release-status-json
make release-approval-evidence-gate-json
make uat-evidence-gate-json
ADMIN_PWA_LIVE_URL=https://admin.collect.ikanisa.com make supabase-go-live-gate-json
./scripts/repo_wide_qa_uat.sh --json
```

## Retained Governance Files

Keep these durable governance files in active docs:

- `docs/release/RELEASE_APPROVAL_PACKET.md`
- `docs/release/RELEASE_APPROVALS.json`
- `docs/release/RELEASE_APPROVALS.example.json`
- `docs/release/UAT_EVIDENCE_MANIFEST.json`
- `docs/release/UAT_EVIDENCE_MANIFEST.example.json`

## Current Human Approval Boundary

Jean Bosco explicitly authorized app release inspection, signing, upload, and
submission for `1.2.2+10`. This approval does not permit fabricated provider,
device, browser, or store-processing evidence and does not authorize unrelated
regulatory, legal, Stripe, financial, or professional submissions.
