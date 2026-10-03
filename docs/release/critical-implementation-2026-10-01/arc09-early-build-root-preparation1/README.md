# Early Android app output root proposal

Unapplied, root-owned patch for exactly `android/build.gradle.kts` and `android/app/build.gradle.kts`. Configure only the app module's existing Collect build-root override before application of Flutter/AGP, preserving every other project directory and relative-path semantics. Remove the late duplicate override. No dependency, plugin, shrinker, signing or SDK version changes.

The private Gradle init script is a proposed bounded producer/configuration readback. It has not been executed. It does not replace the subsequent controlled AAB verification. Source delta metadata explicitly distinguishes the archived 2,561-file abf snapshot from a hypothetical two-file replacement and a still-unobserved actual new source identity. Historical failed packets remain failed.

Original and proposed two-file bytes are retained separately. No maintained, APP, SDK, cache or register mutation occurred while preparing this packet.
