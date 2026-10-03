# E3 Debug JVM continuation — failed test classpath

Only `testInternal_gatewayDebugUnitTest` was requested. Release assembly, lint and dependency graphs were not repeated. The exact Gradle delta extends the existing `collectUnsignedLocalQa=true` marker dependency from Release to every existing production/Gateway preBuild variant. Marker payload/directory, Release dependency, notification adapter, permissions and default signing are unchanged.

The corrected Debug asset merge passed, all native/test sources compiled, and 98 tests executed in 146.07 seconds: 50 passed, 48 failed, zero errors/skips. Every failure is Android's desktop mockable `org.json.JSONObject` throwing “Method put … not mocked” before domain assertions: GatewayWire 10, GatewayDispatchWire 15, GatewayJournalArchive 23. Current XML and individual root causes are preserved. These cases require a real JSON runtime on the Gateway unit-test classpath; the failing stub must not be bypassed with default-return behavior or excluded tests.

`terminal-readback.json` verifies the exact owned Gradle/export hash, corrected marker ordering, unchanged tool-generated main registrant, and Debug registration excluding both notification plugins while retaining Firebase Core. The passed attempt 173 Release APK remains byte-identical, with its Inter/font/manifest/unsigned proof retained. Full E3 JVM acceptance remains open.

The common repository is concurrently changing. This report binds the captured native candidate and narrow owned source delta; it does not certify the entire current checkout, external services, devices, signing or store delivery.
