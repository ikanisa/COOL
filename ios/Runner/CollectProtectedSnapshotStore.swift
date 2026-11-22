import CryptoKit
import Foundation
import Security

enum CollectSnapshotFailure: Error { case invalid, unavailable }

/// File bytes are encrypted and excluded from backup; the key is accessible only
/// while this device is unlocked. Failure never replaces encryption with plaintext.
final class CollectProtectedSnapshotStore {
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
