# E3 Gateway native sequence 172 — failed lint

The single offline unsigned Gateway sequence took 401.66 seconds. Native assembly succeeded; lint stopped the sequence with one error and 40 warnings. The requested JVM task was not reached.

The repository flavor adapter successfully removed `flutter_local_notifications` from Gateway's actual compile/runtime project graphs, generated and compiled registrant, and assembled DEX. The tool-generated main registrant remained unchanged; the separately generated production registrant is byte-identical. Other flavors retain their notification dependency. No permission or lint suppression was introduced.

Lint exposed a second notifying dependency: `firebase_messaging`, through `com.google.firebase.messaging.DisplayNotification`, requires `POST_NOTIFICATIONS`. Firebase Messaging remained in the Gateway graph and registration. This concrete failure requires a second narrow flavor exclusion, preserving Firebase Core and all nonGateway behavior; it is not accepted as a clean native sequence.

`terminal-readback.json` binds the 1,051 selected frozen export inputs, owned adapter source, original registrant, dependency proof, compiled registration, manifest and signature. The unsigned APK SHA-256 is `ce93d5d41b9d56bd7686f967f3a8a8ce5905b4591651a509f68f5016b6297ae9` (82,473,945 bytes). `preserved-apk.json` locates its byte-verified retained copy outside the export that will be reused. The APK contains the explicit local unsigned QA marker, excludes `POST_NOTIFICATIONS`, and retains the pre-font Aeonik payload. It is not a license-cleared final candidate.

The previous settings verifier, Kotlin script and dependency-order failures remain preserved in attempts 169–171. Existing AGP/Kotlin/Android deprecation notices and lint warnings are retained. This packet proves the frozen E3 adapter and failed native sequence only; it does not certify current whole-repository acceptance, production/iOS builds, providers, physical devices, signing or store delivery.
