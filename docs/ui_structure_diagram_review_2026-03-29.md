# UI Structure Review vs Visual Diagrams

Date: 2026-03-29

## Scope

This document compares the live app structure against the screenshot diagrams
stored under:

- `/Volumes/PRO-G40/COOL/visual. diagrams.flowcharts `

Cleaned copies with normalized names are available under:

- `/Volumes/PRO-G40/COOL/visual_diagrams_flowcharts_cleaned`

It also records the requested IA updates that are now implemented in code.

## Final IA Contract

The app now follows this contract:

1. Onboarding does not ask for MoMo setup.
2. The main shell uses 3 bottom tabs: `Home`, `BioPay`, `Settings`.
3. `Tickets`, `Contribute`, and `Rewards` are Home quick actions.
4. Profile/Settings owns the user's official default MoMo number/code.
5. MoMo is only enforced when the user starts `Contribute` or `Create group`.
6. Create-group pre-fills collection MoMo from profile when available, but the
   group MoMo stays editable and independent from the saved profile MoMo.
7. User-facing `Gamefy` / `Gamify` / `Gamification` wording has been removed
   from the consumer UI.

## Implementation Status

### 1. Bottom navigation

Implemented.

The shell remains path-compatible with the existing `/profile` branch, but the
user-facing shell label is now `Settings`, so the live tab set is:

- `Home`
- `BioPay`
- `Settings`

Relevant code:

- `lib/core/router/shell_route.dart`
- `lib/core/router/app_routes.dart`
- `lib/l10n/app_en.arb`

### 2. Onboarding and auth boot

Implemented.

The splash/auth boot flow no longer requires MoMo setup before entry. Users
can land in the app without wallet configuration, and MoMo is no longer part
of profile-completion gating.

Relevant code:

- `lib/features/auth/screens/splash_screen.dart`
- `lib/features/auth/models/user_profile.dart`
- `lib/features/profile/providers/profile_view_provider.dart`
- `lib/core/router/app_redirects.dart`

### 3. MoMo ownership and action-time enforcement

Implemented.

Profile/Settings now owns the official default MoMo record. A shared MoMo guard
intercepts blocked actions and routes the user to `Settings > Wallet` only when
they attempt:

- `Contribute`
- `Create group`

Relevant code:

- `lib/features/profile/services/momo_setup_guard.dart`
- `lib/features/profile/screens/profile_detail_screens.dart`
- `lib/core/router/app_router.dart`

### 4. Group creation MoMo model

Implemented.

Create-group now:

- pre-fills from the saved profile MoMo when present
- keeps group collection MoMo editable in the form
- persists group wallet routing separately from the profile wallet

This means the group collection number/code can differ from the user's saved
profile MoMo.

Relevant code:

- `lib/features/rayon/screens/contribution_circles_screen.dart`
- `lib/features/rayon/providers/rs_contribution_provider.dart`
- `lib/features/rayon/models/rs_contribution_models.dart`
- `supabase/migrations/20260329213000_contribution_groups_wallet_routing.sql`

### 5. Home quick actions

Implemented.

The Home quick-action row now prioritizes the requested top-level tasks:

- `Tickets`
- `Contribute`
- `Rewards`
- `Scan`

Relevant code:

- `lib/features/home/widgets/home_quick_services.dart`
- `lib/features/home/screens/home_screen.dart`

### 6. Rewards rename

Implemented in the consumer UI.

The Home entry point is now `Rewards`, and the visible consumer rewards
surfaces were renamed away from `Gamification`. The remaining internal route
and file compatibility aliases can stay as technical debt, but the user-facing
copy now uses rewards-oriented language.

Relevant code:

- `lib/core/status/screens/cool_tokens_screen.dart`
- `lib/core/status/screens/missions_screen.dart`
- `lib/features/home/screens/seasons_activities_screen.dart`
- `lib/shared/widgets/cool_status_card.dart`
- `lib/core/status/widgets/referral_banner.dart`

## Diagram Cleanup Required

The original screenshot diagrams should be redrawn to match the live app.

### Replace outdated shell diagram

Remove the old 5-tab layout and replace it with:

- `Home`
- `BioPay`
- `Settings`

### Replace outdated onboarding diagram

Remove all first-launch MoMo steps such as:

- `Profile setup (MOMO)`
- `MOMO verified`

Replace with:

- `App launch`
- `Anonymous sign-in`
- `Home`

### Add action-time wallet rule

Show this decision point instead:

- user taps `Contribute` or `Create group`
- if profile MoMo exists: continue
- if profile MoMo is missing: redirect to `Settings > Wallet`

### Redraw create-group wallet flow

Show two separate wallet concepts:

- `Profile MoMo`
- `Group collection MoMo`

The group wallet should be drawn as:

- prefilled from profile
- editable in create-group
- independent when saved

### Replace old gamification wording

Use:

- `Rewards`
- `Fan Rewards`
- `Reward Activities`

Do not use:

- `Gamification`
- `Gamefy`
- `Gamify`

## Remaining Technical Debt

These are compatibility leftovers, not user-facing IA blockers:

1. Legacy paths like `/profile` and `/gamification` still exist as compatibility
   routes/aliases.
2. Internal file names such as `cool_tokens_screen.dart` and
   `gamification_screen.dart` still reflect the old implementation history.
3. The original diagram source is still a screenshot dump rather than editable
   design source files.

## Recommended Next Diagram Deliverable

Create one clean editable diagram set with these five artifacts:

1. `app_shell_and_navigation`
2. `auth_boot_and_entry`
3. `settings_wallet_and_momo`
4. `contribute_and_create_group_wallet_gate`
5. `rewards_information_architecture`

Those five diagrams are enough to replace the current screenshot set and keep
design, QA, and engineering aligned.
