# Native dependency compatibility

The first actual Android build exposed incompatible delivered pins: Compose BOM `2026.09.00` selected Compose `1.12.1`, and Lifecycle `2.11.0` required compile SDK 37 / AGP 9.1 or later. The delivered project specified compile/target SDK 36, AGP 9.0.1 and Gradle 9.1.0. The original failure remains in the `build-001` evidence.

The integration retains that supported Android toolchain and selects the latest compatible Compose BOM verified through published Google Maven POMs and AAR metadata:

| Component | Current selection | Published AAR minimum |
| --- | --- | --- |
| Compose BOM | `2026.06.01` | Selects Compose `1.11.4` and Material3 `1.4.0`. |
| Compose UI/Foundation/Animation | `1.11.4` | SDK 35 / AGP 8.6.0. |
| Material3 | `1.4.0` | SDK 35 / AGP 8.6.0. |
| Activity Compose | `1.13.0`, retained | SDK 36 / AGP 8.9.1. |
| Lifecycle Compose runtime/ViewModel | `2.10.0` | SDK 35 / AGP 8.6.0. |

Activity's transitive Core/Core-KTX resolves to `1.18.0`, whose metadata supports SDK 36 / AGP 8.9.1. AAR validation remains enabled. Kotlin Android/JVM/Compose compiler remains `2.4.21`, Gradle `9.1.0`, AGP `9.0.1`, build-tools `36.0.0`, minimum SDK 26 and target SDK 36.

The first optimized qualification attempt also exposed AGP 9.0.1's embedded R8 `9.0.32` rejecting Kotlin 2.4 metadata. Kotlin 2.4 requires R8 `9.1.29` or later. The settings now pin stable R8 `9.1.57` from Google Maven using R8's documented `pluginManagement.buildscript` override. This retains the Kotlin, Compose compiler, SDK, AGP and Gradle versions above. The Maven POM and JAR availability were verified. A targeted Gradle run confirmed effective class loading from `com.android.tools:r8:9.1.57` and both optimized qualification builds passed with no Kotlin metadata parsing warnings. The cached JAR SHA-256 is `2c21870df0294bba3d5597a3de8f79e385650ea309d6dc55ffbeaa700bad18a5`. Full clean APK inspection remains a separate result. Metadata warnings are not suppressed. Sources: [Android Kotlin/R8 compatibility](https://developer.android.com/build/kotlin-support), [official R8 override instructions](https://r8.googlesource.com/r8/+/refs/heads/main/README.md#replacing-r8-in-android-gradle-plugin), [published R8 POM](https://dl.google.com/dl/android/maven2/com/android/tools/r8/9.1.57/r8-9.1.57.pom).

Other corrections demonstrated by actual configuration/compilation:

- Removed `android.enableLegacyVariantApi`, which AGP 9 rejects.
- Imported `URI` explicitly to avoid Gradle's `java` extension shadowing the package name.
- Registered the receiver generation task through `addGeneratedSourceDirectory`, preserving exact source-pin verification and task dependency.
- Enabled custom resource values required by the app/variant names.
- Aligned wrapper metadata with the checksum-pinned Gradle binary actually used.
- Replaced unavailable `OsConstants.O_DIRECTORY` with public `Os.open` plus `fstat`/`S_ISDIR` validation and directory `fsync`; durable synchronization remains mandatory.
- Made the null-delimited host harness source collection work with macOS Bash 3.
- Updated the UI fixture with explicit snapshot provenance, and restricted durability tests to the exact offline/testOnly receiver sandbox before storage access.
- Added a root Material surface/content-color boundary and explicit light system-bar icons after a settled device capture exposed black inherited headings on the dark family. The capture pipeline now waits for UI idle evidence before collecting startup images.

Sources: [Google BOM POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.06.01/compose-bom-2026.06.01.pom), [Activity POM](https://dl.google.com/dl/android/maven2/androidx/activity/activity-compose/1.13.0/activity-compose-1.13.0.pom), [AGP 9.0 compatibility](https://developer.android.com/build/releases/agp-9-0-0-release-notes), [AGP 9.1 compatibility](https://developer.android.com/build/releases/agp-9-1-0-release-notes), [generated source API](https://developer.android.com/reference/tools/gradle-api/9.0/com/android/build/api/variant/SourceDirectories.Flat).

These metadata checks establish compatible prerequisites, not successful APK compilation or device acceptance. The actual build-result and APK inspection records determine those outcomes.
