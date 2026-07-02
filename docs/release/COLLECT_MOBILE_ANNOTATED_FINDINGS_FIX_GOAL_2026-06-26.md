# Collect Mobile Annotated Findings Fix Goal - 2026-06-26

## Objective

Fix the annotated Flutter mobile review findings across the listed screens,
rebuild the Codex in-app browser review target, and validate the implementation
with focused Flutter analysis and tests.

## Current Status

Status: complete in the code-owned Flutter mobile/web review surface.

Current completion authority:
`docs/design/MOBI_REVOLUT_100_PERCENT_ALIGNMENT_MATRIX.md`.

## Annotated Findings Checklist

| Area | Status | Evidence |
| --- | --- | --- |
| Home top QR shortcut removed | Done | In-app browser `/home` screenshot after final rebuild; `HomeScreen` top chrome has notifications only. |
| Home Join action removed | Done | `/home` shows Create, Scan QR, Share only; app-shell and mobile completion tests pass. |
| Default generated group card artwork removed from mobile group cards | Done | `/home` group cards render generated color surfaces instead of hardcoded image art. |
| Activity duplicate mini-profile icon removed | Done | Activity rows show Collect ID/date aligned without duplicate inline identity icon. |
| Group create keeps group description | Done | `/groups/create` shows group name and optional description on the name step. |
| Group type descriptions removed | Done | `/groups/create` type step shows only type names/icons. |
| Receiver MoMo controls combined | Done | Shared MoMo receiver card uses MoMo Number / MoMo Code segmented control and one input. |
| Settings hero/bento/readiness noise removed | Done | `/settings` shows compact Collect ID, Notifications/Dark mode, Account, Help/Terms/Privacy only. |
| Notifications status banner removed | Done | `/notifications` starts with category toggles and repository-backed notification events. |
| Notification events implemented | Done | Repository, live reader, Supabase preference gate, send function, and tests updated. |
| Readiness screen removed | Done | Production route list and smoke matrix no longer include `/settings/readiness`. |
| Manual join-code screen removed | Done | Visible Join action is gone; `/groups/join` is not in production route inventory; QR/deep-link join remains. |
| Contribution screen cleaned | Done | `/groups/col-church/contribute` has top-left back, group name, manual amount only, and no avatar/search/presets/currency chip. |
| Contribution review uses full receiver and MOMO label | Done | Review summary shows full receiver number and primary action `Pay with MOMO`. |
| Frontend waiting screen removed | Done | `/waiting` route and `ReturnFromMomoWaitingScreen` are removed; handoff redirects to status. |
| Group detail title constrained | Done | Group hero title is one line with ellipsis. |
| Group type badge icon-only | Done | Group detail hero type badge renders the icon-only form. |
| Group hero icon uses collection type | Done | Group detail hero icon uses the collection type icon, e.g. church icon. |
| Manage attention strip removed | Done | `Group needs attention` is removed from manage route and tests assert absence. |
| Group profile native cleanup | Done | Profile uses compact card sections, recurring on/off plus daily/weekly/monthly, and admin invite field. |
| Profile setup MoMo control cleaned | Done | `/settings/profile` uses compact segmented MoMo Number / MoMo Code control without redundant floating label. |
| Legal/account/delete hero cards removed | Done | Terms, Privacy, Account, and Delete Request screens no longer render the noisy hero cards. |

## Validation

Passed:

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/shared/collect_repository_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/supabase_contract_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/widgets_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/mobile_completion_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/persona_uat_smoke_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter build web -t lib/main.dart --release --no-wasm-dry-run --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true --output=build/codex_mobile_review_web`

## Review Target

The Codex review target is rebuilt and served locally:

- `build/codex_mobile_review_web`
- `http://127.0.0.1:57124`
