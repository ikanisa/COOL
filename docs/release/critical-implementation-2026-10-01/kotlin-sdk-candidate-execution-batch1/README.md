# Independent SDK candidate: retained compiler failure

The exact three-file Collect candidate has genuine scoped main-compilation and
publisher-origin evidence. The complete compiler recipe **failed**: attempt 2
exited 1 after **208.412 seconds**, without timeout or headroom failure.
`validatePlugins` rejected five task metadata issues; `compileTestKotlin` rejected
unchanged upstream imports of Gradle-internal shaded JUnit classes. **Zero SDK
JUnit tests executed.** No candidate selection, promotion or release is approved.

The compiled output contains **83 actual class files plus one Kotlin module
metadata file** (84 regular main outputs). The generated 183,898-byte JAR contains
the same 83 class files with exact corresponding hashes. This corrects the earlier
intermediate shorthand “84 classes.” Main compilation/JAR generation does not
substitute for the failed validation and missing tests.

The reviewed writer expanded a fresh physical candidate in 24.183 seconds. Full
pristine readback passed in 7.054 seconds, the exact approved three-file patch was
applied, and full patched readback passed in 6.042 seconds. After the actual build
failure, full built-source readback passed in 9.048 seconds: all 22,415 retained
publisher members, exactly three permitted source deltas, all source/license/link/
mode/physical independence checks, and generated output only under the three
approved Gradle output roots. The generated outputs have their own manifest.

Attempt 1 was deliberately cancelled while re-downloading the exact distribution
after 13 minutes 17 seconds of compiler-wrapper elapsed time. Its 65,297,348-byte
partial, original producing runner, logs and cancellation receipt are retained.
The controlled parent and child process group received SIGTERM and were absent;
this was neither a timeout nor a compiler failure. A separate new 2,700-second
attempt used the **unchanged** frozen command and standard wrapper. Only the
complete raw Gradle ZIP was copied exclusively into the owned download location.
Its 232,491,070 bytes fully read back to the independently published SHA-256
`b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85`, with
distinct source/target devices/inodes and target link count one. No shared extracted
distribution or dependency-module caches were copied. The wrapper performed its
normal authentication and extraction. [Gradle publisher checksum](https://services.gradle.org/distributions/gradle-9.1.0-all.zip.sha256).

Actual loaded Kotlin JVM class hierarchy, runtime KGP and compiler components are
2.4.20. The loaded JVM classes point directly to the raw Gradle-813 KGP JAR:
30,694,269 bytes, SHA-256
`e9b18ac15c81b55d6d336356f9197aa1fb9f9371e0e76fbd2b06871cb5cf46b2`,
matching the independently authenticated publisher module descriptor. This is
actual loaded-byte evidence rather than an inference from declarations.
[Exact publisher KGP module](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/2.4.20/kotlin-gradle-plugin-2.4.20.module).

The actual compiler JAR matches a separately downloaded, full-readback HTTPS
publisher body: 58,593,245 bytes, SHA-256
`cf97161430683fb9af96dc6a7017ffae1fe8737b80d12eee11f2fe3e76f8ded8`.
Its actual SHA-1 matches the independently published sidecar. The compiler module,
SHA-256 and SHA-512 sidecar endpoints returned genuine retained 404s; an
independently published compiler SHA-256 is **not claimed**. The full public body
is retained outside the repository, with an explicit relocation receipt. Actual
cache POM bytes also match independent JVM-marker, core and compiler POM bodies.
Core embedded legal-member hashes and compiler POM Apache-2.0 declaration are
retained; the compiler JAR has no matching embedded legal members. This does not
clear every transitive dependency's license or advisory obligations.
[Exact compiler publisher JAR](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.4.20/kotlin-compiler-embeddable-2.4.20.jar),
[published compiler SHA-1](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.4.20/kotlin-compiler-embeddable-2.4.20.jar.sha1),
[compiler POM](https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.4.20/kotlin-compiler-embeddable-2.4.20.pom).

The full graph is **mixed**. Runtime Kotlin stdlib/common/JDK7/JDK8 resolve to
1.7.10 through retained serialization 1.4.0. Compiler stdlib resolves to 2.4.20
and reflect to 1.6.10. Complete observed graphs and all artifact hashes are
retained. Only the critical core/compiler origin binding is established; no
uniform-version, complete ABI, transitive advisory or full-license acceptance
follows from it. The actual Gradle Kotlin DSL warning also remains: its embedded
Kotlin is 2.2.0, and the requested 2.4.20 may behave differently. Generic SDK
template/maxKnown declarations remain 2.3.20 within the explicitly retained
Collect-only scope.

`terminal-native-failure-results.json` contains all actual five validation errors,
all compiler diagnostics, actual class/JAR hashes and zero-JUnit proof.
`actual-critical-publisher-license-bindings.json` and
`actual-applied-code-and-configurations.json` contain the genuine origin/loaded/
configuration evidence. `candidate-built-source-attempt2-readback.json` contains
the complete physical/source/generated-output manifest.

Current preservation readback proves all **235 leaves in six prior sealed
packets**, eight owned repository pin/lock/provenance inputs, 37 selected installed
SDK source paths, the previously observed installed SDK lock, and the pristine
foundation's three actual original source files unchanged. Whole installed-SDK
cleanliness is not claimed. No shared or pristine SDK, repository pins/locks,
Flutter bootstrap scripts, Dart tooling, application builds, signing or hosted
services were changed or executed by this packet.

Next work requires a separately reviewed exact extension for the five unchanged
upstream task/test files implicated by the real failures, while retaining the
complete command, validation and assertions. All SDK tests, application/native/
all-flavor consumers, current complete provenance/license/advisory/SBOM inventory,
candidate selection and release authority remain open. ARC09 remains open.
