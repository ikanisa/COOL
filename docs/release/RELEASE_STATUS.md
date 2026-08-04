# Collect Release Status

Status date: 2026-08-04
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
- iOS is marked out of scope for the Android Google Play go-live in
  `docs/release/RELEASE_APPROVALS.json`.
- `docs/release/UAT_EVIDENCE_MANIFEST.json` still records persona evidence as
  `pending` and the release owner decision as `NO-GO`.
- Public and Admin Cloudflare deployments are recorded in
  `docs/release/LIVE_DEPLOYMENTS.json` with live gate status `pass`.
- Local Play implementation/readiness checks pass except for authorized Play
  Developer Reporting access and live account-controlled Console surfaces.

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
