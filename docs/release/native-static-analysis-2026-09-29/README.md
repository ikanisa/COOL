# Native static-analysis checkpoint — 29 September 2026

**Scope:** current dirty checkout at HEAD `c2569a47c7f87de68a60c4a247b5c5e3ca640f06`, Flutter 3.44.4, Dart 3.12.2, Android Gradle Plugin 9.0.1, Gradle 9.1.0 and JDK 21.0.8. This is a development-variant checkpoint, not signed-release acceptance.

## Results

- `flutter pub get --enforce-lockfile` passed with a fresh isolated Pub cache; `pubspec.yaml` and `pubspec.lock` hashes did not change.
- `make format-check` passed without writing Dart source.
- `flutter analyze --fatal-infos --no-pub` reported no issues.
- `./gradlew :app:lintDevDebug :app:testDevDebugUnitTest --offline --no-daemon` passed. The lint XML at `build/app/reports/lint-results-devDebug.xml` reported **zero errors and 40 warnings**. The Android JVM unit task passed.
- The merged devDebug manifest declares `RECEIVE_SMS` and does not declare `READ_SMS`, `SEND_SMS`, `READ_EXTERNAL_STORAGE` or `WRITE_EXTERNAL_STORAGE`.

An initial lint run found one `InlinedApi` warning: `FEATURE_TELEPHONY_MESSAGING` is available only from API 33 while the app supports API 24. `MainActivity.supportsSmsAccess()` now uses that granular feature on API 33+ and the older `FEATURE_TELEPHONY` feature on API 24–32. The subsequent lint run removed this warning. Physical pre-33 SMS capability and receipt capture remain part of M02/M06 device acceptance.

## Remaining lint warning disposition

| Warning | Count | Disposition needed before Q02 closure |
| --- | ---: | --- |
| `ApplySharedPref` | 10 | Review each synchronous commit against native receipt and permission durability requirements before changing write semantics. |
| `ScopedStorage` | 2 | Source manifest uses `tools:node="remove"` to strip plugin storage declarations; verify the same absence from the final release manifest. |
| `GradleDependency` | 1 | Review desugar library 2.1.4 to 2.1.5 under the pinned dependency process. |
| `IconLauncherShape`, `IconLocation` | 6 | Review launcher assets under the owner-selected `revolut-design` authority and final artifact inspection. |
| `ObsoleteSdkInt` | 2 | Review `drawable-v21` folders after native visual regression and resource merging. |
| `UnusedAttribute`, `UnusedResources` | 2 | Review API-specific back callback and transparent drawable reachability before cleanup. |
| `UseKtx` | 17 | Style/extension suggestions; review only when touching the related code. |

The warnings are recorded, not blanket-waived. Q02 still requires a frozen clean commit, release-variant native analysis, generated-source checks and documented line-level decisions on material warnings. Q03/Q04 still require full exact-candidate tests and signed artifacts.
