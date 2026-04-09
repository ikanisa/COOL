# Performance Budgets

> Monitored via Firebase Performance, Crashlytics, and CI gates.
> Last updated: March 2026

## Runtime Budgets

| Metric | Budget | Source | Alert Threshold |
|---|---|---|---|
| Cold start (P90) | < 3 s | Firebase Performance `_app_start` | > 4 s |
| Warm start (P90) | < 1.5 s | Firebase Performance | > 2 s |
| Jank rate (P90) | < 5% slow frames | Firebase Performance `_fr_perc` | > 8% |
| Crash-free sessions | > 99.5% | Crashlytics | < 99% |
| ANR rate | < 0.5% | Play Console | > 1% |
| Network TTFB (P90) | < 500 ms | Dio `PerformanceInterceptor` | > 800 ms |

## Build Budgets

| Metric | Budget | Enforcement | Notes |
|---|---|---|---|
| APK size (release) | < 50 MB | CI gate in `ci.yml` | Fail build if exceeded |
| AAB size (release) | < 30 MB | Manual check | Google Play limit: 150 MB |
| Dart analysis | 0 issues | `flutter analyze --fatal-infos` | Enforced in CI and release |
| Test pass rate | 100% | `flutter test` | Enforced in CI and release |

## How to Monitor

### Firebase Performance
- Dashboard: Firebase Console → Performance → Traces
- Custom traces: `cold_start`, `momo_send`, `group_contribution`
- Network traces: auto-instrumented via Dio interceptor

### Crashlytics
- Dashboard: Firebase Console → Crashlytics
- Breadcrumbs: added for MoMo flow, credit flow, and group contribution
- Non-fatal errors: logged via `FirebaseCrashlytics.instance.recordError()`

### CI Size Gate
- Runs on every push: builds release APK, measures size, fails if > 50 MB
- Size is recorded in build summary for trend analysis

## Baseline Profile

Located at `android/app/src/main/baseline-prof.txt`.

Pre-compiles hot startup paths (Flutter engine, Firebase init, deep link handling)
to reduce cold-start jank on first install.

### Regeneration

```bash
# 1. Build with compilation trace
flutter build profile --dump-compilation-trace

# 2. Analyse trace and update baseline-prof.txt

# 3. Verify improvement
flutter run --profile  # Compare cold start time on physical device
```

## Budget Review Cadence

- **Monthly**: Review Firebase Performance dashboards for P90 regressions
- **Per release**: Verify APK size stays within budget
- **Quarterly**: Re-evaluate budgets based on device distribution and network conditions
