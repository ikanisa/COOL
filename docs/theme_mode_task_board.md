# Theme Mode Task Board

Status: `PR1` through `PR8` implemented locally; `PR9` and `PR10` pending

## PR1 Theme Preference Foundation

- [x] Define `AppThemePreference` domain enum and ThemeMode mapping.
- [x] Add Hive-backed theme preference store.
- [x] Add Riverpod notifier/provider for theme preference state.
- [x] Preload saved theme preference in app bootstrap after Hive init.
- [x] Wire root `MaterialApp` instances to consume `themeMode`.
- [x] Add unit tests for store and notifier behavior.
- [x] Run targeted formatting and tests.

## PR2 Semantic Theme Builder

- [x] Split raw brand constants from semantic UI tokens.
- [x] Add light and dark semantic palettes.
- [x] Build shared `AppTheme.light` and `AppTheme.dark`.
- [x] Keep existing dark visuals unchanged while tokens migrate.

Note: the root app now respects the saved `themeMode` preference. Remaining
light-mode work is in the feature migrations listed in later PR slices.

## PR3 System Chrome And Native Alignment

- [x] Replace fixed dark system chrome with theme-aware behavior.
- [x] Align Android launch and normal themes with app theme mode.
- [x] Align iOS launch assets and splash backgrounds with app theme mode.
- [x] Revisit `flutter_native_splash` config for distinct day/night colors.

## PR4 Appearance Settings UI

- [x] Add `Appearance` entry under Profile > Preferences.
- [x] Add `System`, `Light`, and `Dark` selection UI.
- [x] Add localization strings for appearance controls.
- [x] Apply the selected preference instantly without restart.

## PR5 Shared Widget Migration

- [x] Migrate `CoolCard`, `CoolButton`, `CoolScreenBackground`, and scaffold helpers.
- [x] Migrate shared status, empty, error, toast, field, and chip widgets.
- [x] Remove direct dark-surface assumptions from shared primitives.

## PR6 Core Screen Migration

- [x] Migrate shell navigation and shared route chrome.
- [x] Migrate Home, Groups, and Profile surfaces.
- [x] Fix contrast and elevation semantics in the primary daily-use routes.

Note: targeted `flutter analyze` passed for the PR6 files. Targeted
`flutter test` smoke files for Home, Groups, and Profile currently stall during
the loader phase in this workspace before any test body executes, so smoke
verification is still pending.

## PR7 Mobility And MoMo Migration

- [x] Remove hardcoded dark picker and dialog overrides.
- [x] Migrate Mobility screens and shared widgets.
- [x] Migrate MoMo screens and shared widgets.
- [x] Document camera/QR overlays that intentionally stay dark.

Progress:
- Schedule Trip route, picker, toast, place search, and review widgets now use semantic light/dark tokens.
- MoMo home shell, send sheet, shared MoMo cards, statements screen, statements sections, QR sheet/card, payment request flow, and NFC sheets/cards now use semantic light/dark tokens.
- Mobility home, trip board, driver profile/detail/listing/map, and remaining driver widgets now adapt through the semantic compatibility bridge, so the Mobility slice no longer forces dark-only shell colors.
- QR canvas rendering remains intentionally white/black for scan reliability.

## PR8 Admin, Partners, And Rayon Migration

- [x] Migrate Admin screens.
- [x] Migrate partner discovery and partner detail screens.
- [x] Keep Rayon brand colors while making shell surfaces theme-aware.

Progress:
- Legacy `AppColors` semantic roles now follow the active light/dark brightness, which lifts the remaining Admin, Auth, Groups, Profile, Credit, Shared, and Partner shells onto the active theme without waiting for every file to read `context.coolPalette` directly.
- Light variants were added for the legacy card, blue, and purple gradients so older Rayon/group/shared cards no longer stay visually dark in light mode.
- Remaining direct `AppColors.bg/surface/text/border` references are compatibility-layer debt, not functional light-mode blockers.

## Intentional Fixed-Color Exceptions

- QR scanner overlays, QR canvases, and scanner chrome remain fixed black/white for scan reliability.
- PDF statement export styling remains fixed for document rendering, not app chrome.
- Rayon and partner hero art, badges, and brand marks keep fixed white/black treatments where they sit on controlled brand gradients or imagery.
- Some CTA and add-button icons still use explicit on-primary black/white on accent-filled buttons; these are contrast-safe but can be normalized later to `colorScheme.onPrimary`/`onError`.
- The current exhaustive file inventory is tracked in `docs/theme_mode_fixed_color_exceptions.md`.

## PR9 Backend Sync

- [ ] Add `theme_preference` and `theme_preference_updated_at` to `public.users`.
- [ ] Mirror theme preference into auth user metadata.
- [ ] Sync local and remote preferences with last-write-wins timestamps.
- [ ] Preserve preference across sign-in, sign-out, and multi-device restore.

## PR10 Test Matrix And Rollout

- [ ] Parameterize test harnesses for light, dark, and system modes.
- [ ] Add route smoke coverage in both light and dark.
- [ ] Add regression guards against new hardcoded dark theme APIs and hexes.
- [ ] Gate rollout behind a feature flag until dual-theme smoke passes.
