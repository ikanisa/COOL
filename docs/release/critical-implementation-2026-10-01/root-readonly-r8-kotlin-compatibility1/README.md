# Read-only R8/Kotlin compatibility finding

Cached AGP builder 9.0.1 embeds R8 9.0.32. Its version properties and a pinned-JDK R8 --version command agree. The official Android Kotlin compatibility table requires R8 9.1.29 for Kotlin 2.4, while current settings and locked stdlib use 2.4.20.

This records an existing Android toolchain compatibility gap under ARC09. It does not introduce a new acceptance requirement, determine the ongoing AAB outcome, or claim production acceptance. The R8 README documents a precise compiler override within pluginManagement.buildscript. No version change or public artifact acquisition was applied. The cached provider and maintained/private APP settings and locks were byte/identity equal before and after the readback. Actual Gradle-process classloader inspection was not performed.
