import CryptoKit
import Security
import Flutter
import UIKit
import UserNotifications
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var snapshotChannel: FlutterMethodChannel?
  private var authSessionChannel: FlutterMethodChannel?
  private var paymentHelpPendingChannel: FlutterMethodChannel?
  private var receiptSmsPendingChannel: FlutterMethodChannel?
  private let receiptSmsPendingStore = ReceiptSmsPendingStore()
  private let receiptSmsPendingQueue = DispatchQueue(label: "collect.receipt-sms.pending")
  private var turnstileChannel: FlutterMethodChannel?
  private var turnstileController: CollectTurnstileViewController?
  private let snapshotQueue = DispatchQueue(label: "collect.secure.snapshot")
  private let snapshotStore = CollectProtectedSnapshotStore()
  private let authSessionStore = CollectProtectedSnapshotStore(purpose: "auth")
  private let paymentHelpPendingStore = CollectProtectedSnapshotStore(purpose: "payment_help")
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
    let challengeChannel = FlutterMethodChannel(name: "collect/turnstile",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
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
    let paymentHelpChannel = FlutterMethodChannel(name: "collect/payment_help_pending",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    paymentHelpPendingChannel = paymentHelpChannel
    paymentHelpChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "payment_help_storage_unavailable", message: "Secure payment help recovery is unavailable", details: nil)); return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      guard ["read", "write", "clear"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      self.snapshotQueue.async {
        do {
          let output: Any?
          switch call.method {
          case "read": output = try self.paymentHelpPendingStore.read(owner: arguments["owner_id"] as? String ?? "")
          case "write":
            guard let value = arguments["value"] as? String else { throw CollectSnapshotFailure.invalid }
            try self.paymentHelpPendingStore.write(owner: arguments["owner_id"] as? String ?? "", value: value)
            output = true
          default:
            if arguments.keys.contains("owner_id"), !(arguments["owner_id"] is String) { throw CollectSnapshotFailure.invalid }
            try self.paymentHelpPendingStore.clear(owner: arguments["owner_id"] as? String)
            output = true
          }
          DispatchQueue.main.async { result(output) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "payment_help_storage_unavailable",
              message: "Secure payment help recovery is unavailable; retained requests were not discarded.", details: nil))
          }
        }
      }
    }
    let receiptChannel = FlutterMethodChannel(name: "collect/receipt_sms_pending",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    receiptSmsPendingChannel = receiptChannel
    receiptChannel.setMethodCallHandler { [weak self] call, result in
      guard let self, ["read", "claim", "claimWithdrawalFence", "complete", "supersede"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
      let arguments = call.arguments as? [String: Any] ?? [:]
      self.receiptSmsPendingQueue.async {
        do {
          let owner = arguments["owner_id"] as? String ?? "", group = arguments["collection_id"] as? String ?? ""
          let value: Any?
          switch call.method {
          case "read": value = try self.receiptSmsPendingStore.read(owner: owner, group: group)
          case "claim": value = try self.receiptSmsPendingStore.claim(owner: owner, group: group, value: arguments["request"])
          case "claimWithdrawalFence": value = try self.receiptSmsPendingStore.claim(owner: owner, group: group, value: arguments["request"], fence: true)
          case "complete": value = try self.receiptSmsPendingStore.complete(owner: owner, group: group, value: arguments["request"], head: arguments["decision_revision"])
          default: value = try self.receiptSmsPendingStore.supersede(owner: owner, group: group, values: arguments["known_requests"], head: arguments["decision_revision"])
          }
          DispatchQueue.main.async { result(value) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "receipt_sms_recovery_unavailable",
          message: "Secure receipt SMS recovery is unavailable; retained requests were not discarded.", details: nil)) } }
      }
    }
    let authChannel = FlutterMethodChannel(name: "collect/secure_auth_session",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    authSessionChannel = authChannel
    authChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "auth_storage_unavailable", message: "Protected sign-in storage unavailable", details: nil)); return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      guard ["read", "write", "clear"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      self.snapshotQueue.async {
        do {
          let output: Any?
          switch call.method {
          case "read": output = try self.authSessionStore.read(owner: arguments["owner_id"] as? String ?? "")
          case "write":
            guard let value = arguments["value"] as? String else { throw CollectSnapshotFailure.invalid }
            try self.authSessionStore.write(owner: arguments["owner_id"] as? String ?? "", value: value)
            output = true
          default: try self.authSessionStore.clear(); output = true
          }
          DispatchQueue.main.async { result(output) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "auth_storage_unavailable", message: "Protected sign-in storage temporarily unavailable", details: nil))
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


/// This isolated browser has no bearer or refresh credential. Only its own
/// main-frame challenge may return a candidate token to Flutter.
private final class CollectTurnstileViewController: UIViewController,
  WKNavigationDelegate, WKScriptMessageHandler, UIAdaptivePresentationControllerDelegate {
  let attemptId: String
  private let completion: (String?, String?) -> Void
  private let expectedURL: URL
  private var browser: WKWebView?
  private var deadline: DispatchWorkItem?
  private var completed = false
  private static func configuredEndpoint() -> (origin: String, path: String)? {
    let raw = Bundle.main.object(forInfoDictionaryKey: "CollectPublicDartDefines") as? String ?? ""
    var values: [String: String] = [:]
    if !raw.isEmpty && raw != "$(DART_DEFINES)" {
      for part in raw.split(separator: ",") {
        guard let bytes = Data(base64Encoded: String(part)), let text = String(data: bytes, encoding: .utf8),
          let separator = text.firstIndex(of: "=") else { return nil }
        let key = String(text[..<separator])
        guard values[key] == nil else { return nil }
        values[key] = String(text[text.index(after: separator)...])
      }
    }
    let backend = values["COLLECT_BACKEND"] ?? "supabase"
    if backend == "cloudflare" { return ("https://api.collect.ikanisa.com", "/v1/security/challenge") }
    guard backend == "supabase", let project = values["SUPABASE_URL"],
      let key = values["SUPABASE_PUBLISHABLE_KEY"],
      key.range(of: "^sb_publishable_[A-Za-z0-9_-]{10,300}$", options: .regularExpression) != nil else { return nil }
    let api = values["SUPABASE_API_URL"].flatMap { $0.isEmpty ? nil : $0 } ?? project
    func origin(_ value: String) -> String? {
      guard let url = URLComponents(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
        url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
        url.port == nil || url.port == 443, ["", "/"].contains(url.path) else { return nil }
      return "https://\(host.lowercased())"
    }
    guard origin(project) != nil, let apiOrigin = origin(api) else { return nil }
    return (apiOrigin, "/functions/v1/collect-api/v1/security/challenge")
  }
  static func acceptsRouting(_ arguments: [String: Any]) -> Bool {
    guard let endpoint = configuredEndpoint() else { return false }
    if Set(arguments.keys) == Set(["attempt_id"]) {
      return endpoint.path == "/v1/security/challenge"
    }
    return Set(arguments.keys) == Set(["attempt_id", "backend_origin", "backend_path"]) &&
      arguments["backend_origin"] as? String == endpoint.origin && arguments["backend_path"] as? String == endpoint.path
  }
  private static let envelopeType = "collect.turnstile.v1"

  init(attemptId: String, completion: @escaping (String?, String?) -> Void) {
    self.attemptId = attemptId
    self.completion = completion
    let endpoint = Self.configuredEndpoint()!
    var url = URLComponents(string: endpoint.origin + endpoint.path)!
    url.queryItems = [URLQueryItem(name: "attempt_id", value: attemptId),
      URLQueryItem(name: "parent_origin", value: endpoint.origin),
      URLQueryItem(name: "theme", value: "auto")]
    expectedURL = url.url!
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { return nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.accessibilityViewIsModal = true
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.userContentController.add(self, name: "CollectTurnstile")
    config.userContentController.addUserScript(WKUserScript(source: """
      window.CollectTurnstile = Object.freeze({postMessage: function(value) {
        if (typeof value === 'string' && value.length <= 4096) {
          window.webkit.messageHandlers.CollectTurnstile.postMessage(value);
        }
      }});
      """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.translatesAutoresizingMaskIntoConstraints = false
    web.accessibilityLabel = "Collect security verification"
    browser = web
    view.addSubview(web)
    let cancel = UIButton(type: .system)
    cancel.setTitle("Cancel", for: .normal)
    cancel.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
    cancel.titleLabel?.adjustsFontForContentSizeCategory = true
    cancel.translatesAutoresizingMaskIntoConstraints = false
    cancel.addTarget(self, action: #selector(cancelChallenge), for: .touchUpInside)
    view.addSubview(cancel)
    NSLayoutConstraint.activate([
      web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      web.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      web.bottomAnchor.constraint(equalTo: cancel.topAnchor, constant: -12),
      cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      cancel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])
    let timeout = DispatchWorkItem { [weak self] in
      self?.finish(envelope: nil, error: "captcha_unavailable")
    }
    deadline = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
    web.load(URLRequest(url: expectedURL))
  }

  @objc private func cancelChallenge() { finish(envelope: nil, error: "captcha_cancelled") }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(envelope: nil, error: "captcha_cancelled")
  }

  private func allowed(_ url: URL, main: Bool) -> Bool {
    if main { return url == expectedURL }
    if ["about:blank", "about:srcdoc"].contains(url.absoluteString) { return true }
    guard url.scheme == "https", url.user == nil, url.password == nil,
      url.port == nil || url.port == 443 else { return false }
    return url == expectedURL || url.host == "challenges.cloudflare.com"
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let frame = navigationAction.targetFrame, let url = navigationAction.request.url,
      allowed(url, main: frame.isMainFrame) else {
      decisionHandler(.cancel)
      if navigationAction.targetFrame?.isMainFrame == true {
        finish(envelope: nil, error: "captcha_unavailable")
      }
      return
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if navigationResponse.isForMainFrame,
       let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
      decisionHandler(.cancel); finish(envelope: nil, error: "captcha_unavailable"); return
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(envelope: nil, error: "captcha_unavailable")
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(envelope: nil, error: "captcha_unavailable")
  }
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    let origin = message.frameInfo.securityOrigin
    guard !completed, message.name == "CollectTurnstile", message.frameInfo.isMainFrame,
      origin.protocol == "https", origin.host == expectedURL.host, [0,443].contains(origin.port),
      message.frameInfo.request.url == expectedURL, browser?.url == expectedURL,
      let raw = message.body as? String, raw.utf8.count <= 4096,
      let bytes = raw.data(using: .utf8) else { return }
    guard let value = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
      Set(value.keys) == Set(["type", "attempt_id", "token"]),
      value["type"] as? String == Self.envelopeType, value["attempt_id"] as? String == attemptId,
      let token = value["token"] as? String, !token.isEmpty, token.count <= 2048,
      token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
      finish(envelope: nil, error: "captcha_unavailable"); return
    }
    finish(envelope: raw, error: nil)
  }

  func finish(envelope: String?, error: String?) {
    guard !completed else { return }
    completed = true
    deadline?.cancel(); deadline = nil
    browser?.configuration.userContentController.removeScriptMessageHandler(forName: "CollectTurnstile")
    browser?.stopLoading(); browser?.navigationDelegate = nil
    let done = { self.completion(envelope, error) }
    if presentingViewController != nil { dismiss(animated: true, completion: done) } else { done() }
  }
}

private enum CollectSnapshotFailure: Error { case invalid, unavailable }

/// File bytes are encrypted and excluded from backup; the key is accessible only
/// while this device is unlocked. Failure never replaces encryption with plaintext.
private final class CollectProtectedSnapshotStore {
  private let maximumBytes = 1024 * 1024
  private let purpose: String
  private let directoryRoot: URL?
  private let keyProvider: ((String, Bool) throws -> SymmetricKey)?
  init(purpose: String = "snapshot", directoryRoot: URL? = nil,
       keyProvider: ((String, Bool) throws -> SymmetricKey)? = nil) {
    precondition(["snapshot", "auth", "payment_help"].contains(purpose))
    self.purpose = purpose; self.directoryRoot = directoryRoot; self.keyProvider = keyProvider
  }
  private var serviceSuffix: String {
    switch purpose { case "auth": return ".auth-session.v1"; case "payment_help": return ".payment-help.v1"; default: return ".snapshot.v5" }
  }
  private var service: String { (Bundle.main.bundleIdentifier ?? "app.cool.mobile") +
    serviceSuffix }
  private var directory: URL {
    let name: String
    switch purpose { case "auth": name = "CollectProtectedAuthSession"; case "payment_help": name = "CollectProtectedPaymentHelp"; default: name = "CollectProtectedSnapshot" }
    return (directoryRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
      .appendingPathComponent(name, isDirectory: true)
  }
  private func validate(_ owner: String) throws {
    guard owner.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil
      else { throw CollectSnapshotFailure.invalid }
  }
  private func path(_ owner: String) -> URL {
    let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(hash + ".enc")
  }
  private func associatedData(_ owner: String) -> Data {
    Data(("collect" + serviceSuffix + "\0" + owner).utf8)
  }
  private func key(create: Bool) throws -> SymmetricKey {
    if let keyProvider { return try keyProvider(service, create) }
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
      where other.lastPathComponent != destination.lastPathComponent { try FileManager.default.removeItem(at: other) }
  }
  func clear(owner: String? = nil) throws {
    if let owner {
      try validate(owner)
      let destination = path(owner)
      if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
      return
    }
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      try FileManager.default.removeItem(at: item)
    }
  }
}
