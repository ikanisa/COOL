import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let protectedChannels = MemberProtectedChannels()
  private var turnstileChannel: FlutterMethodChannel?
  private var turnstileController: CollectTurnstileViewController?
  private let notificationChannelName = "app.cool.mobile/notifications"
  private var notificationChannel: FlutterMethodChannel?
  private var remoteDeviceToken: String?
  private var initialNotification: [AnyHashable: Any]?
  private var notificationOwner: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    initialNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any]
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let challengeChannel = FlutterMethodChannel(name: "collect/turnstile",
      binaryMessenger: messenger)
    turnstileChannel = challengeChannel
    challengeChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "captcha_unavailable", message: "Security verification unavailable", details: nil)); return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      if call.method == "cancel" {
        if let id = arguments["attempt_id"] as? String, self.turnstileController?.attemptId == id {
          self.turnstileController?.finish(envelope: nil, error: "captcha_cancelled")
        }
        result(nil); return
      }
      guard call.method == "acquire" else { result(FlutterMethodNotImplemented); return }
      guard CollectTurnstileViewController.acceptsRouting(arguments), let id = arguments["attempt_id"] as? String,
        id.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil,
        self.turnstileController == nil else {
        result(FlutterError(code: "captcha_unavailable", message: "Security verification unavailable", details: nil)); return
      }
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      guard let root = scenes.filter({ $0.activationState == .foregroundActive })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController,
        root.presentedViewController == nil else {
        result(FlutterError(code: "captcha_unavailable", message: "Security verification unavailable", details: nil)); return
      }
      let controller = CollectTurnstileViewController(attemptId: id) { [weak self] envelope, error in
        self?.turnstileController = nil
        if let error {
          result(FlutterError(code: error, message: "Security verification could not finish", details: nil))
        } else { result(envelope) }
      }
      self.turnstileController = controller
      controller.modalPresentationStyle = .pageSheet
      root.present(controller, animated: true) {
        controller.presentationController?.delegate = controller
      }
    }
    protectedChannels.register(with: messenger)
    let channel = FlutterMethodChannel(
      name: notificationChannelName,
      binaryMessenger: messenger
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
      case "setNotificationOwner":
        let rawOwner = call.arguments as? String
        self.notificationOwner = rawOwner?.range(
          of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
          options: .regularExpression
        ) != nil ? rawOwner : nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        result(nil)
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
    if notification.request.trigger is UNPushNotificationTrigger {
      // Dart checks the live Auth identity again and displays generic text.
      // Never present remote provider text while the app is in the foreground.
      let payload = notification.request.content.userInfo
      if isCurrentNotification(payload) {
        notificationChannel?.invokeMethod("notificationForeground", arguments: payload)
      }
      completionHandler([])
    } else {
      completionHandler([.banner, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.trigger is UNPushNotificationTrigger &&
        !isCurrentNotification(response.notification.request.content.userInfo) {
      completionHandler()
      return
    }
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

  private func isCurrentNotification(_ payload: [AnyHashable: Any]) -> Bool {
    guard let owner = notificationOwner,
          payload["collect_push_version"] as? String == "2",
          payload["recipient_id"] as? String == owner else { return false }
    return true
  }
}
