# Collect Revolut-Style Parity Signoff Checklist

Date: 2026-06-18
Repo: `/Volumes/PRO-G40/COOL`
Current decision: **NO-GO until signed**

This checklist captures the human-only decisions that automation cannot honestly complete. Do not add secrets, signing keys, raw SMS bodies, OTPs, PINs, provider tokens, private phone numbers, raw receiver MoMo numbers, or production customer data.

## Evidence Packet

- Parity evidence report: `docs/design/REVOLUT_PARITY_EVIDENCE_2026-06-18.md`
- Fresh Pixel 4a normal route evidence: `.cache/android_route_visual_evidence/20260618T_root_sms_redirect_contract_pixel4a/summary.json`
- Fresh browser member route evidence: `.cache/mobile_route_render_smoke/20260618T_root_sms_redirect_contract/summary.json`
- Fresh Pixel 4a 200 percent route evidence: `.cache/android_route_visual_evidence/20260618T_large_text_pixel4a/summary.json`
- Fresh mobile design compliance audit: `.cache/collect_mobile_design_compliance/20260618T_native_launch_splash_contract/summary.json`
- Fresh Pixel 4a native permission evidence: `.cache/permission_device_evidence/20260618T_native_permission_contract/summary.json`
- Fresh Pixel 4a TalkBack structural evidence: `.cache/android_accessibility_pixel4a/20260618T_talkback_structural_refresh/summary.json`
- Fresh Admin PWA render smoke: `.cache/admin_pwa_render_smoke/20260618T181108Z/summary.json`
- Fresh production release reinstall proof: `.cache/android_install/20260618T_after_root_sms_redirect_contract/package.txt`
- Signoff gate: `scripts/revolut_parity_signoff_gate.sh --json`

## Required Signoffs

| Signoff | Status | Required reviewer action | Evidence reference | Reviewer | Signed at |
| --- | --- | --- | --- | --- | --- |
| Revolut reference visual parity | Open | Compare Home, Groups, group detail, create, scan, profile, permissions, notifications, legal, light mode, and Admin PWA against the 11 supplied reference screenshots. | `docs/design/REVOLUT_PARITY_EVIDENCE_2026-06-18.md` |  |  |
| Android TalkBack auditory review | Open | Listen through representative Home, Groups, group detail, create group, scan, payment, profile, permissions, notifications, and legal flows. Confirm narration order, labels, and recovery actions are understandable. | `.cache/android_accessibility_pixel4a/20260618T_talkback_structural_refresh/summary.json` |  |  |
| iOS VoiceOver or scope decision | Open | Either complete iOS VoiceOver review on a current build or explicitly record iOS as out of scope for this Android parity claim. | `docs/release/RELEASE_APPROVALS.json` |  |  |
| Android release signing / Play App Signing review | Open | Confirm the current release artifacts and signing setup are acceptable for release. Do not record or expose private signing material. | `docs/release/RELEASE_APPROVALS.json` |  |  |
| Final release-owner parity decision | Open | Review this checklist, the evidence report, current release blockers, and approval records; then decide GO or NO-GO for the parity claim. | `docs/design/REVOLUT_PARITY_EVIDENCE_2026-06-18.md` |  |  |

## Completion Rule

The Collect app can only be called **100 percent Revolut-style parity complete** when every row above is signed or explicitly waived with a reviewer, timestamp, evidence reference, and sanitized notes. Until then, keep the parity claim at **NO-GO** even if all code-owned gates pass.

After updating this checklist, run `scripts/revolut_parity_signoff_gate.sh --json`. The expected current result is blocked with `human_revolut_parity_signoff`; a GO claim requires this gate to pass.
