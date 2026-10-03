# E3 Gateway Release — scoped acceptance

The frozen current source overlay contains 1,081 declared repository inputs, with 62 additions/updates and exactly two removed Aeonik font files. The repository adapter excludes `flutter_local_notifications` and `firebase_messaging` from Gateway only. Firebase Core remains. Gateway's 27 reachable Dart source files use Flutter/go_router and its own platform channel; neither Firebase initialization nor messaging/member bootstrap is reachable.

Twenty-four actual generated-registrant controls passed. The native sequence then assembled Gateway Release and passed lint with zero errors and 40 warnings. Its actual compile/runtime graphs exclude both notification projects; all three nonGateway flavor declarations retain both. The tool-generated main registrant is unchanged, and the separately generated production registrant is byte-identical. The Gateway generated/compiled registrant and assembled DEX omit both notification plugins while retaining Firebase Core. No permission or lint suppression was introduced.

`release-scoped-readback.json` binds the unsigned APK, dependency proof, original/generated/compiled registration, lint XML, manifest, signature, font payload and QA marker. The preserved APK is 82,297,842 bytes, SHA-256 `7a66f1b847ec36ab3f34db98b48c993073fedfadb6e08863633000be2fe4423d`. Aeonik entries/family and `POST_NOTIFICATIONS` are absent. Inter matches source SHA-256 `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031`. The explicit local unsigned QA marker remains.

The 565.38-second sequence remains failed: preparation for the requested Debug JVM stage found an undeclared dependency on the flavor-wide QA marker. Attempt 174 preserves the exact correction and unfinished-stage continuation. This failure does not reverse the observed Release assembly/lint/artifact checks. Existing native and AGP/Kotlin deprecation warnings remain recorded.

This is a captured Gateway native candidate and scoped E3 Release proof. Concurrent backend/MCP/test work makes the shared checkout mutable; no whole-repository semantic acceptance, production/iOS rebuild, physical-device, provider, signing or store claim is made.
