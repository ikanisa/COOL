#!/usr/bin/env python3
"""Compile/run exact isolated plugin callback and pinned engine dispatch on macOS.

The Objective-C method bodies and protocol declaration come from real source;
Foundation stand-ins isolate notification/setup state. This is not an iOS
device, Firebase SDK/provider integration, or full plugin compilation claim.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SDK = Path("/Volumes/PRO-G40/Development/Flutter/flutter")
XCODE = "/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer"
METHOD = "ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def method(text, pattern):
    found = re.search(pattern, text)
    if not found:
        raise ValueError("Expected exact callback/dispatch signature is absent")
    start = text.index("{", found.start())
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if not depth:
                return text[found.start():index + 1]
    raise ValueError("Unterminated source method")


PREFIX = r'''#import <Foundation/Foundation.h>
#include <stdio.h>
@interface UIScene : NSObject @end
@implementation UIScene @end
@interface UISceneSession : NSObject @end
@implementation UISceneSession @end
@interface LocalNotificationContent : NSObject
@property(nonatomic,strong) NSDictionary *userInfo;
@end
@implementation LocalNotificationContent @end
@interface LocalNotificationRequest : NSObject
@property(nonatomic,strong) LocalNotificationContent *content;
@end
@implementation LocalNotificationRequest @end
@interface LocalNotification : NSObject
@property(nonatomic,strong) LocalNotificationRequest *request;
@end
@implementation LocalNotification @end
@interface LocalNotificationResponse : NSObject
@property(nonatomic,strong) LocalNotification *notification;
@property(nonatomic,strong) NSString *actionIdentifier;
@end
@implementation LocalNotificationResponse @end
@interface UISceneConnectionOptions : NSObject
@property(nonatomic,strong) LocalNotificationResponse *notificationResponse;
@end
@implementation UISceneConnectionOptions @end
@protocol FlutterSceneLifeCycleDelegate <NSObject>
@optional
__PROTOCOL__
@end
@interface FLTFirebaseMessagingPlugin : NSObject <FlutterSceneLifeCycleDelegate> {
@public
  BOOL _sceneDidConnect;
  NSString *_notificationOpenedAppID;
  NSUInteger _setupCalls;
  NSDictionary *_observedNotification;
  NSString *_observedAction;
}
- (void)setupNotificationHandlingWithRemoteNotification:(NSDictionary *)info actionIdentifier:(NSString *)action;
@end
@implementation FLTFirebaseMessagingPlugin
- (void)setupNotificationHandlingWithRemoteNotification:(NSDictionary *)info actionIdentifier:(NSString *)action {
  _setupCalls++;
  _observedNotification = info;
  _observedAction = action;
}
__CALLBACK__
@end
@interface ProbeDelegate : NSObject <FlutterSceneLifeCycleDelegate>
@property(nonatomic) BOOL consume;
@property(nonatomic) NSUInteger calls;
@property(nonatomic,strong) UISceneConnectionOptions *seenOptions;
@end
@implementation ProbeDelegate
- (BOOL)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
  self.calls++;
  self.seenOptions = options;
  return self.consume;
}
@end
@interface NativeDispatch : NSObject {
  NSPointerArray *_delegates;
}
- (void)addDelegate:(NSObject<FlutterSceneLifeCycleDelegate> *)delegate;
__PROTOCOL__
@end
@implementation NativeDispatch
- (instancetype)init { if ((self = [super init])) _delegates = [NSPointerArray weakObjectsPointerArray]; return self; }
- (void)addDelegate:(NSObject<FlutterSceneLifeCycleDelegate> *)delegate { [_delegates addPointer:(__bridge void *)delegate]; }
__DISPATCH__
@end
static UISceneConnectionOptions *options(NSDictionary *info) {
  UISceneConnectionOptions *value = [UISceneConnectionOptions new];
  if (info) {
    value.notificationResponse = [LocalNotificationResponse new];
    value.notificationResponse.notification = [LocalNotification new];
    value.notificationResponse.notification.request = [LocalNotificationRequest new];
    value.notificationResponse.notification.request.content = [LocalNotificationContent new];
    value.notificationResponse.notification.request.content.userInfo = info;
    value.notificationResponse.actionIdentifier = @"tap";
  }
  return value;
}
static NSUInteger assertions = 0;
#define CHECK(condition, name) do { if (!(condition)) { fprintf(stderr, "FAIL: %s\n", name); return 2; } assertions++; } while (0)
int main(void) { @autoreleasepool {
  FLTFirebaseMessagingPlugin *plugin = [FLTFirebaseMessagingPlugin new];
  CHECK(![plugin scene:nil willConnectToSession:nil options:nil], "nil options are not consumed");
  CHECK(plugin->_sceneDidConnect && plugin->_setupCalls == 1 && !plugin->_observedNotification, "nil options preserve original scene/setup state");
  UISceneConnectionOptions *empty = options(nil);
  CHECK(![plugin scene:nil willConnectToSession:nil options:empty], "empty connection remains available");
  CHECK(plugin->_setupCalls == 2, "empty connection keeps upstream setup call");
  NSDictionary *otherInfo = @{@"other": @"local-notification"};
  UISceneConnectionOptions *other = options(otherInfo);
  CHECK(![plugin scene:nil willConnectToSession:nil options:other], "non-FCM notification remains available");
  CHECK(plugin->_observedNotification == otherInfo && [plugin->_observedAction isEqual:@"tap"] && !plugin->_notificationOpenedAppID, "non-FCM upstream notification/action state is unchanged");
  NSDictionary *fcmInfo = @{@"gcm.message_id": @"fcm-1", @"data": @"fixture"};
  UISceneConnectionOptions *fcm = options(fcmInfo);
  CHECK([plugin scene:nil willConnectToSession:nil options:fcm], "recognized FCM notification is consumed");
  CHECK([plugin->_notificationOpenedAppID isEqual:@"fcm-1"] && plugin->_observedNotification == fcmInfo && [plugin->_observedAction isEqual:@"tap"], "FCM identifier/action/setup stay upstream");
  CHECK(![plugin scene:nil willConnectToSession:nil options:nil], "later consumed connection remains false");
  CHECK([plugin->_notificationOpenedAppID isEqual:@"fcm-1"] && plugin->_setupCalls == 5 && !plugin->_observedNotification, "nil event preserves original stored message ID and setup call");
  NativeDispatch *dispatch = [NativeDispatch new];
  ProbeDelegate *after = [ProbeDelegate new];
  [dispatch addDelegate:plugin]; [dispatch addDelegate:after];
  CHECK([dispatch scene:nil willConnectToSession:nil options:fcm], "actual pinned dispatch aggregates FCM handling");
  CHECK(after.calls == 1 && !after.seenOptions, "actual pinned dispatch withholds consumed options from later plugin");
  CHECK(![dispatch scene:nil willConnectToSession:nil options:other], "actual pinned dispatch leaves non-FCM unhandled");
  CHECK(after.calls == 2 && after.seenOptions == other, "non-FCM options reach later plugin unchanged");
  CHECK(![dispatch scene:nil willConnectToSession:nil options:empty], "empty options remain unhandled by actual dispatch");
  CHECK(after.calls == 3 && after.seenOptions == empty, "empty options remain available to Flutter fallback/deep-link flow");
  NativeDispatch *already = [NativeDispatch new];
  ProbeDelegate *before = [ProbeDelegate new]; before.consume = YES;
  ProbeDelegate *last = [ProbeDelegate new];
  [already addDelegate:before]; [already addDelegate:plugin]; [already addDelegate:last];
  NSUInteger setup = plugin->_setupCalls;
  CHECK([already scene:nil willConnectToSession:nil options:fcm], "prior consumer remains authoritative");
  CHECK(before.seenOptions == fcm && plugin->_setupCalls == setup + 1 && !plugin->_observedNotification && last.calls == 1 && !last.seenOptions, "prior consumer causes genuine nil callback without duplicate notification processing");
  printf("{\"cases\":8,\"assertions\":%lu,\"status\":\"pass\"}\n", (unsigned long)assertions);
  return 0;
} }
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        raise ValueError("Native callback probe requires a fresh evidence directory")
    out.mkdir(parents=True)
    upstream = ROOT / "docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/source-snapshot/upstream-package" / METHOD
    current = ROOT / "third_party/firebase_messaging" / METHOD
    header = SDK / "engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterSceneLifeCycle.h"
    dispatch = SDK / "engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycle.mm"
    signature = r"- \((?:void|BOOL)\)scene:\(UIScene \*\)scene\s+willConnectToSession:"
    declaration = re.search(r"- \(BOOL\)scene:\(UIScene\*\)scene\s+willConnectToSession:\(UISceneSession\*\)session\s+options:\(nullable UISceneConnectionOptions\*\)connectionOptions;", header.read_text())
    if not declaration:
        raise ValueError("Pinned native scene protocol declaration changed")
    engine = method(dispatch.read_text(), r"- \(BOOL\)scene:\(UIScene\*\)scene\s+willConnectToSession:")
    commands = []
    env = {key: value for key, value in os.environ.items() if key in {"HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"}}
    env["DEVELOPER_DIR"] = XCODE

    def run(name, command):
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
        (out / (name + ".stdout")).write_bytes(result.stdout)
        (out / (name + ".stderr")).write_bytes(result.stderr)
        commands.append({"name": name, "command": command, "exit_code": result.returncode,
                         "stdout_sha256": sha(out / (name + ".stdout")), "stderr_sha256": sha(out / (name + ".stderr"))})
        return result

    source_hashes = {str(path): sha(path) for path in [upstream, current, header, dispatch, Path(__file__)]}
    for label, path in [("prior", upstream), ("current", current)]:
        text = PREFIX.replace("__PROTOCOL__", declaration[0]).replace("__CALLBACK__", method(path.read_text(), signature)).replace("__DISPATCH__", engine)
        source = out / (label + "-callback-dispatch.m")
        source.write_text(text)
        result = run(label + "-compile", ["/usr/bin/xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-O2", "-Werror=mismatched-return-types", "-Werror=return-type", "-framework", "Foundation", str(source), "-o", str(out / (label + "-probe"))])
        if label == "prior":
            if result.returncode == 0 or b"conflicting return type" not in result.stderr:
                raise ValueError("Original source must fail the actual protocol return-type gate")
        elif result.returncode:
            raise ValueError("Corrected native callback failed compilation")
    result = run("current-native-runtime", [str(out / "current-probe")])
    if result.returncode:
        raise ValueError("Corrected native callback/dispatch behavior failed")
    checks = json.loads(result.stdout)
    if checks != {"cases": 8, "assertions": 18, "status": "pass"}:
        raise ValueError("Native callback probe coverage changed")
    after = {path: sha(Path(path)) for path in source_hashes}
    report = {"status": "pass", "kind": "native_foundation_isolated_actual_callback_dispatch",
              "scope": "Exact source-derived plugin callback/protocol/engine dispatch compiled and executed on macOS Foundation stand-ins; not full Firebase SDK/iOS device/provider acceptance",
              "actual_cases": 8, "actual_assertions": 18, "prior_source_native_compile_rejected": True,
              "source_sha256_before": source_hashes, "source_sha256_after": after, "sources_unchanged": source_hashes == after,
              "commands": commands, "provider_calls": 0, "hosted_calls": 0, "database_calls": 0,
              "native_full_plugin_compile_accepted": False, "artifact_sha256": sha(out / "current-probe")}
    (out / "verification.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"cases": 8, "assertions": 18, "verification_sha256": sha(out / "verification.json")}))


if __name__ == "__main__":
    main()
