# Native Mobile Accessibility Responsibility And Signoff Checklist

Date: 2026-06-30
Scope: Collect Flutter mobile app native accessibility responsibility for the
current universal mobile design parity target in
`DESIGN.md`.
Current decision: **CODE-OWNED STRUCTURAL PASS; HUMAN AUDITORY SIGNOFF OPEN**

## Evidence Packet

- Offline/cache tests: `test/shared/collect_repository_test.dart`, `test/features/mobile_completion_test.dart`
- - Android profile evidence: `.cache/mobile_native_performance_profile/20260630T_device_profile_gfxinfo/summary.json`
- Android structural accessibility: `.cache/android_accessibility_pixel4a/20260630T_connected_app_refresh/summary.json`
- iOS simulator smoke: `.cache/ios_simulator_smoke/20260630T_current/summary.json`
- Current route screenshots: `.cache/mobile_route_render_smoke/20260702T131433Z/summary.json`
- Device evidence summary: `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md`

## Required Responsibilities

| Responsibility | Status | Codex-owned action | Evidence reference | Owner | Accepted at |
| --- | --- | --- | --- | --- | --- |
| Android TalkBack structural responsibility | Accepted | Codex accepts responsibility for automated Android structural accessibility evidence based on TalkBack-enabled node capture, semantics tests, route screenshots, and 200 percent text coverage. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Codex | 2026-07-02T15:59:00Z |
| iOS VoiceOver scope responsibility | Accepted | Codex accepts responsibility for the current automated iOS scope based on iOS simulator smoke, shared Flutter semantics, reduced-motion/text-scale tests, and the current release scope. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Codex | 2026-07-02T15:59:00Z |
| Final Codex accessibility responsibility | Accepted | Codex owns the automated and structural accessibility evidence for this code-owned parity target, but not the human auditory signoff. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Codex | 2026-07-02T15:59:00Z |

## Responsibility Rules

- No human reviewer identity is required for the code-owned structural responsibility rows.
- Every responsibility row must be `Accepted`, owned by `Codex`, and include an ISO-8601 UTC timestamp ending in `Z`.
- Evidence references must be repo-relative files or HTTPS URLs.
- Do not add secrets, signing keys, raw SMS bodies, OTPs, private phone numbers, raw receiver MoMo numbers, provider tokens, or production customer data.

## Required Human Signoffs

| Signoff | Status | Required reviewer action | Evidence reference | Reviewer | Signed at |
| --- | --- | --- | --- | --- | --- |
| Android TalkBack auditory traversal | Open | Listen through auth, home, groups, scanner, contribution, payment, share, settings, offline, and error states on an Android device with TalkBack enabled. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Pending accessibility reviewer | Pending |
| iOS VoiceOver traversal or scoped waiver | Open | Listen through auth keyboard, QR permission, share sheet, photo picker, back gestures, payment status, offline, and error states on iOS, or record a human-approved iOS scope waiver for this release. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Pending iOS reviewer | Pending |
| Final native mobile accessibility decision | Open | Review automated evidence, structural accessibility output, human auditory notes, defects, waivers, and retest status before approving the native accessibility claim. | `docs/release/NATIVE_MOBILE_DEVICE_EVIDENCE_2026-06-30.md` | Pending release owner | Pending |

## Human Signoff Rules

- Android TalkBack must be `Signed`; it cannot be waived for a maximum native mobile experience claim.
- iOS VoiceOver may be `Signed` or `Waived`; any waiver must state that iOS is out of scope for this specific release claim.
- Final native mobile accessibility decision must be `Signed`.
- Every signed row must include a non-placeholder reviewer name and an ISO-8601 UTC timestamp ending in `Z`.

Use `scripts/native_mobile_accessibility_signoff_gate.sh --json` to verify the
Codex-owned responsibility state and the still-open human auditory signoff.
