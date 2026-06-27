# Collect Mobile Annotated Findings Fix Goal - 2026-06-26

## Objective

Implement the Codex in-app browser annotation findings and the full mobile step-health review list for the Collect Flutter mobile app. The pass must reduce redundant/noisy UI, preserve required product functions, wire notification behavior through frontend, repository, Supabase RPC, and Edge Function contracts, and keep the Flutter web review target launchable inside Codex.

## Non-Negotiable Review Fixes

- Group create: keep group name and group description fields; remove only collection-type description text from type cards.
- Group create receiver: combine MoMo number and MoMo code into one receiver card with toggles and one active input.
- Profile setup: combine MoMo number and MoMo code into one receiver card with toggles and one active input.
- Settings: remove the Account center hero and redundant bento/status cards.
- Settings: remove the Readiness row and retire the redundant `/settings/readiness` route.
- Account: remove redundant hero/status card while keeping profile, MoMo, delete data, and sign-out functions.
- Account delete: remove redundant hero/status card while keeping reason selection, disabled-state behavior, and submit flow.
- Notifications: remove the noisy top permission-status card.
- Notifications: keep the preference toggles and implement notification events through Flutter state, Supabase table reads, mark-read RPC, preference-gated enqueue RPC, and Edge Function response handling.
- Contribution: clean the screen so amount entry is the primary task; remove collection-type marketing copy and redundant review actions.

## Step Health Implementation Checklist

### Must Fix In This Pass

- Launch/root: verify default route, empty loading state, and no dead landing surface.
- Auth phone: simplify instructions, improve validation copy, and prevent truncation on small screens.
- Auth failure: strengthen recovery actions and error distinction.
- Profile setup: make requirements clearer and keep MoMo number/code toggle card.
- Profile readiness: remove the redundant screen; represent readiness only where it directly unblocks a task.
- Groups search: improve empty/search states and recovery copy.
- Group create: keep name/description, remove type-card descriptions, and simplify receiver setup.
- Contribution: simplify amount/review flow.
- Payment intent: clarify what is being created and what the user does next.
- Payment waiting: add clearer guidance and recovery states.
- Payment pending: distinguish pending verification from support review.
- Payment expired: make retry clarity explicit.
- Payment needs review: improve user guidance and support handoff.
- Payment support review: add form guidance and disabled-state clarity.
- Manage group: group actions by role and risk.
- Members: clarify role/access state.
- Device permission: make explanations task-specific.
- Sync: add more status detail.
- Account: remove redundant visual card and keep direct account actions.
- Account delete: explain disabled submit state.
- Legal terms/privacy: improve reading ergonomics.
- Fresh link request: improve form/copy guidance.

### Verify And Keep

- Onboarding: keep flow; check truncation risk.
- Auth success: keep.
- Home: keep density but check bottom-nav overlap and scanability.
- Groups list: keep.
- Join portal: keep with fallback check.
- Shared group link: keep privacy copy concise.
- Group detail: keep, but check action labels.
- Group created/joined: keep.
- Share group: check modal/title clarity.
- Ledger: keep.
- SMS denied: keep, check truncation.
- Notifications denied: keep and document native handoff test requirement.
- Camera denied: keep and ensure manual fallback exists.
- iPhone create unavailable: keep but ensure platform wording is precise.
- Notifications: keep preference list and backend event integration.
- Offline: keep.
- Settings: keep cleaned version; verify bottom-nav overlap.
- Privacy data: keep, check readability.
- Help support: keep and verify escalation path.
- Share invalid/expired: keep.

### Manual Or Native Verification Gates

- Group scan: requires native camera/device test beyond web review.
- Notifications denied: requires native permission handoff test.
- Camera denied: requires native permission handoff plus manual fallback test.
- iPhone create unavailable: requires iOS/mobile-web platform wording check.

## Implementation Rules

- Do not remove real functions just because a status/hero card is noisy.
- Keep sensitive payment receiver data out of public share surfaces.
- Preserve existing repository patterns and tests.
- Do not revert unrelated dirty worktree changes.
- Rebuild `build/codex_mobile_review_web` and relaunch `http://127.0.0.1:57124` for Codex review.
- Validate with `flutter analyze --no-pub` and focused route/repository/Supabase tests.

## Evidence Targets

- Source diff covering all annotated comments.
- Supabase migration/function contract for notification preference gating.
- Focused Flutter analysis and test output.
- Codex in-app browser URL reachable at `http://127.0.0.1:57124`.
