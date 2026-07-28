# Validation Plan

## Static and source gates

- `dart format --set-exit-if-changed .`
- `flutter analyze`
- `git diff --check`
- Source-contract tests reviewed for current architecture.
- Search for non-Inter font declarations, routine 800/900 weights, secrets,
  debug fixtures, unsupported branding, and private-data leakage.

## Automated test gates

- `flutter test --coverage`
- Focused widget and semantics tests for each changed component.
- Golden tests for shared shell, Home, Groups, Group Detail, Contribution,
  Activity, Profile, authentication, states, public web, and representative
  Admin PWA screens.
- Integration tests for authentication, five-tab navigation, contribution,
  ledger privacy, group management, offline recovery, and route matrix.

## Visual QA gates

- Open the verified reference and implementation screenshot together.
- Normalize to the same viewport and state.
- Fix P0/P1/P2 differences.
- Record only P3 polish after the final pass.
- Keep `design-qa.md` synchronized with the actual scope.

## Viewports and environments

| Target | Required evidence |
|---|---|
| 320x568 | Compact layout screenshot and large-text check |
| 368x800 | iOS baseline and reference comparisons |
| 390x844 | Standard iPhone screenshot |
| 430x932 | Large iPhone screenshot |
| Android compact/large | Emulator screenshots and critical-flow smoke |
| Larger adaptive layout | Navigation/layout evidence |
| Flutter web | Responsive interaction and keyboard evidence |

## Accessibility

- Semantics labels and reading order.
- iOS 44-point and Android 48-dp targets.
- 200% text scale.
- Light, Dark, and System modes.
- High contrast where supported.
- Reduced motion.
- Keyboard/focus navigation on web and Admin PWA.
- WCAG AA-equivalent contrast proof for critical text and controls.

## Performance and reliability

- Startup observation.
- Dense activity and group-list scroll observation/profile.
- Amount-entry rebuild behavior.
- Route transition and sheet animation checks.
- Offline/stale-cache and retry behavior.
- Record crash/ANR evidence as unavailable unless an authorized source exists.

## Build and release gates

- Flutter web release build.
- Android APK and app bundle release builds where local signing allows.
- iOS simulator build and unsigned/local release checks where allowed.
- CI workflow review.
- Security hygiene and secret scan.
- Dependency and license review.
- Store metadata, privacy, data safety, and account deletion recorded as
  external/human gates where not locally verifiable.

