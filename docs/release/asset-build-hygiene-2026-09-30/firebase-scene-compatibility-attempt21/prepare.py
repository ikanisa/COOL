#!/usr/bin/env python3
"""Preserve cached upstream bytes and prepare the reviewed bounded native fork."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
UPSTREAM = ROOT / ".cache/pub-cache-hygiene-20260930/hosted/pub.dev/firebase_messaging-16.5.0"
FORK = ROOT / "third_party/firebase_messaging"
SDK = Path("/Volumes/PRO-G40/Development/Flutter/flutter")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


assert not FORK.exists(), "Never overwrite an existing fork"
original = {}
snapshot = OUT / "source-snapshot/upstream-package"
for path in sorted(UPSTREAM.rglob("*")):
    assert not path.is_symlink(), "Preserved package must not follow symlinks"
    if not path.is_file():
        continue
    relative = path.relative_to(UPSTREAM).as_posix()
    target = snapshot / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)
    assert sha(path) == sha(target)
    original[relative] = sha(target)
    if relative.startswith(("lib/", "android/", "ios/", "macos/")) or relative in {"pubspec.yaml", "LICENSE", "README.md", "CHANGELOG.md"}:
        destination = FORK / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, destination)
        assert sha(destination) == original[relative]
plugin = FORK / "ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m"
before = plugin.read_text()
assert before.count("- (void)scene:(UIScene *)scene") == 1
after = before.replace("- (void)scene:(UIScene *)scene", "- (BOOL)scene:(UIScene *)scene", 1)
old_end = "  [self setupNotificationHandlingWithRemoteNotification:remoteNotification\n                                       actionIdentifier:actionIdentifier];\n}\n#endif\n\n#pragma mark - Firebase Messaging API"
assert after.count(old_end) == 1
new_end = "  [self setupNotificationHandlingWithRemoteNotification:remoteNotification\n                                       actionIdentifier:actionIdentifier];\n  // Consume only an FCM notification, matching the existing application delegate.\n  // Empty/non-FCM options remain available for other plugins and Flutter deep links.\n  return remoteNotification[@\"gcm.message_id\"] != nil;\n}\n#endif\n\n#pragma mark - Firebase Messaging API"
plugin.write_text(after.replace(old_end, new_end, 1))
pubspec = FORK / "pubspec.yaml"
text = pubspec.read_text()
assert text.count("resolution: workspace\n") == 1
pubspec.write_text(text.replace("resolution: workspace\n", "", 1))
(FORK / "UPSTREAM-SHA256.json").write_text(json.dumps(original, indent=2, sort_keys=True) + "\n")
sources = {}
for relative in ["engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycle.mm",
                 "engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycleTest.mm",
                 "engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterSceneLifeCycle.h"]:
    source = SDK / relative
    target = OUT / "source-snapshot/flutter" / Path(relative).name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    assert sha(source) == sha(target)
    sources[relative] = sha(source)
(FORK / "COLLECT_FORK.md").write_text("""# Collect Firebase Messaging 16.5.0 native compatibility fork

Upstream package: firebase_messaging16.5.0. Previously locked hosted pub.dev archive SHA-256: `55cf1000dd72d229ebff3ce6a399bd35705a7675275478b31308afd90ac85751`.
The original BSD-3-Clause LICENSE is unchanged. UPSTREAM-SHA256.json binds every original cached package file; this manifest records cached bytes and does not independently authenticate a published archive. The complete original package is preserved in `docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/source-snapshot/upstream-package/`. Examples and upstream tests stay in that source evidence; all package runtime/platform files are retained here.

## Bounded changes

1. Remove the workspace-resolution declaration so this unchanged16.5.0 package version can resolve through Collect's local override. Package dependency versions remain unchanged.
2. Implement iOS `scene:willConnectToSession:options:` with `BOOL`, matching pinned Flutter3.44.4/ad70ec4617166f1c38e5d2bfd388af71fda14f06 `FlutterSceneLifeCycleDelegate`.
3. Return true only when the existing scene callback processed a notification with `gcm.message_id`, matching the adjacent upstream application notification delegate's FCM-selection policy. The original setup/action/initial-notification body is unchanged. Nil, empty and non-FCM options return false so subsequent plugins, application fallback and Flutter deep links can receive them.

The exact pinned engine dispatch consumes connection options after a true result and sends nil options to later plugins. It calls fallback/deep-link handling when unconsumed. Returning true for every scene connection would incorrectly consume non-notification deep links. Returning false for every connection would fail to report an already handled FCM notification.

All Dart, Android and macOS runtime bytes remain upstream. No Firebase initialization, APNs registration, credentials, notification delivery or hosted/provider behavior is asserted by the isolated native callback probe. Full current unsigned native compilation and separate provider/device acceptance remain required. Native prior-source negative and corrected callback/dispatch tests are retained under the dated compatibility packet. No SDK/pub-cache source is patched.
""")
current = {path.relative_to(FORK).as_posix(): sha(path) for path in FORK.rglob("*") if path.is_file()}
changed = sorted(name for name in original if name in current and original[name] != current[name])
assert changed == ["ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m", "pubspec.yaml"]
omitted = sorted(set(original) - set(current))
assert all(path.startswith(("example/", "test/")) for path in omitted)
assert current["LICENSE"] == original["LICENSE"]
report = {"kind": "bounded_cached_firebase_messaging_fork_preparation", "upstream_version": "16.5.0",
          "upstream_archive_sha256_from_prior_lock": "55cf1000dd72d229ebff3ce6a399bd35705a7675275478b31308afd90ac85751",
          "upstream_files": original, "fork_files": current, "changed_common_files": changed,
          "omitted_files_preserved_in_source_snapshot": omitted,
          "added_files": sorted(set(current) - set(original)), "license_unchanged": True,
          "sdk_dispatch_header_test_sources": sources, "recorder_sha256": sha(Path(__file__)),
          "package_binding_published": False, "native_provider_acceptance": False}
(OUT / "preparation.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(json.dumps({"original_files": len(original), "fork_files": len(current), "changed": changed,
                  "omitted_preserved": len(omitted), "preparation_sha256": sha(OUT / "preparation.json")}))
