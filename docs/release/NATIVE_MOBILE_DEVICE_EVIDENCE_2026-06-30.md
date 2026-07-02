# Native Mobile Device Evidence - 2026-06-30

Scope: native mobile evidence retained as release governance for the current
universal mobile design parity target in
`DESIGN.md`.

## Passed Evidence

- Offline/cache: `test/shared/collect_repository_test.dart` verifies snapshot persistence for profile, groups, payment intents, and ledger contributions; `test/features/mobile_completion_test.dart` verifies the stale cache is labeled as offline saved data on `/home`.
- Current route route evidence is produced by `scripts/mobile_route_render_smoke.sh`; the mobile route artifact gate now validates the latest `.cache/mobile_route_render_smoke/*/summary.json` instead of the deleted June 26 screenshot bundle.
- - Android profile performance: `.cache/mobile_native_performance_profile/20260630T_device_profile_gfxinfo/summary.json` passed on device `13111JEC215558`; artifacts include `timeline.binpb`, `gfxinfo.txt`, profile run log, runner result JSON, and a launch screenshot. Current metrics include `scenario_seconds=12`, `max_skipped_frames_logcat=60`, `gfxinfo_total_frames=3`, `gfxinfo_janky_frames=1`, and `gfxinfo_90th_percentile_ms=29`; this records current behavior but does not support a maximum smoothness claim.
- iOS simulator smoke: `.cache/ios_simulator_smoke/20260630T_current/summary.json` passed for the `production` scheme on iPhone 17 simulator; screenshot captured.
- Android structural accessibility: `.cache/android_accessibility_pixel4a/20260630T_connected_app_refresh/summary.json` passed on the connected Pixel 4a with TalkBack enabled, app state reset before each capture, and `app.cool.mobile` verified as the focused package for both captures.

## Code-owned structural accessibility responsibility

Codex owns the automated and structural native mobile accessibility evidence
for this code-owned universal mobile design parity target. The evidence set is automated
and structural:

- Android structural accessibility with TalkBack enabled.
- iOS simulator smoke for the production scheme.
- Flutter widget coverage for semantics, 200 percent text scale, reduced motion,
  loading states, route rendering, and shared component behavior.
- Route route evidence validated by
  `scripts/mobile_route_artifact_gate.sh`.

## Human auditory signoff still required

This structural evidence does not certify human auditory narration order,
pronunciation, comprehension, or iOS VoiceOver traversal. Use
`docs/release/NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST_2026-06-30.md` as
the canonical responsibility and signoff surface. Use
`scripts/native_mobile_accessibility_signoff_gate.sh --json` to verify Codex
ownership, evidence references, timestamps, secret-safe metadata, and the
remaining human signoff blocker.
