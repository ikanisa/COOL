# Universal Source Migration Inventory

This file is release evidence only. It is not a design authority, token source,
visual source, catalog, screenshot baseline, or resource pack. The only design
authority for this repo is the root `DESIGN.md`.

## Source Contract

- External source: `/Volumes/PRO-G40/DESIGN/DESIGN.md`
- Repo contract: `DESIGN.md`
- SHA-256 after refresh: `b5fd2243b2cc280e4808c761a1511133cdd4a5c5665e62224c73b8d2be6867ee`
- Exact-match proof command: `cmp -s DESIGN.md /Volumes/PRO-G40/DESIGN/DESIGN.md`

## Baseline And Scope

- Baseline branch before migration commit: `main...origin/main [ahead 2]`
- Migration commit: `01f14a50 Enforce universal DESIGN.md source`
- Files changed by migration commit: `126`
- Deleted tracked resource files in migration commit: `77`
- Current follow-up scope: refresh root `DESIGN.md` to the latest external
  source, remove the remaining Flutter `Image.asset` contract, and track this
  inventory.

## Removed Resource Classes

The migration commit removed these repo-owned visual resource classes:

| Class | Paths |
| --- | --- |
| Flutter fonts | `assets/fonts/collect/` |
| Runtime images, icons, logos, media, and splash assets | `assets/runtime/` |
| Public web install icons | `web/icons/` |
| Android bitmap launcher and splash resources | `android/app/src/main/res/**/collect_splash_logo.png`, `android/app/src/main/res/**/ic_launcher.png`, `android/app/src/main/res/drawable/collect_launcher_icon.png` |
| iOS app icon and launch image PNG catalogs | `ios/Runner/Assets.xcassets/AppIcon.appiconset/`, `ios/Runner/Assets.xcassets/LaunchBackground.imageset/`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/` |
| Store listing feature image | `fastlane/metadata/android/en-US/images/featureGraphic.png` |

## Current Enforcement Inventory

These files are allowed because they enforce the single-source rule or record
release evidence without defining design:

| Purpose | File |
| --- | --- |
| Contract gate | `scripts/universal_contract_gate.sh` |
| Contract audit | `scripts/universal_contract_audit.sh` |
| Mobile evidence delegation gate | `scripts/mobile_route_artifact_gate.sh` |
| Repo QA/UAT orchestration | `scripts/repo_wide_qa_uat.sh` |
| Runtime no-asset contract test | `test/features/runtime_component_contract_test.dart` |
| App shell contract test | `test/app_shell_test.dart` |
| Release document contract test | `test/release_docs_test.dart` |

## Current Reference Scans

The required tracked-path scan returns only the root contract:

```text
$ git ls-files | rg -i '(^|/)(design)(/|\.|-|_)|design[_-]|[_-]design|DESIGN_SYSTEM|design-system|figma|wireframe|prototype|visual_qa|collect_mobile_design|product_design|revolut_parity|baseline_routes|icon-mapping|source_variants|assets/brand|^assets/fonts/|^assets/runtime/|^web/icons/|^ios/Runner/Assets\.xcassets/.*\.(png|jpg|jpeg|webp)$|^android/app/src/main/res/.*/.*\.(png|webp)$|brand-primary-colors'
DESIGN.md
```

The broad local visual-file scan excludes build output, generated Flutter
tooling, and generated evidence folders, and currently returns no repo source
files:

```text
$ find . -path './build' -prune -o -path './.dart_tool' -prune -o -path './.cache' -prune -o -path './output' -prune -o -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.svg' -o -iname '*.otf' -o -iname '*.ttf' \) -print
```

The runtime source scan is expected to return only enforcement tests and gate
patterns, not production asset usage:

```text
$ rg -n 'Image\.asset|AssetImage|SvgPicture|flutter_svg|assets/runtime|assets/fonts|web/icons|collect_splash_logo|collect_launcher_icon|collect-web-512|wordmark\.png|featureGraphic|LaunchImage|LaunchBackground|AppIcon\.appiconset|brand-primary-colors' --glob '!build/**' --glob '!.dart_tool/**' --glob '!ios/Pods/**' --glob '!macos/Pods/**' .
```

Production code must not reintroduce repo-hosted fonts, app icons, splash
bitmaps, logos, media, SVG icon packs, screenshot baselines, generated token
JSON, or alternate design-source documents.

## Proof Gate Evidence

Required migration gates passed on 2026-07-02:

| Gate | Result |
| --- | --- |
| `scripts/universal_contract_gate.sh --json` | `pass` |
| `scripts/universal_contract_audit.sh --json` | `pass` |
| Forbidden tracked source/resource path scan | `DESIGN.md` only |
| Source visual-file scan excluding `build/` and `.dart_tool/` | no files |
| `/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .` | `pass`, 176 files, 0 changed |
| `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` | `pass`, no issues |
| Focused Flutter tests | `pass`, 122 tests |
| Full Flutter test suite | `pass`, 309 tests |

Optional repo-wide QA/UAT was attempted at
`.cache/repo_wide_qa_uat/20260702T204656Z/`. It produced useful passing
evidence but did not finish as a full GO gate:

| Nested Check | Result |
| --- | --- |
| `format_check` | `0` |
| `flutter_analyze` | `0` |
| `flutter_test` | `0` |
| `release_secret_scan` | `0` |
| `mobile_route_artifact_gate` | `0` |
| `admin_pwa_build` | `0` |
| `admin_pwa_manifest_gate` | `0` |
| `mobile_route_render_smoke` | `0`, route summary `pass`, 30 routes, 27 product screens, `390x844` |
| `android_apk_release_build` | `0`, built `build/app/outputs/flutter-apk/app-production-release.apk` |
| `android_aab_release_build` | `0` in the wrapper command log, but the later release artifact manifest did not find `build/app/outputs/bundle/productionRelease/app-production-release.aab` |
| `release_artifact_manifest` | `99`, blocked on missing production AAB |
| `flutter_mobile_release_gate` | `99`, blocked on `android_release_artifacts` and `android_release_artifact_signatures` because the production AAB was missing |

The optional wrapper was terminated after those blockers were recorded; no
`summary.json` was emitted by `scripts/repo_wide_qa_uat.sh --json`. This does
not weaken the universal design-source migration proof above because the
required contract, runtime, analyzer, focused, and full Flutter gates passed.
