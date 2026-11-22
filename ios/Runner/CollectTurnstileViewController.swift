import UIKit
import WebKit

/// This isolated browser has no bearer or refresh credential. Only its own
/// main-frame challenge may return a candidate token to Flutter.
final class CollectTurnstileViewController: UIViewController,
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
    let cloudProject = "https://rrlduytparvsjfmegalh.supabase.co"
    let cloudAPIOrigins: Set<String> = [
      cloudProject,
      "https://collect.ikanisa.com",
      "https://admin.collect.ikanisa.com",
      "https://platform-admin.collect.ikanisa.com",
      "https://admin-supabase-qa.collect.ikanisa.com",
    ]
    guard origin(project) == cloudProject, let apiOrigin = origin(api),
      cloudAPIOrigins.contains(apiOrigin) else { return nil }
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
