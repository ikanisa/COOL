// AppDelegate's actual private protected-store implementation is prepended by
// the host runner; no production keychain item or application directory is used.
private func rejected(_ body: () throws -> Void) throws {
  do { try body() } catch { return }
  throw NSError(domain: "Expected rejection", code: 1)
}
private func require(_ condition: @autoclosure () throws -> Bool) throws {
  if try !condition() { throw NSError(domain: "Check failed", code: 2) }
}
private let owner = "d1000000-0000-4000-8000-000000000001"
private let other = "d1000000-0000-4000-8000-000000000002"
private var passed = 0
private func test(_ name: String, _ body: (URL, @escaping (String, Bool) throws -> SymmetricKey) throws -> Void) throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("payment-help-store-test-" + UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  var keys: [String: SymmetricKey] = [:]
  let key: (String, Bool) throws -> SymmetricKey = { service, create in
    if let value = keys[service] { return value }
    guard create else { throw CollectSnapshotFailure.unavailable }
    let value = SymmetricKey(size: .bits256); keys[service] = value; return value
  }
  try body(root, key); passed += 1; print("PASS Swift store: " + name)
}
private func file(_ root: URL, _ purpose: String, _ user: String = owner) -> URL {
  let directory = purpose == "auth" ? "CollectProtectedAuthSession" : purpose == "payment_help" ? "CollectProtectedPaymentHelp" : "CollectProtectedSnapshot"
  let digest = SHA256.hash(data: Data(user.utf8)).map { String(format: "%02x", $0) }.joined()
  return root.appendingPathComponent(directory).appendingPathComponent(digest + ".enc")
}
try test("reconstruction, isolated finance/auth and stale owner clear") { root, key in
  let finance = CollectProtectedSnapshotStore(directoryRoot: root, keyProvider: key)
  let auth = CollectProtectedSnapshotStore(purpose: "auth", directoryRoot: root, keyProvider: key)
  let help = CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root, keyProvider: key)
  try finance.write(owner: owner, value: "retained finance"); try auth.write(owner: owner, value: "retained auth"); try help.write(owner: owner, value: "request")
  let originalFinance = try Data(contentsOf: file(root, "snapshot")), originalAuth = try Data(contentsOf: file(root, "auth"))
  try require(CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root, keyProvider: key).read(owner: owner) == "request")
  try help.write(owner: other, value: "new owner request"); try help.clear(owner: owner); try require(help.read(owner: other) == "new owner request")
  try help.clear(); try require(help.read(owner: other) == nil)
  try require(finance.read(owner: owner) == "retained finance"); try require(auth.read(owner: owner) == "retained auth")
  try require(Data(contentsOf: file(root, "snapshot")) == originalFinance); try require(Data(contentsOf: file(root, "auth")) == originalAuth)
}
try test("cross-purpose AAD rejects ciphertext even with a shared controlled key") { root, _ in
  let shared = SymmetricKey(size: .bits256), key: (String, Bool) throws -> SymmetricKey = { _, _ in shared }
  let help = CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root, keyProvider: key)
  try help.write(owner: owner, value: "request")
  for purpose in ["snapshot", "auth"] {
    let store = CollectProtectedSnapshotStore(purpose: purpose, directoryRoot: root, keyProvider: key)
    try store.write(owner: owner, value: "private " + purpose)
    let bytes = try Data(contentsOf: file(root, purpose)); try bytes.write(to: file(root, "payment_help"))
    try rejected { _ = try help.read(owner: owner) }; try require(Data(contentsOf: file(root, "payment_help")) == bytes)
    try require(store.read(owner: owner) == "private " + purpose)
  }
}
try test("wrong owner and tampered bytes fail without deletion") { root, key in
  let help = CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root, keyProvider: key)
  try help.write(owner: owner, value: "request"); let original = try Data(contentsOf: file(root, "payment_help"))
  try original.write(to: file(root, "payment_help", other)); try rejected { _ = try help.read(owner: other) }
  try require(Data(contentsOf: file(root, "payment_help", other)) == original)
  var corrupt = original; corrupt[corrupt.count - 1] ^= 1; try corrupt.write(to: file(root, "payment_help"))
  try rejected { _ = try help.read(owner: owner) }; try require(Data(contentsOf: file(root, "payment_help")) == corrupt)
}
try test("locked read does not create a key or replace recovery bytes") { root, key in
  try CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root, keyProvider: key).write(owner: owner, value: "request")
  let before = try Data(contentsOf: file(root, "payment_help")); var createRequested = false
  let unavailable = CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root) { _, create in
    createRequested = create; throw CollectSnapshotFailure.unavailable
  }
  try rejected { _ = try unavailable.read(owner: owner) }; try require(!createRequested)
  try require(Data(contentsOf: file(root, "payment_help")) == before)
}
try test("invalid owners and over-limit write preserve prior help") { root, key in
  let help = CollectProtectedSnapshotStore(purpose: "payment_help", directoryRoot: root, keyProvider: key)
  try help.write(owner: owner, value: "original"); let before = try Data(contentsOf: file(root, "payment_help"))
  try rejected { try help.clear(owner: "../owner") }; try rejected { try help.write(owner: owner, value: String(repeating: "x", count: 1024 * 1024 + 1)) }
  try require(Data(contentsOf: file(root, "payment_help")) == before)
}
print("Swift protected-store checks: \(passed) passed")
