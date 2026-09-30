# Collect Firebase Messaging 16.5.0 native compatibility fork

Upstream package: firebase_messaging16.5.0. Previously locked hosted pub.dev archive SHA-256: `55cf1000dd72d229ebff3ce6a399bd35705a7675275478b31308afd90ac85751`.
The original BSD-3-Clause LICENSE is unchanged. UPSTREAM-SHA256.json binds every original cached package file; this manifest records cached bytes and does not independently authenticate a published archive. The complete original package is preserved in `docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/source-snapshot/upstream-package/`. Examples and upstream tests stay in that source evidence; all package runtime/platform files are retained here.

## Bounded changes

1. Remove the workspace-resolution declaration so this unchanged16.5.0 package version can resolve through Collect's local override. Package dependency versions remain unchanged.
2. Implement iOS `scene:willConnectToSession:options:` with `BOOL`, matching pinned Flutter3.44.4/ad70ec4617166f1c38e5d2bfd388af71fda14f06 `FlutterSceneLifeCycleDelegate`.
3. Return true only when the existing scene callback processed a notification with `gcm.message_id`, matching the adjacent upstream application notification delegate's FCM-selection policy. The original setup/action/initial-notification body is unchanged. Nil, empty and non-FCM options return false so subsequent plugins, application fallback and Flutter deep links can receive them.

The exact pinned engine dispatch consumes connection options after a true result and sends nil options to later plugins. It calls fallback/deep-link handling when unconsumed. Returning true for every scene connection would incorrectly consume non-notification deep links. Returning false for every connection would fail to report an already handled FCM notification.

All Dart, Android and macOS runtime bytes remain upstream. No Firebase initialization, APNs registration, credentials, notification delivery or hosted/provider behavior is asserted by the isolated native callback probe. Full current unsigned native compilation and separate provider/device acceptance remain required. Native prior-source negative and corrected callback/dispatch tests are retained under the dated compatibility packet. No SDK/pub-cache source is patched.
