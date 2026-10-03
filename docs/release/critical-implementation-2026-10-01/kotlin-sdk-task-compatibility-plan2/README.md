# Exact task/test extension proposed after genuine failure

This is a review proposal for **five additional files**, preserving the original
three approved Collect version/checker changes. Nothing has been applied to any
SDK. The original failed candidate, compiled JAR and sealed failure packet remain
intact. The proposed patch is
`proposed-five-file-task-test-compatibility.patch`, SHA-256
`1e8afbbacd725d9f0578e69cff2c5c81f6c65a2ac00dca1a7c675c9097d4318e`.

All five before-byte identities equal both the authenticated pristine foundation
and the exact official Flutter Git blobs at
`ad70ec4617166f1c38e5d2bfd388af71fda14f06`. Their original copyright/license
headers are unchanged in the RAM-proposed after bytes. Six unchanged helper/test
consumers are separately bound to the same exact upstream tree. This establishes
byte attribution for the actual diagnostic locations; an unmodified SDK baseline
compiler was not executed.

| File | Exact proposal and rationale |
|---|---|
| BaseFlutterTask.kt | Explicit `@DisableCachingByDefault`: the helper invokes external local SDK/engine tooling with inputs not fully represented for shared caching. Retains the existing disabled-cache default. |
| FlutterTask.kt | Same explicit default with its own concrete reason; `sourceFiles` gains `@get:PathSensitive(PathSensitivity.ABSOLUTE)`. Its depfile-derived file inputs keep existing absolute identity. |
| DeepLinkJsonFromManifestTask.kt | Explicit disabled-cache default; merged `manifestFile` gains absolute normalization. Manifest copy and generated metadata behavior remains unchanged. Shared-cache behavior has not been established. |
| DeeplinkTest.kt | Replace private shaded JUnit `assertThrows` with already available public `kotlin.test.assertFailsWith<NullPointerException>`. Preserve the exact expected exception and original `equals(null)` block. |
| FlutterPluginUtilsTest.kt | Remove two Gradle-internal shaded assertion imports; use public `kotlin.test.assertTrue` and the existing `kotlin.test.assertFalse`. Every predicate, regex fixture and message remains identical. |

The authenticated Gradle 9.1.0 distribution source explicitly defines the missing
`PathSensitive` default as `ABSOLUTE`. The proposal preserves that default for
both properties and explicitly declares non-cacheability; it does not enable
caching, opt out of task tracking, disable property validation or claim portable
cache support. Exact publisher-source member bytes and hashes for
`PathSensitive`, `PathSensitivity` and `DisableCachingByDefault` are retained.
[Authenticated Gradle distribution](https://services.gradle.org/distributions/gradle-9.1.0-all.zip),
[publisher checksum](https://services.gradle.org/distributions/gradle-9.1.0-all.zip.sha256).

The public Kotlin assertions enforce the existing true/false expressions and
expected exception type. Actual already-resolved `kotlin-test:2.4.20` and
`kotlin-test-junit5:2.4.20` JAR hashes match independently downloaded publisher
module descriptors. The exact JUnit5 projection back to the parent Kotlin-test
component is validated rather than assuming a flat metadata identity. The
existing public JUnit API 5.10.1 compile artifact is present. The declared runtime
engine remains pending because compilation failed before tests could run; no
JUnit execution or full transitive origin/license acceptance is claimed.
[Public assertFailsWith API](https://kotlinlang.org/api/core/kotlin-test/kotlin.test/assert-fails-with.html),
[public assertTrue API](https://kotlinlang.org/api/core/kotlin-test/kotlin.test/assert-true.html),
[exact Kotlin-test metadata](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-test/2.4.20/kotlin-test-2.4.20.module),
[exact Kotlin-test JUnit5 metadata](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-test-junit5/2.4.20/kotlin-test-junit5-2.4.20.module).

Two read-only review-validator rejections are retained: initially assuming a flat
JUnit5 component identity, and then incorrectly requiring a runtime engine before
test compilation had succeeded. The completed reader validates the exact
publisher parent/variant projection, requires the actual compile API and records
the unresolved runtime engine as pending. The valid metadata acquisition was
reused; neither event was a candidate build or source mutation.

After root's exact review, the next preparation must bind a fresh physically
independent candidate2, cumulative eight-file source validator, exact exclusive
patch application and complete execution controller. Candidate1's source and
generated artifacts remain intact. Only the idle same-owned authenticated private
Gradle home may be reused; no global extracted/module caches, hardlinks or source
outputs are transferred. The unchanged strict compiler/validation/test/JAR/graph
tasks run with `--rerun-tasks` and `--no-build-cache`, a new fixed 2,700-second
deadline, exact candidate2 observer restriction and separate full source readback.

The runtime 1.7.10 stdlib family, compiler 2.4.20 stdlib/1.6.10 reflect, retained
serialization 1.4.0, embedded Kotlin DSL support warning and generic SDK
template/maxKnown 2.3.20 remain separate observed limits. No dependency version,
serialization, Kotlin DSL, template, application, repository pin or release scope
is expanded by this proposal. ARC09 remains open.
