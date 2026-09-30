import CryptoKit
import Security
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var snapshotChannel: FlutterMethodChannel?
  private let snapshotQueue = DispatchQueue(label: "collect.secure.snapshot")
  private let snapshotStore = CollectProtectedSnapshotStore()
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
    let secureChannel = FlutterMethodChannel(name: "collect/secure_snapshot",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    snapshotChannel = secureChannel
    secureChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "cache_unavailable", message: "Protected cache unavailable", details: nil)); return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      guard ["read", "write", "clear"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      self.snapshotQueue.async {
        do {
          let output: Any?
          switch call.method {
          case "read": output = try self.snapshotStore.read(owner: arguments["owner_id"] as? String ?? "")
          case "write":
            guard let value = arguments["value"] as? String else { throw CollectSnapshotFailure.invalid }
            try self.snapshotStore.write(owner: arguments["owner_id"] as? String ?? "", value: value)
            output = true
          default: try self.snapshotStore.clear(); output = true
          }
          DispatchQueue.main.async { result(output) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "cache_unavailable", message: "Protected cache temporarily unavailable", details: nil))
          }
        }
      }
    }
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


private enum CollectSnapshotFailure: Error { case invalid, unavailable }

/// File bytes are encrypted and excluded from backup; the key is accessible only
/// while this device is unlocked. Failure never replaces encryption with plaintext.
private final class CollectProtectedSnapshotStore {
  private let maximumBytes = 1024 * 1024
  private let service = (Bundle.main.bundleIdentifier ?? "app.cool.mobile") + ".snapshot.v5"
  private var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CollectProtectedSnapshot", isDirectory: true)
  }
  private func validate(_ owner: String) throws {
    guard owner.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil
      else { throw CollectSnapshotFailure.invalid }
  }
  private func path(_ owner: String) -> URL {
    let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(hash + ".enc")
  }
  private func associatedData(_ owner: String) -> Data { Data(("collect.snapshot.v5\0" + owner).utf8) }
  private func key(create: Bool) throws -> SymmetricKey {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "data-key",
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
    guard status == errSecItemNotFound, create else { throw CollectSnapshotFailure.unavailable }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CollectSnapshotFailure.unavailable }
    let data = Data(bytes)
    let insertion: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "data-key",
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecValueData as String: data]
    let added = SecItemAdd(insertion as CFDictionary, nil)
    if added == errSecDuplicateItem { return try key(create: false) }
    guard added == errSecSuccess else { throw CollectSnapshotFailure.unavailable }
    return SymmetricKey(data: data)
  }
  func read(owner: String) throws -> String? {
    try validate(owner)
    let url = path(owner)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: maximumBytes + 30) ?? Data()
    guard bytes.count >= 29, bytes.count <= maximumBytes + 29, bytes.first == 5 else { throw CollectSnapshotFailure.invalid }
    let sealed = try AES.GCM.SealedBox(combined: bytes.dropFirst())
    let data = try AES.GCM.open(sealed, using: key(create: false), authenticating: associatedData(owner))
    guard let value = String(data: data, encoding: .utf8) else { throw CollectSnapshotFailure.invalid }
    return value
  }
  func write(owner: String, value: String) throws {
    try validate(owner)
    let data = Data(value.utf8)
    guard data.count <= maximumBytes else { throw CollectSnapshotFailure.invalid }
    let sealed = try AES.GCM.seal(data, using: key(create: true), authenticating: associatedData(owner))
    guard let combined = sealed.combined else { throw CollectSnapshotFailure.unavailable }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    var dir = directory
    var resources = URLResourceValues(); resources.isExcludedFromBackup = true
    try dir.setResourceValues(resources)
    let destination = path(owner)
    try (Data([5]) + combined).write(to: destination, options: [.atomic, .completeFileProtection])
    for other in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where other != destination { try FileManager.default.removeItem(at: other) }
  }
  func clear() throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      try FileManager.default.removeItem(at: item)
    }
  }
}
