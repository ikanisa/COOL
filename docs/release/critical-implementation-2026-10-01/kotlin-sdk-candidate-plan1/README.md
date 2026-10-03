# Independent Flutter SDK Kotlin candidate — review plan

This is a read-only plan and an unapplied patch preview. No SDK candidate was
created, no shared SDK or repository fork was edited, and no new native test was
run for this proposed SDK. The completed repository pin, strict graph, production
Kotlin compile and 12 native SMS unit results remain frozen in
[kotlin-dependency-batch1](../kotlin-dependency-batch1/README.md). Full ARC09 is open.

## Exact remaining component and source basis

The installed stable Flutter 3.44.4 reports framework commit
`ad70ec4617166f1c38e5d2bfd388af71fda14f06`, engine
`a10d8ac38de835021c8d2f920dbf50a920ccc030` and Dart 3.12.2. The fresh
[official tag response](https://api.github.com/repos/flutter/flutter/git/ref/tags/3.44.4)
matches that framework commit. Seven selected installed source/license files
match their exact official 3.44.4 bytes;
[installed-sdk-plan-observation.json](installed-sdk-plan-observation.json)
records those pairs and 37 current Gradle source/test hashes. This is selected
source identity, not whole SDK publisher authentication.

The official
[Gradle source](https://raw.githubusercontent.com/flutter/flutter/3.44.4/packages/flutter_tools/gradle/build.gradle.kts)
declares JVM KGP 2.2.20 at line 11 and runtime KGP 2.0.0 at line 57. The completed
native packet actually observed both the applied 2.2.20 plugin and selected 2.0.0
runtime artifact. Both remain within the affected range in
[GHSA-r937-wjx7-w2jp](https://github.com/advisories/GHSA-r937-wjx7-w2jp).
The parent's dated checks of 3.47.2 and master also retain those declarations;
[bound evidence](publisher-license-advisory-binds.json) preserves their exact
receipt hashes. No supported fixed upstream stable SDK was confirmed.

Read-only installed SDK Git status also reports `pubspec.lock` modified. Its
current and HEAD hashes are retained; the earlier native packet has no whole-SDK
clean-state receipt with which to attribute that modification. Do not copy that
tree and declare it pristine publisher source.

## Reviewable minimum proposal

[proposed-collect-only-sdk.patch](proposed-collect-only-sdk.patch) and
[proposed-delta.json](proposed-delta.json) are a preview against exact official
tagged source. Before/after hashes are proposal identities, not approved fork
trust anchors or executed test proof.

| Proposed source | Delta and purpose |
| --- | --- |
| `packages/flutter_tools/gradle/build.gradle.kts` | JVM 2.2.20 and implementation 2.0.0 to exact stable 2.4.20. Preserve the existing Kotlin DSL plugin, Java 11 target, AGP compile/test API and serialization dependency. |
| `gradle/src/main/kotlin/DependencyVersionChecker.kt` | Raise the candidate's error and warning floors to 2.4.20 together. The upstream build comment explicitly links the implementation pin to this minimum policy. |
| `gradle/src/test/kotlin/DependencyVersionCheckerTest.kt` | Use a supported 2.4.20 fixture; replace the obsolete warning-only case with behavior tests rejecting 2.0.0, 2.2.20 and 2.3.20 and accepting 2.4.20. |

The policy change is for a **dedicated Collect candidate**: it excludes projects
that the original SDK permitted and leaves no warning-only interval below the
security minimum. A pin-only experiment can first characterize compiler/runtime
compatibility, but must not quietly claim the upstream-linked policy is resolved.
Numeric version checking cannot independently guarantee a stable publisher
artifact; exact declaration, actual classloader/artifact and reviewed-delta
guards must enforce stable 2.4.20 separately. No bypass of dependency validation
is part of the proposal.

Kotlin's [publisher compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html)
covers KGP 2.4.20 with Gradle 9.1.0 and AGP 9.0.1. That does not establish Flutter
SDK plugin ABI compatibility. Gradle 9.1's
[versioned matrix](https://docs.gradle.org/9.1.0/userguide/compatibility.html)
lists its embedded Kotlin 2.2.0, and its
[Kotlin DSL guidance](https://docs.gradle.org/9.1.0/userguide/kotlin_dsl.html)
describes the external-plugin/embedded-library compatibility boundary. Keep
Gradle's bundled DSL version unchanged; retain any warning and require actual
compiler-plugin, runtime and application consumption tests. Do not substitute
the newest Portal DSL plugin or suppress mismatch diagnostics.

Flutter's unchanged `gradle_utils.dart` treats Kotlin versions newer than its
known range as provisionally valid. That fallback does not certify this
candidate. Its source/hash is retained, and the targeted tool tests belong in
the future proof. No Dart compatibility-table change is proposed without an
actual failing consumer and a separately reviewed delta.

## Physically independent execution sequence

1. Authenticate the fresh SDK foundation first. Prefer the exact official
   macOS arm64 3.44.4 bundle, using its independently published release metadata
   and archive SHA-256. The fresh official
   [release catalog](https://storage.googleapis.com/flutter_infra_release/flutter/releases/releases_macos.json)
   returned **404**, as the earlier check did; the failed request is retained in
   [origin-index.json](public-origin/origin-index.json). No archive digest or full
   binary bundle authenticity is currently proved. The tagged-source route may
   instead use a fresh official Git checkout pinned to the authenticated commit,
   verifying its commit/tree/blob identities and source licenses; it still needs
   independent engine/Dart artifact origin and checksum proof. Do not substitute
   a guessed archive, installed tree, or unverified cache hash for missing proof.
2. Create a new physical directory only after that foundation is reviewed.
   Use a new task-local SDK, native source copy and Gradle cache. Never use
   hardlink copies or mutate paths under `/Volumes/PRO-G40/Development/Flutter/flutter`.
   Reject unsafe/duplicate archive paths, special files and external link targets;
   allow only verified internal SDK links where required. Check writable regular
   files do not share inode identities with the installed SDK, and bind the
   complete pristine selected source manifest before applying any delta.
3. Apply only the reviewed preview deltas, preserving every other source and
   license byte. Bind explicit changed/added/omitted files, their reasons and
   immutable reviewed hashes. No tool may learn or bless arbitrary current bytes.
   Keep SDK version/engine/Dart and existing application wrapper/AGP pins fixed;
   any further compiler/API or serialization change requires a new reviewed delta.
4. Point only the new native copy's public generated package configuration,
   local Flutter path and included build at the candidate. Validate the Collect
   self-package, local forks, SDK package roots and generated package graph against
   frozen pubspec/lock bytes. Use the installed JDK/Android prerequisites, minimal
   environment, process-only analytics suppression and unsigned source-test mode.
   Exclude provider/signing configuration, keys and customer data. Root tools and
   every other project must continue to point at the installed SDK.
5. Run genuine SDK plugin compilation, strict plugin validation and all existing
   SDK Gradle unit tests. The
   [official SDK test guidance](https://raw.githubusercontent.com/flutter/flutter/3.44.4/packages/flutter_tools/gradle/README.md)
   identifies these tests. Reuse the authenticated existing Gradle 9.1 wrapper
   with `-p <candidate>/packages/flutter_tools/gradle`, rather than downloading
   engine build tools or generating a replacement wrapper. Required tasks are
   `compileKotlin`, `validatePlugins` and `test`, with no daemon/build cache and
   bounded workers. Retain each terminal log, runner, deadline, JUnit outcome and
   compiled plugin hash, including actual failures.
6. Observe actual SDK plugin/buildscript/compile/runtime selections. Authenticate
   the exact **JVM** Plugin Portal marker separately from the already checked
   Android marker; compare fresh Maven module SHA-256/SHA-512 with the selected
   2.4.20 JAR bytes. Record compiler/build-tools, SAM compiler plugin, embedded
   Gradle libraries and all SDK runtime artifacts. Require no affected KGP
   2.2.20/2.0.0 selection or fallback. Embedded Kotlin library version numbers must
   be classified by their actual component; the KGP advisory is not a blanket
   finding against every Kotlin library. Refresh advisory/license inventory for
   the complete actual graph before any closure claim.
7. Test real application consumers against a new coherent source cohort. Repeat
   both strict production artifact graphs, File Saver release Kotlin compilation,
   production app Kotlin compilation and the separate production-debug JVM unit
   task. Confirm both Flutter loader/app plugin classes load the candidate output
   without linkage errors and all 17 Android KGP instances still match the stable
   publisher artifact. Include current gateway flavor native/JVM consumers once
   their source is stable and confirm their exact tasks before execution. Use
   current later Dart/startup source for this new cohort; the previous successful
   frozen native copy cannot accept those later changes.

SDK ABI consumers include `FlutterPluginTest`, `FlutterPluginUtilsTest`,
`DependencyVersionCheckerTest`, `VersionFetcherTest`, `VersionUtilsTest`,
`BaseFlutterTaskHelperTest`, `FlutterTaskHelperTest` and the plugin loader's actual
application use. Run the complete existing SDK test set, and targeted
`packages/flutter_tools/test/general.shard/android/gradle_utils_test.dart` and
the existing Gradle plugin integration harness as prerequisites permit. Preserve
real missing prerequisites or failures rather than replacing them with source
searches. For exact stable selection, reject an old pin restored in the SDK,
unexpected source/manifest/archive drift, foreign publisher artifacts, license
loss, external/hardlink references and a residual vulnerable resolved KGP graph.

## Publisher, license and acceptance boundaries

[publisher-license-advisory-binds.json](publisher-license-advisory-binds.json)
binds 12 reusable primary or genuine native receipts. Fresh selected Flutter
[LICENSE](https://raw.githubusercontent.com/flutter/flutter/3.44.4/LICENSE)
matches the installed bytes (BSD 3-Clause, SHA-256
`a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20`).
The exact [KGP POM](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/2.4.20/kotlin-gradle-plugin-2.4.20.pom)
declares Apache-2.0. Preserve those copyright/license notices and inspect actual
SDK/engine/Dart/JAR/transitive notices and distribution obligations independently.
Source license identity is not complete redistribution-rights acceptance.

This proposal remains a local SDK fork, not a supported upstream stable fix.
Candidate publisher/fork integrity, SDK compiler/runtime/ABI tests, coherent app
consumer evidence and complete advisory/rights review are all still required.
Deployment, provider/device checks, signed artifacts, store acceptance and
production authorization remain separate. No candidate promotion or shared SDK
change is authorized or performed by this plan.
