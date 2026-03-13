import Flutter
import Firebase
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func firebaseOptions(for bundleId: String) -> FirebaseOptions? {
    let options: FirebaseOptions

    switch bundleId {
    case "app.cool.mobile":
      options = FirebaseOptions(
        googleAppID: "1:1074154147498:ios:97b9701b34e0dddedc4ad3",
        gcmSenderID: "1074154147498"
      )
      options.apiKey = "AIzaSyC3wczTXHP3fkryFydOTu6RIbxZ5vRUbg0"
      options.projectID = "gen-lang-client-0172279957"
      options.storageBucket = "gen-lang-client-0172279957.firebasestorage.app"
      options.bundleID = "app.cool.mobile"
      return options
    case "app.cool.mobile.staging":
      options = FirebaseOptions(
        googleAppID: "1:1074154147498:ios:59411d4546071204dc4ad3",
        gcmSenderID: "1074154147498"
      )
      options.apiKey = "AIzaSyC3wczTXHP3fkryFydOTu6RIbxZ5vRUbg0"
      options.projectID = "gen-lang-client-0172279957"
      options.storageBucket = "gen-lang-client-0172279957.firebasestorage.app"
      options.bundleID = "app.cool.mobile.staging"
      return options
    default:
      return nil
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil,
      let bundleId = Bundle.main.bundleIdentifier,
      let options = firebaseOptions(for: bundleId) {
      FirebaseApp.configure(options: options)
    }

    // Google Maps (optional API key from Info.plist)
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      GMSServices.provideAPIKey(apiKey)
    }

    GeneratedPluginRegistrant.register(with: self)

    // APNs registration for FCM on iOS
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
