# Collect Release Status

Status date: 2026-06-27
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

- Latest `./scripts/release_status.sh --json` result in this cleanup pass:
  `NO-GO`, `blocked`, blocker key `android_release_artifacts`, because current
  Android release APK/AAB artifacts are missing or stale.
- Android Play release approval metadata is recorded in
  `docs/release/RELEASE_APPROVALS.json`.
- iOS is marked out of scope for the Android Google Play go-live in
  `docs/release/RELEASE_APPROVALS.json`.
- `docs/release/UAT_EVIDENCE_MANIFEST.json` still records persona evidence as
  `pending` and the release owner decision as `NO-GO`.
- Public and Admin Cloudflare deployments are recorded in
  `docs/release/LIVE_DEPLOYMENTS.json` with live gate status `pass`.

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
