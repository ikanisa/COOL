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

Current evidence is mixed:

- Latest `./scripts/release_status.sh --json` result: `NO-GO`, `blocked`, with
  only `release_owner_signoff` remaining.
- The production APK/AAB are current for `1.2.2+10`. Their SHA-256 values are
  `fe130d6c493dd1ea09edf305ed4249437dab7f1c1b7035f7ec0122030a1d29aa`
  and `441b7937d3be6ef11f32d948ad787cb60fa5d231240144a9813a5d62df8cef1d`.
  The upload-certificate preflight and Android signing review are approved for
  that exact version without exposing signing material. The release-owner
  approval still identifies `1.2.2+9` and remains rejected as stale.
- iOS remains outside the Android Google Play approval manifest. E-081 retains
  current local iOS evidence: 35/35 Simulator routes, both controlled
  Camera permission phases, a passing App Store package gate, and a
  freshly rebuilt production-scheme unsigned `1.2.2 (10)` archive and a
  24/24 fresh manifest. The paired physical iPhone passed its staging prebuild
  but remained locked, so its runner never started. Distribution provisioning,
  physical VoiceOver/UAT, App Store Connect, upload, and processing remain open.
- `docs/release/UAT_EVIDENCE_MANIFEST.json` still records persona evidence as
  `pending` and the release owner decision as `NO-GO`.
- Public and Admin Cloudflare deployments are recorded in
  `docs/release/LIVE_DEPLOYMENTS.json` with live gate status `pass`.
- Local Play implementation/readiness checks pass except for authorized Play
  Developer Reporting access and live account-controlled Console surfaces.
- The extended cross-platform manifest passes 24/24 locally buildable files for
  public, Admin, Android, and iOS. GitHub-hosted CI is unavailable: recent pushes
  and current push run `30954970376` fails before job creation as `startup_failure`,
  requiring organization-level Actions administration.
- Production schema/RLS/migration and linked SMS/Admin UAT checks pass, but the
  strict Supabase readiness command fails closed until the four APNs
  credential/configuration secrets are supplied securely.

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

Do not submit app-store releases, regulatory reports, legal notices, Data
safety declarations, Stripe live-mode changes, public claims, filings, or other
external professional submissions from this repo without explicit recorded
human approval.
