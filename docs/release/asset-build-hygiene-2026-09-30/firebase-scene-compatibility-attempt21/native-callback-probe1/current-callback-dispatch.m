#import <Foundation/Foundation.h>
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
- (BOOL)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(nullable UISceneConnectionOptions*)connectionOptions;
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
- (BOOL)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions {
  // Handle launch notification if present
  // With scene delegates, the notification can be in notificationResponse if user tapped it
  _sceneDidConnect = YES;

  NSDictionary *remoteNotification = nil;
  NSString *actionIdentifier = nil;
  if (connectionOptions.notificationResponse != nil) {
    // User tapped the notification.
    remoteNotification =
        connectionOptions.notificationResponse.notification.request.content.userInfo;
    actionIdentifier = connectionOptions.notificationResponse.actionIdentifier;
    _notificationOpenedAppID = remoteNotification[@"gcm.message_id"];
  }

  [self setupNotificationHandlingWithRemoteNotification:remoteNotification
                                       actionIdentifier:actionIdentifier];
  // Consume only an FCM notification, matching the existing application delegate.
  // Empty/non-FCM options remain available for other plugins and Flutter deep links.
  return remoteNotification[@"gcm.message_id"] != nil;
}
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
- (BOOL)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(nullable UISceneConnectionOptions*)connectionOptions;
@end
@implementation NativeDispatch
- (instancetype)init { if ((self = [super init])) _delegates = [NSPointerArray weakObjectsPointerArray]; return self; }
- (void)addDelegate:(NSObject<FlutterSceneLifeCycleDelegate> *)delegate { [_delegates addPointer:(__bridge void *)delegate]; }
- (BOOL)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  BOOL handledByPlugin = NO;
  for (NSObject<FlutterSceneLifeCycleDelegate>* delegate in _delegates.allObjects) {
    if ([delegate respondsToSelector:_cmd]) {
      // If this event has already been consumed by a plugin, send the event with nil options.
      // Only allow one plugin to process the connection options.
      if ([delegate scene:scene
              willConnectToSession:session
                           options:(handledByPlugin ? nil : connectionOptions)]) {
        handledByPlugin = YES;
      }
    }
  }
  return handledByPlugin;
}
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
