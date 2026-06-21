# Collect Secondary UI Upgrade Progress

Date: 2026-06-21
Repo: `/Volumes/PRO-G40/COOL`
Status: **Implemented and owned for the current code-owned mobile design gates**

## Scope Completed In This Pass

- Settings now starts with a Collect-owned visual account center, keeps primary
  settings actions visible in the first viewport, and adds a compact bento
  summary for identity, access, and support.
- Permission recovery routes now pair the existing recovery panel with a richer
  visual feature card and compact blocked/settings rows.
- Offline and sync routes now use stronger product status hierarchy with bento
  cells instead of paragraph-first recovery copy.
- Privacy, help, legal, account, and delete-request routes now use richer visual
  feature cards, compact status tiles, and shorter labels.
- Account MoMo display is now masked through `maskMomoNumberForDisplay()` rather
  than rendering the raw stored number in the account summary.
- Join-by-link entry is now code/QR-first in visible UI while preserving tolerant
  parsing for pasted links.
- Mobile route evidence now covers `/`, `/groups/search`, `/app`, and
  `/invite/038491` through the Flutter test renderer, with PNG size and sampled
  pixel checks so blank captures fail.
- `CollectionsScreen` can render in direct widget evidence mode without a
  `GoRouterState`, while normal app routing remains unchanged.
- Design audit assumptions now match the current shared chrome location
  (`lib/shared/widgets/collect_chrome.dart`) and route/search behavior.
- Public landing colors and auth transparent paint are tokenized through
  `CollectColors`, so the raw-color design gate is enforceable across `lib`.

## Validation Run

| Gate | Result | Evidence |
| --- | --- | --- |
| Dart format | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/dart format lib/app/theme/collect_colors.dart lib/features/auth/widgets/auth_screen_widgets.dart lib/features/collections/collections_screen.dart lib/features/collections/group_link_screen.dart lib/features/landing/collect_landing_page.dart lib/features/status/production_state_screens.dart lib/features/settings/settings_screen.dart test/visual_evidence_capture_test.dart test/persona_uat_smoke_test.dart` |
| Flutter analyzer | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` (`No issues found`, 221.6s) |
| Persona + public landing smoke | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/persona_uat_smoke_test.dart test/landing_page_test.dart` (`42` tests passed) |
| Design-system component contracts | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart` |
| Accessibility, large text, and theme parity | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart test/features/widgets_test.dart test/features/theme_mode_visual_parity_test.dart` (`29` tests passed) |
| Visual route fixture test | Pass | `COLLECT_VISUAL_EVIDENCE_DIR=.cache/flutter_visual_evidence/20260621T155059Z-secondary-ui-upgrade-current /Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/visual_evidence_capture_test.dart` (`58` mobile route screenshots plus admin screenshots passed) |
| Design compliance audit | Pass | `MOBILE_ROUTE_RENDER_SUMMARY=.cache/flutter_visual_evidence/20260621T155059Z-secondary-ui-upgrade-current/mobile/summary.json scripts/collect_mobile_design_compliance_audit.sh --json` |
| Diff whitespace check | Pass | `git diff --check` |

## Route Evidence Attempts

- Partial route capture: `.cache/mobile_route_render_smoke/20260621T145702Z-secondary-ui-upgrade`
  - Result: 9 screenshots captured before Chrome DevTools startup failed at
    `/permissions/sms-denied`.
- System Chrome rerun: `.cache/mobile_route_render_smoke/20260621T150250Z-secondary-ui-upgrade-system-chrome`
  - Result: no screenshots captured; Chrome DevTools startup failed at `/`.
- Current Flutter renderer evidence:
  `.cache/flutter_visual_evidence/20260621T155059Z-secondary-ui-upgrade-current`
  - Result: pass. `mobile/summary.json` records `58` expected routes, `58`
    captures, and all captured PNGs pass byte-size and sampled-pixel checks.

The Chrome/CDP failures remain environment-specific. The current code-owned route
evidence is the Flutter renderer capture above, which avoids Chrome startup and
still fails on missing routes or blank captures.

## Ownership Boundary

- There are no open code-owned mobile design blockers in this pass after the
  green analyzer, widget tests, visual evidence, and design compliance audit.
- External release approval, store submission, or public marketing claims are
  governance actions and should not be described as engineering blockers.
- The design contract and compliance audit now use this ownership split
  explicitly, so a passing code/design audit reports only code-owned evidence
  plus separate external approval scope.
- Optional: repair Chrome/CDP screenshot capture for web-rendered evidence. It
  is not blocking because the Flutter renderer path now provides full route
  coverage and blank-capture checks.
