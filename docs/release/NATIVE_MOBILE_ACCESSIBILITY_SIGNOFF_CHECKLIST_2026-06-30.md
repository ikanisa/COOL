# Native Mobile Accessibility Signoff Checklist

Date: 2026-06-30
Scope: Collect Flutter mobile app native accessibility follow-up for `docs/release/CRITICAL_NATIVE_MOBILE_EXPERIENCE_AUDIT_2026-06-29.md`.
Current decision: **NO-GO until signed**

## Evidence Packet

- Offline/cache tests: `test/shared/collect_repository_test.dart`, `test/features/mobile_completion_test.dart`
- Visual matrix: `.cache/mobile_visual_evidence_matrix/20260630T_critical_routes/summary.json`
- Android profile evidence: `.cache/mobile_native_performance_profile/20260630T_device_profile_gfxinfo/summary.json`
- Android structural accessibility: `.cache/android_accessibility_pixel4a/20260630T_connected_app_refresh/summary.json`
- iOS simulator smoke: `.cache/ios_simulator_smoke/20260630T_current/summary.json`
- Device evidence summary: `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md`

## Required Signoffs

| Signoff | Status | Required reviewer action | Evidence reference | Reviewer | Signed at |
| --- | --- | --- | --- | --- | --- |
| Android TalkBack auditory traversal | Open | Listen through auth, home, groups, scanner, contribution, payment, share, settings, offline, and error states on an Android device with TalkBack enabled. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Pending accessibility reviewer | Pending |
| iOS VoiceOver traversal or scoped waiver | Open | Listen through auth keyboard, QR permission, share sheet, photo picker, back gestures, payment status, offline, and error states on iOS, or record a human-approved iOS scope waiver for this release. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Pending iOS reviewer | Pending |
| Final native mobile accessibility decision | Open | Review automated evidence, structural accessibility output, human auditory notes, defects, waivers, and retest status before approving the native accessibility claim. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Pending release owner | Pending |

## Signoff Rules

- Android TalkBack must be `Signed`; it cannot be waived for a maximum native mobile experience claim.
- iOS VoiceOver may be `Signed` or `Waived`; any waiver must state that iOS is out of scope for this specific release claim.
- Final native mobile accessibility decision must be `Signed`.
- Every row must include a non-placeholder reviewer name and an ISO-8601 UTC timestamp ending in `Z`.
- Evidence references must be repo-relative files or HTTPS URLs.
- Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data.

Use `scripts/record_native_mobile_accessibility_signoff.sh` to update this
checklist after a real human review. Use
`scripts/native_mobile_accessibility_signoff_gate.sh --json` to verify whether
the signed metadata is sufficient for the native accessibility claim.
