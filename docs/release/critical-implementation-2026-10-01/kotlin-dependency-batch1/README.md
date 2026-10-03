# Kotlin dependency remediation — 1 October 2026

The three authorized repository declarations now select stable Kotlin 2.4.20.
Publisher authentication and the file_saver source comparison pass. Genuine
native resolution, compilation and unit results are recorded separately below;
this packet does not authorize production release. The installed Flutter SDK
also has older independently declared Kotlin build dependencies, so ARC09 remains
open across the complete toolchain.

| Declaration | Previous | Current | Purpose |
| --- | --- | --- | --- |
| `android/settings.gradle.kts` KGP | 2.3.20 | 2.4.20 | Application Gradle plugin selection |
| `third_party/file_saver/android/build.gradle` Kotlin | 2.1.0 | 2.4.20 | Standalone plugin/compiler and standard library alignment |
| `android/app/build.gradle.kts` stdlib-common | 2.3.20 | 2.4.20 | Match the selected compiler's standard library |

[reviewed-pin-delta.json](reviewed-pin-delta.json) proves each change is the exact
version replacement against preserved pre-change bytes. No wrapper, AGP, Android
runtime, signing, SDK configuration or unrelated dependency pin was changed.

## Publisher authentication

[GHSA-r937-wjx7-w2jp / CVE-2026-53914](https://github.com/advisories/GHSA-r937-wjx7-w2jp)
affects KGP before 2.4.20-Beta1 through unsafe build-cache metadata
deserialization, with the recorded local attack, high complexity and high
privilege conditions. Stable 2.4.20 is published in the
[Kotlin release list](https://kotlinlang.org/docs/releases.html) and
[official release](https://github.com/JetBrains/kotlin/releases/tag/v2.4.20).
The current primary release receipt confirms `draft=false` and `prerelease=false`.
The dated exact-target OSV query returned no records;
[advisory-crosscheck.json](advisory-crosscheck.json) binds these existing current
receipts. That query covers this KGP target, not the entire dependency inventory.

The [official compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html)
supports Gradle 7.6.3–9.7.0 and AGP 8.5.2–9.3.1 for KGP 2.4.20, covering the
repository's existing Gradle 9.1.0 and AGP 9.0.1.
[Android's AGP 9.0.1 documentation](https://developer.android.com/build/releases/agp-9-0-0-release-notes)
requires Gradle 9.1.0 and at least JDK 17. The legacy Kotlin/DSL opt-outs are
preserved. [compatibility.json](public-origin/compatibility.json) records the
source and ranges; compatibility documentation alone is not a successful build.

Exact public inputs are listed in
[origin-index.json](public-origin/origin-index.json). The
[Maven Central module metadata](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/2.4.20/kotlin-gradle-plugin-2.4.20.module)
publishes SHA-256 and SHA-512 for the main and `gradle813` plugin JARs. Both
downloaded JARs match both published digests. `gradle813` is the highest published
plugin API variant no newer than Gradle 9.1; actual Gradle selection must also be
observed. The [Plugin Portal marker](https://plugins.gradle.org/m2/org/jetbrains/kotlin/android/org.jetbrains.kotlin.android.gradle.plugin/2.4.20/org.jetbrains.kotlin.android.gradle.plugin-2.4.20.pom)
points exactly to KGP 2.4.20. The POM/marker published SHA-1 values match. Requested
SHA-256 sidecars returned 404; those failures are retained rather than reported as
successful checks. Strong JAR checksum proof comes from the publisher's module
metadata. [authentication.json](public-origin/authentication.json) records the
results. Public JAR bytes remain in the task-local cache; hashes, metadata,
URLs and observations are retained here without adding binaries to the source
distribution.

## Reviewed file_saver fork

The current [comparison](file-saver-fork-comparison.json) authenticates the
[official pub.dev metadata](https://pub.dev/api/packages/file_saver/versions/0.4.0)
and exact [0.4.0 archive](https://pub.dev/api/archives/file_saver-0.4.0.tar.gz),
SHA-256 `68c9a085d9bb4546e0a31d1e583a48d7c17a6987d538788ea064f0043b1fc02d`.
There are 184 upstream files, 48 retained fork files, 38 identical common files,
8 explicitly reviewed changed files, 2 added governance files and 138 omitted
examples, tests, documentation, images or IDE files. The license is byte-identical.
Seven previously changed source files retain the exact reviewed September 30
bytes. The only new native source delta is the one Kotlin version line.

`COLLECT_FORK_DELTA.json` binds each changed/added/omitted path to exact hashes
and rationale; the verifier pins that manifest's raw SHA-256. There is no mode to
learn arbitrary current fork bytes. The existing Dart formatting equivalence
check still runs. Unsafe archive paths, duplicates, links/devices and bounded
regular source reads use the existing authenticated-fork helper.

The [11-test transcript](fork-tests-attempt3.stdout) includes real copied-fork
and official-cache mutations: already-whitelisted runtime source, unsafe Kotlin
pin reversion, added/removed source, changed/lost license, manifest or governance
drift, changed archive, foreign metadata, symlink/FIFO and concurrent source
mutation during the real Dart formatting check. It also proves that missing or
foreign global pub-cache content does not change the canonical source proof;
that optional host observation is excluded from the current receipt so cold CI
can check the same official bytes. Attempt 1's failed assertion is
retained: license mutation was already rejected by an earlier delta-set check;
the explicit license check now reports that loss first. No negative was relaxed
to accept drift.

## Native checks and remaining toolchain boundary

Native checks use the [fixed runner](run-native.py), a copied source tree, the
installed JDK/Android SDK, and a task-local Gradle cache. Private ignored provider
and signing files are excluded. The explicit existing `collectUnsignedLocalQa`
mode prevents signing credential reads. The copied Collect self-package and
local fork references point to the isolated tree;
[native-source-build-inputs.json](native-source-build-inputs.json) binds its
selected source inputs. This snapshot is evidence for the affected native
toolchain and does not certify later independent product changes.

The initial fresh Gradle distribution download was deliberately stopped and
retained as an interrupted attempt. An existing complete ZIP was then rehashed
against the freshly fetched
[official Gradle checksum](https://gradle.org/release-checksums/) and the existing
wrapper pin before copying it into the fresh task-local cache. No extracted or
module cache was borrowed. The
[distribution receipt](public-origin/gradle-distribution-authentication.json)
records this distinction.

The first complete cold build attempt reached its 20-minute runner limit after
compiling the Flutter included Gradle plugin and downloading the application
KGP/AGP components; it has no successful graph or app compilation result. The
30-minute warm attempt then reached its own runner limit while configuring the
JNI plugin. Its [terminal receipt](resolve-compile-attempt3.json) and
[transcript](resolve-compile-attempt3.stdout) are retained with the exact
[runner used](run-native-attempt3.py). Attempt 4 continued the same source and
task-local cache with an explicit 45-minute limit and UTC boundaries, then
[completed compile-classpath resolution](resolve-compile-attempt4.json) in
11 minutes 34 seconds. [Runtime resolution](resolve-runtime-attempt1.json) also
completed, in 2 minutes 21 seconds. Neither report contains failed dependency
lines. The observed lock delta contains only `kotlin-stdlib-common` and
`kotlin-stdlib` changing from 2.3.20 to 2.4.20 for both production configurations;
[resolved-lock-observation.patch](resolved-lock-observation.patch) records it.
The genuine strict [compile graph](production-compile-graph.json) resolves 64
components and 47 external artifacts; the strict
[runtime graph](production-runtime-graph.json) resolves 173 components and 141
external artifacts. Both terminal runs succeed, every external artifact is
present and hashed, and neither graph contains unresolved dependencies. The
[reviewed lock promotion](reviewed-lock-promotion.json) then records promotion
of precisely those two version-line replacements into the repository lock;
all other lock bytes are preserved. These graph checks prove resolution and
artifact identity, while native compilation and unit outcomes are recorded
separately. All real attempts are retained, including failures or unmet
prerequisites. No source-string check substitutes for native compilation.

[effective-kgp-authentication.json](effective-kgp-authentication.json) binds the
actual applied plugin observation: all 17 Android Kotlin plugin instances,
including the app and file_saver, load KGP 2.4.20. Their loaded `gradle813` JAR
is byte-identical to the independently authenticated publisher artifact.
The compile/unit runner uses the SDK-supported process-only
`FLUTTER_SUPPRESS_ANALYTICS=true`; its source/hash observation is retained in
[process-only-analytics-suppression.json](process-only-analytics-suppression.json).
No persisted Flutter settings were changed.

The first [native compile attempt](compile-attempt1.json) ended with a genuine
failure because the isolated Flutter assembly needed generated
`.dart_tool/package_graph.json`. File Saver's Kotlin task had already compiled;
the failure and its [complete transcript](compile-attempt1.stdout) remain here.
The [metadata repair](compile-input-metadata-repair.json) reused only public
generated dependency metadata after verifying the matching frozen pubspec/lock,
all 168 package names, and every pinned non-root package version. There was no
`pub get`, source upgrade or SDK change. The
[second compile input map](native-source-compile-attempt2-inputs.json) contains
that one generated addition and no changes to the existing 751 selected files.

The same [second native compile](compile-attempt2.json) then passed, completing
`:file_saver:compileReleaseKotlin` and `:app:compileProductionReleaseKotlin` in
9 minutes 19 seconds. All 752 selected input hashes were reread unchanged after
the terminal result. The [transcript](compile-attempt2.stdout) retains the
existing plugin warnings and Gradle deprecation notice. Native production-debug
unit outcomes are recorded separately below; compilation alone does not prove
those behavior assertions.

The separate [native unit run](unit-attempt1.json) passed in 12 minutes 6 seconds.
Its [JUnit readback](native-unit-result.json) and retained [XML reports](junit/)
contain 12 tests across the SMS parser/envelope, queue ownership and worker
scheduling suites, with zero failures, errors or skips. All 752 selected input
hashes still match. The actual compile and unit classloader observations each
confirm 17 applied Android KGP 2.4.20 instances with the authenticated publisher
JAR bytes. [native-compile-output-observation.json](native-compile-output-observation.json)
binds the generated 20 application and 9 File Saver production class files;
these generated binaries remain in the local build cache.

The [final source readback](native-current-source-final-observation.json) verifies
that current production Android main/production/test sources and all eight owned
dependency/provenance files match the checked snapshot. It also records 25
changed selected repository inputs and 30 added public Dart/gateway sources
outside this snapshot. Those later product/startup and internal gateway changes
require their own cohort evidence. The native run does not accept them.

Existing warnings remain visible: File Saver's nullable string use at
`FileUtils.kt:204`, other plugin warnings, the legacy KGP/AGP opt-outs and Gradle
10 deprecations. This pin change preserves their runtime bytes. A future runtime
or DSL refactor needs its own reviewed delta and affected behavior checks.

[native-current-source-drift-observation.json](native-current-source-drift-observation.json)
records the current repository comparison against the isolated snapshot: eight
changed and eight added Android paths are confined to the independently changing
internal gateway and its dedicated tests. Production main/production/test inputs
and the three reviewed dependency declarations still match. No live native input
was replaced while Gradle was running.

The installed Flutter included build separately declares KGP 2.2.20 for its JVM
plugin and 2.0.0 as an implementation dependency. Its exact published-source
comparison and version/hash observations are retained in
[flutter-included-build-observation.json](public-origin/flutter-included-build-observation.json).
The pinned SDK source and version are unchanged; normal generated native build
outputs come from the genuine compilation. The genuine
[SDK runtime graph](sdk-runtime-graph.json) and its
[terminal receipt](sdk-runtime-attempt1.json) resolve 30 modules and 27 external
module artifacts without unresolved dependencies. KGP 2.0.0 is actually selected
on that SDK runtime configuration (`gradle85` JAR SHA-256
`fa9f364fb3ff1330ea2908e6ddfe66ee3d20abe975d61ae9f81e1e6bd276eaf7`),
while the SDK separately applies its JVM plugin 2.2.20. These are observed
component hashes and selection, not publisher authentication or remediation
through the application check. Both older KGP scopes remain outside the three
repository declaration changes; a supported fixed SDK path remains unresolved.

No signed AAB/IPA, installation, provider operation, customer action, store
submission, distribution-rights acceptance or production approval was performed.
