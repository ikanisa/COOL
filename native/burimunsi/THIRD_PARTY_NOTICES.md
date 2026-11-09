# Asset and dependency scope

No font binary, brand-reference image, production credential, signing key, compiled Android artifact or dependency tree is bundled.

Native vector geometry is adapted from the owner's frozen `source/icons.json`. That frozen package explicitly did not establish independent icon-license provenance. Confirm T006 before distribution. System-native font fallback is used; no licensed font file is supplied. Exact native font and screenshot equivalence remain unverified.

The receiving implementation is referenced by repository commit/Git blob hashes and extracted from the owner's verified Collect checkout at build time, not copied into this package as a newly invented queue. Preserve the original source's ownership and applicable license notices.

Kotlin, Android/AndroidX, Gradle, coroutines, Node and test/build tooling remain under their respective upstream licenses. Pinned versions specify intended build inputs, not successful dependency resolution or a newly granted license.
