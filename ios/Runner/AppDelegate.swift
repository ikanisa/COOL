import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let notificationChannelName = "app.cool.mobile/notifications"
  private var notificationChannel: FlutterMethodChannel?
  private var remoteDeviceToken: String?
  private var initialNotification: [AnyHashable: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    initialNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any]
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: notificationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    notificationChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Notification bridge unavailable", details: nil))
        return
      }
      switch call.method {
      case "requestRemoteRegistration":
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(self.remoteDeviceToken)
      case "getInitialNotification":
        result(self.initialNotification)
        self.initialNotification = nil
      case "getRemoteEnvironment":
        result(Bundle.main.object(forInfoDictionaryKey: "CollectAPNSEnvironment") as? String)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    if let token = remoteDeviceToken {
      channel.invokeMethod("remoteToken", arguments: token)
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    remoteDeviceToken = token
    notificationChannel?.invokeMethod("remoteToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
    notificationChannel?.invokeMethod(
      "remoteRegistrationError",
      arguments: ["code": (error as NSError).code]
    )
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    notificationChannel?.invokeMethod(
      "notificationTap",
      arguments: response.notification.request.content.userInfo
    )
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }
}
