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
4. Pin the standalone Gradle wrapper archive's SHA-256; its upstream wrapper
   version remains unchanged.
5. Replace Android/iOS routine logs of file paths, file sizes, method names and
   exception text/stack traces with fixed operation labels. Keep the existing
   structured channel errors and return values available to the caller.

The Dart API remains unchanged. The Gradle migration follows Flutter's
[plugin-author built-in Kotlin guidance](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors).
Collect currently pins Flutter 3.44.4 and AGP 9.0.1, with
`android.builtInKotlin=false` and `android.newDsl=false` in
`android/gradle.properties`. Flutter 3.44 supports this temporary legacy-KGP
compatibility mode on AGP 9; enabling built-in Kotlin requires Flutter 3.47
or later and migration of every plugin. This fork removes the unconditional
upstream KGP application, but the full native graph and signed build still
require validation.

## Published-source comparison

The [29 September comparison](../../docs/implementation/dependency-provenance-current.md#file-saver-2026-09-28)
retains the historical pre-correction comparison. The
[30 September comparison](../../docs/implementation/dependency-provenance-current.md#file-saver-2026-09-30)
retains that day's source review. The
[current comparison](../../docs/implementation/dependency-provenance/file_saver-0.4.0-comparison.json)
checks every file in the published pub.dev 0.4.0 archive, SHA-256
`68c9a085d9bb4546e0a31d1e583a48d7c17a6987d538788ea064f0043b1fc02d`,
against this fork. The explicit reviewed delta contains the Gradle build and
wrapper files, `pubspec.yaml`, `lib/src/utils/mime_types.dart`, the three Android
implementation files and iOS `Dialog.swift`. The MIME file becomes identical after Dart
formatting. The 138 omitted upstream files are examples, tests, README/images,
or an IDE project file; no package runtime or licence file was omitted. The
upstream `LICENSE` is byte-identical. `COLLECT_FORK.md` and the reviewed
`COLLECT_FORK_DELTA.json` are the two added governance files.
Run `python3 scripts/supply_chain/verify_file_saver_fork.py --fetch --check`
from the repository root to repeat the published-archive comparison. For an
isolated authored-source export, pass `--root /absolute/source` and
`--cache-dir /absolute/official-cache`; the same archive and exact-byte trust
checks apply. The default comparison is retained under
`docs/implementation/dependency-provenance/`. Historical packets are dated
evidence; the current index records their external custody and hashes.

The [native log packet](../../docs/implementation/dependency-provenance-current.md#native-log-packet)
records failing prior and corrected production plugin JVM log probes, compilation
of all three Kotlin sources against the cached Android36 and pinned Flutter
engine APIs, and fixed-literal Swift print checks. The test replaces only the
Android Log sink; it does not prove device behavior, Swift compilation or a
current unsigned/signed application build. Those artifact gates remain separate.

## Update rule

Before replacing or refreshing this fork, compare the upstream licence,
changelog, public API, platform manifests, permissions, Gradle configuration,
and package tests. Re-run dependency resolution, the Kotlin compatibility gate,
the full Flutter suite, Android release builds, packaged-permission inspection,
and source/evidence consistency gates.

## Kotlin build-tool security pin

The standalone Kotlin Gradle plugin/stdlib pin is now exactly `2.4.20`, aligned
with Collect's app plugin pin. This addresses the affected build-tool versions in
[GHSA-r937-wjx7-w2jp / CVE-2026-53914](https://github.com/advisories/GHSA-r937-wjx7-w2jp),
which concerns unsafe build-cache metadata deserialization under its stated local
privilege/cache trust conditions. No runtime source or license text changes.

The [Kotlin compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html)
includes Collect's Gradle 9.1.0 and AGP 9.0.1 in 2.4.20's supported ranges. Exact
Maven Central module metadata and downloaded plugin artifacts bind SHA-256 and
SHA-512; the Plugin Portal marker binds the exact plugin version. Primary response,
native compile/resolution evidence and remaining limits are retained in the
[Kotlin packet](../../docs/implementation/dependency-provenance-current.md#kotlin-packet).

`COLLECT_FORK_DELTA.json` and the verifier trust anchor bind every reviewed changed,
added and omitted byte set. A pin change requires manual review of the precise
Gradle line and trust-anchor update; the verifier cannot learn or approve arbitrary
new fork changes. Earlier comparison packets remain dated evidence.
