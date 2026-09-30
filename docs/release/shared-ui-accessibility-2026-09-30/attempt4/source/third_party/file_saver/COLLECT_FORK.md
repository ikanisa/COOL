# Collect file_saver fork

This directory is a controlled source fork of `file_saver` 0.4.0 from
pub.dev. The upstream package is BSD-3-Clause licensed; the unchanged upstream
licence is retained in `LICENSE`.

## Provenance

- Upstream package: `file_saver` 0.4.0
- Upstream source: `https://github.com/incrediblezayed/file_saver`
- Original cached Android Gradle SHA-256:
  `bb480272a269f20fb8e98f452e53c03503f71538bb2dd073cd63871e3d85ae1f`
- Original cached `pubspec.yaml` SHA-256:
  `ef78146a178dfb23290f2546cc6876990dcf6a5a22b5ba9747d2cb438b2a8adc`
- Fork version: `0.4.0+collect.1`

## Collect-owned changes

1. Raise the minimum Dart/Flutter versions to Dart 3.12 and Flutter 3.44.
2. Remove unconditional `kotlin-android` application.
3. Replace `kotlinOptions` with `kotlin.compilerOptions` targeting JVM 17.

The Dart API and all platform implementation source remain otherwise
unchanged. The migration follows Flutter's
[plugin-author built-in Kotlin guidance](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors).
Collect currently pins Flutter 3.44.4 and AGP 9.0.1, with
`android.builtInKotlin=false` and `android.newDsl=false` in
`android/gradle.properties`. Flutter 3.44 supports this temporary legacy-KGP
compatibility mode on AGP 9; enabling built-in Kotlin requires Flutter 3.47
or later and migration of every plugin. This fork removes the unconditional
upstream KGP application, but the full native graph and signed build still
require validation.

## Published-source comparison

The [29 September comparison](../../docs/release/supply-chain-2026-09-28/file-saver-fork-comparison.json)
checks every file in the published pub.dev 0.4.0 archive, SHA-256
`68c9a085d9bb4546e0a31d1e583a48d7c17a6987d538788ea064f0043b1fc02d`,
against this fork. Of 184 upstream files, 43 common files are byte-identical;
the only changed common files are `android/build.gradle`, `pubspec.yaml`, and
`lib/src/utils/mime_types.dart`. The MIME file becomes identical after Dart
formatting. The 138 omitted upstream files are examples, tests, README/images,
or an IDE project file; no package runtime or licence file was omitted. The
upstream `LICENSE` is byte-identical. `COLLECT_FORK.md` is the one added file.
Run `python3 scripts/supply_chain/verify_file_saver_fork.py --fetch --check`
from the repository root to repeat the published-archive comparison.

## Update rule

Before replacing or refreshing this fork, compare the upstream licence,
changelog, public API, platform manifests, permissions, Gradle configuration,
and package tests. Re-run dependency resolution, the Kotlin compatibility gate,
the full Flutter suite, Android release builds, packaged-permission inspection,
and source/evidence consistency gates.
