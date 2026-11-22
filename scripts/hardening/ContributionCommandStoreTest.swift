import Foundation
import CryptoKit
import Darwin

// Compile with the actual new Runner cipher/store. Every path and key is test-only.
@main struct ContributionCommandStoreTest {
  static let a = String(repeating: "a", count: 64), b = String(repeating: "b", count: 64)
  static let fixtureKey = SymmetricKey(data: Data(repeating: 74, count: 32))
  static func key(_ service: String, _ create: Bool) throws -> SymmetricKey {
    guard service.hasSuffix(".contribution-commands.v1") else { throw ContributionCommandFailure.invalid }; return fixtureKey
  }
  static func require(_ condition: @autoclosure () throws -> Bool) throws {
    if try !condition() { throw NSError(domain: "Contribution native test", code: 1) }
  }
  static func rejected(_ body: () throws -> Void) throws {
    do { try body() } catch { return }; throw NSError(domain: "Expected rejection", code: 2)
  }
  static func folder(_ root: URL) -> URL { root.appendingPathComponent("CollectContributionCommandsV1") }
  static func file(_ root: URL, _ partition: String = a) -> URL { folder(root).appendingPathComponent(partition + ".enc") }
  static func ownedRoot(_ path: String) throws -> URL {
    let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard root.lastPathComponent.hasPrefix("collect-contribution-native-test-"), root != URL(fileURLWithPath: "/") else { throw ContributionCommandFailure.invalid }
    return root
  }
  static func main() throws {
    if CommandLine.arguments.count == 6, CommandLine.arguments[1] == "--claim" {
      let root = try ownedRoot(CommandLine.arguments[2]), partition = CommandLine.arguments[3]
      let gate = URL(fileURLWithPath: CommandLine.arguments[4]); let deadline = ProcessInfo.processInfo.systemUptime + 8
      let ready = URL(fileURLWithPath: CommandLine.arguments[5]).standardizedFileURL
      guard ready.deletingLastPathComponent() == root, ready.lastPathComponent.hasPrefix("ready-") else { throw ContributionCommandFailure.invalid }
      try Data([1]).write(to: ready); print("READY"); fflush(stdout)
      while !FileManager.default.fileExists(atPath: gate.path) {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw ContributionCommandFailure.busy }; usleep(10000)
      }
      let result = try ContributionCommandStore(directoryRoot: root, keyProvider: key)
        .compareAndSet(partition: partition, expected: NSNumber(value: 0), payload: "dispatchPossible")
      print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!); return
    }
    guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--root" else { throw ContributionCommandFailure.invalid }
    // Foundation's temporaryDirectory may ignore TMPDIR. The coordinator passes
    // an exact fresh fixture root inside its admitted external APFS boundary.
    let root = try ownedRoot(CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    var count = 0
    func test(_ name: String, _ body: (URL) throws -> Void) throws {
      let scope = root.appendingPathComponent("collect-contribution-native-test-" + UUID().uuidString)
      try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: false)
      try body(scope); count += 1; print("PASS native contribution: " + name); fflush(stdout)
    }
    try test("reconstruction, CAS conflict and multi-owner retention") { root in
      let store = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      try require(store.read(partition: a)["revision"] as? Int64 == 0)
      try require(store.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "original")["committed"] as? Bool == true)
      let retained = try Data(contentsOf: file(root))
      _ = try store.compareAndSet(partition: b, expected: NSNumber(value: 0), payload: "second owner")
      let reconstructed = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      try require(reconstructed.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "new key")["committed"] as? Bool == false)
      try require(reconstructed.read(partition: b)["payload"] as? String == "second owner")
      try require(Data(contentsOf: file(root)) == retained)
    }
    try test("wrong owner, tampering and malformed staging preserve encrypted bytes") { root in
      let store = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      _ = try store.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "original")
      let original = try Data(contentsOf: file(root)); try original.write(to: file(root, b))
      try rejected { _ = try store.read(partition: b) }; try require(Data(contentsOf: file(root, b)) == original)
      var corrupt = original; corrupt[corrupt.count - 1] ^= 1; try corrupt.write(to: file(root))
      try rejected { _ = try store.read(partition: a) }; try require(Data(contentsOf: file(root)) == corrupt)
      try original.write(to: file(root))
      try Data([1, 2, 3]).write(to: file(root).appendingPathExtension("new"))
      try rejected { _ = try store.read(partition: a) }
      try rejected { _ = try store.compareAndSet(partition: String(repeating: "c", count: 64), expected: NSNumber(value: 0), payload: "new request") }
      try require(Data(contentsOf: file(root)) == original)
    }
    try test("purpose AAD and safe revision envelope are strict") { _ in
      let cipher = ContributionCommandCipher(key: { _ in fixtureKey })
      let snapshot = try ContributionCommandSnapshot(partition: a, revision: ContributionCommandCipher.maxRevision, payload: "x")
      try require(cipher.decrypt(a, cipher.encrypt(snapshot)) == snapshot)
      try rejected { _ = try ContributionCommandSnapshot(partition: a, revision: 0, payload: "x") }
      try rejected { _ = try ContributionCommandSnapshot(partition: a, revision: ContributionCommandCipher.maxRevision + 1, payload: "x") }
      let bytes = Data([0, 0, 0, 0, 0, 0, 0, 1, 120])
      let foreign = try AES.GCM.seal(bytes, using: fixtureKey, authenticating: Data(("collect.payment-help.v1\0" + a).utf8))
      try rejected { _ = try cipher.decrypt(a, Data([1]) + foreign.combined!) }
    }
    try test("lost acknowledgement after promotion is retained without a second claim") { root in
      var encrypted = false
      let ambiguous = ContributionCommandStore(directoryRoot: root) { _, create in
        if create { encrypted = true; return fixtureKey }
        if encrypted { throw ContributionCommandFailure.unavailable }; return fixtureKey
      }
      try rejected { _ = try ambiguous.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "dispatchPossible") }
      let store = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      try require(store.read(partition: a)["payload"] as? String == "dispatchPossible")
      try require(store.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "replacement")["committed"] as? Bool == false)
    }
    try test("missing key and invalid payload/revision never become absence") { root in
      let store = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      _ = try store.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "retained")
      let before = try Data(contentsOf: file(root))
      let locked = ContributionCommandStore(directoryRoot: root) { _, _ in throw ContributionCommandFailure.unavailable }
      try rejected { _ = try locked.read(partition: a) }; try rejected { _ = try locked.read(partition: b) }
      for invalid: Any in [true, 1.5, -1, NSNumber(value: ContributionCommandCipher.maxRevision)] {
        try rejected { _ = try store.compareAndSet(partition: a, expected: invalid, payload: "changed") }
      }
      try rejected { _ = try store.compareAndSet(partition: a, expected: NSNumber(value: 1), payload: "") }
      try rejected { _ = try store.compareAndSet(partition: a, expected: NSNumber(value: 1), payload: String(repeating: "é", count: ContributionCommandCipher.maxPayloadBytes / 2 + 1)) }
      try require(Data(contentsOf: file(root)) == before)
    }
    try test("partition capacity refuses without owner eviction") { root in
      let store = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      for value in 0..<64 {
        _ = try store.compareAndSet(partition: String(format: "%064x", value), expected: NSNumber(value: 0), payload: "retained")
      }
      let before = try Data(contentsOf: file(root, String(format: "%064x", 0)))
      try rejected { _ = try store.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: "new owner") }
      try require(Data(contentsOf: file(root, String(format: "%064x", 0))) == before)
      try require(FileManager.default.contentsOfDirectory(atPath: folder(root).path).filter { $0.hasSuffix(".enc") }.count == 64)
    }
    try test("aggregate ciphertext capacity refuses without overwriting history") { root in
      let store = ContributionCommandStore(directoryRoot: root, keyProvider: key)
      let payload = String(repeating: "x", count: ContributionCommandCipher.maxPayloadBytes)
      for value in 0..<15 {
        _ = try store.compareAndSet(partition: String(format: "%064x", value), expected: NSNumber(value: 0), payload: payload)
      }
      try rejected { _ = try store.compareAndSet(partition: a, expected: NSNumber(value: 0), payload: payload) }
      try require(store.read(partition: String(format: "%064x", 0))["payload"] as? String == payload)
      try require(store.read(partition: a)["revision"] as? Int64 == 0)
    }
    try test("independent processes admit exactly one atomic claim") { root in
      _ = try ContributionCommandStore(directoryRoot: root, keyProvider: key).read(partition: a)
      let gate = root.appendingPathComponent("begin")
      var children = [(Process, Pipe)]()
      // Every owned child is reaped on success and on all failure paths.
      defer {
        if !FileManager.default.fileExists(atPath: gate.path) { try? Data([1]).write(to: gate) }
        let grace = ProcessInfo.processInfo.systemUptime + 3
        while children.contains(where: { $0.0.isRunning }) && ProcessInfo.processInfo.systemUptime < grace { usleep(10000) }
        for (child, _) in children where child.isRunning { child.terminate() }
        let stopped = ProcessInfo.processInfo.systemUptime + 1
        while children.contains(where: { $0.0.isRunning }) && ProcessInfo.processInfo.systemUptime < stopped { usleep(10000) }
        for (child, _) in children where child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
        for (child, _) in children { child.waitUntilExit() }
      }
      var readyFiles = [URL]()
      for index in 0..<8 {
        let child = Process(), pipe = Pipe()
        let ready = root.appendingPathComponent("ready-\(index)"); readyFiles.append(ready)
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["--claim", root.path, a, gate.path, ready.path]
        child.standardOutput = pipe; child.standardError = FileHandle.standardError; try child.run(); children.append((child, pipe))
      }
      let readyDeadline = ProcessInfo.processInfo.systemUptime + 6
      while !readyFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
        guard children.allSatisfy({ $0.0.isRunning }), ProcessInfo.processInfo.systemUptime < readyDeadline else { throw ContributionCommandFailure.busy }
        usleep(10000)
      }
      try Data([1]).write(to: gate)
      let exitDeadline = ProcessInfo.processInfo.systemUptime + 8
      while children.contains(where: { $0.0.isRunning }) {
        guard ProcessInfo.processInfo.systemUptime < exitDeadline else { throw ContributionCommandFailure.busy }; usleep(10000)
      }
      var winners = 0
      for (child, pipe) in children {
        child.waitUntilExit(); try require(child.terminationStatus == 0)
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        guard let last = output.split(separator: "\n").last,
          let result = try JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any] else { throw ContributionCommandFailure.invalid }
        if result["committed"] as? Bool == true { winners += 1 }
      }
      try require(winners == 1)
      try require(ContributionCommandStore(directoryRoot: root, keyProvider: key).read(partition: a)["revision"] as? Int64 == 1)
    }
    print("Native contribution store checks: \(count) passed; fixture root \(root.path)"); fflush(stdout)
  }
}
