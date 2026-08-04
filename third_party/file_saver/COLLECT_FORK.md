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
unchanged. The migration follows Flutter's plugin-author built-in Kotlin
guidance. Collect remains on Flutter 3.44/AGP 8, so the app cannot enable and
validate `android.builtInKotlin=true` until Flutter 3.47 or later; this fork
removes the unconditional upstream blocker without overstating that platform
gate as closed.

## Update rule

Before replacing or refreshing this fork, compare the upstream licence,
changelog, public API, platform manifests, permissions, Gradle configuration,
and package tests. Re-run dependency resolution, the Kotlin compatibility gate,
the full Flutter suite, Android release builds, packaged-permission inspection,
and source/evidence consistency gates.
