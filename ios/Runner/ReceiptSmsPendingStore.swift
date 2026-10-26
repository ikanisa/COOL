import Foundation
import CryptoKit
import Security
import Darwin

// A separate device-only journal. No expiry, silent repair, account replacement,
// credential, phone or message storage; it is never a server authorization.
final class ReceiptSmsPendingStore {
  private static let lock = NSLock()
  private static let maximum = 8 + 64 * 166
  private let manager = FileManager.default
  private var directory: URL {
    manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .resolvingSymlinksInPath().appendingPathComponent("CollectReceiptSmsPendingV1", isDirectory: true)
  }
  private var service: String { (Bundle.main.bundleIdentifier ?? "app.cool.mobile") + ".receipt-sms-pending.v1" }
  private enum Failure: Error { case invalid, unavailable, capacity }
  private struct Record: Equatable {
    let owner: String, session: String, group: String, request: String
    let revision: Int, decisionRevision: Int64, choice: Bool
    var wire: [String: Any] { ["schema_version": 2, "user_id": owner, "session_id": session,
      "collection_id": group, "request_id": request, "expected_revision": revision, "expected_decision_revision": decisionRevision, "opt_in": choice] }
  }
  private func uuid(_ value: String) throws -> String {
    guard value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil else { throw Failure.invalid }
    return value
  }
  private func record(_ value: Any?) throws -> Record {
    guard let row = value as? [String: Any], Set(row.keys) == Set(["schema_version", "user_id", "session_id", "collection_id", "request_id", "expected_revision", "expected_decision_revision", "opt_in"]),
      let version = row["schema_version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 2, String(cString: version.objCType) != "d", String(cString: version.objCType) != "f",
      let revision = row["expected_revision"] as? NSNumber, CFGetTypeID(revision) != CFBooleanGetTypeID(),
      revision.doubleValue >= 0, revision.doubleValue <= 999999998, revision.doubleValue.rounded(.towardZero) == revision.doubleValue,
      String(cString: revision.objCType) != "d", String(cString: revision.objCType) != "f",
      let decision = row["expected_decision_revision"] as? NSNumber, CFGetTypeID(decision) != CFBooleanGetTypeID(),
      String(cString: decision.objCType) != "d", String(cString: decision.objCType) != "f",
      decision.int64Value >= 0, decision.int64Value <= 9007199254740990,
      let choice = row["opt_in"] as? NSNumber, CFGetTypeID(choice) == CFBooleanGetTypeID(),
      let owner = row["user_id"] as? String, let session = row["session_id"] as? String,
      let group = row["collection_id"] as? String, let request = row["request_id"] as? String else { throw Failure.invalid }
    return Record(owner: try uuid(owner), session: try uuid(session), group: try uuid(group), request: try uuid(request), revision: revision.intValue, decisionRevision: decision.int64Value, choice: choice.boolValue)
  }
  private func path(_ owner: String) -> URL {
    let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(hash + ".enc")
  }
  private func checkFile(_ url: URL, directory isDirectory: Bool = false) throws {
    let attributes: [FileAttributeKey: Any]
    do { attributes = try manager.attributesOfItem(atPath: url.path) }
    catch let error as NSError {
      if error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return }
      throw error
    }
    let type = attributes[.type] as? FileAttributeType
    guard type == (isDirectory ? .typeDirectory : .typeRegular) else { throw Failure.invalid }
  }
  private func key(create: Bool) throws -> SymmetricKey {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "data-key", kSecReturnData as String: true,
      kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var output: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &output)
    if status == errSecSuccess, let row = output as? [String: Any], let bytes = row[kSecValueData as String] as? Data,
      bytes.count == 32, (row[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String) { return SymmetricKey(data: bytes) }
    guard status == errSecItemNotFound, create else { throw Failure.unavailable }
    if manager.fileExists(atPath: directory.path), !(try manager.contentsOfDirectory(atPath: directory.path)).isEmpty { throw Failure.unavailable }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.unavailable }
    let insertion: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "data-key", kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecValueData as String: Data(bytes)]
    let added = SecItemAdd(insertion as CFDictionary, nil)
    if added == errSecDuplicateItem { return try key(create: false) }
    guard added == errSecSuccess else { throw Failure.unavailable }; return SymmetricKey(data: Data(bytes))
  }
  private func aad(_ owner: String) -> Data { Data(("collect.receipt-sms-pending.v1\0" + owner).utf8) }
  private struct Superseded {
    let request: Record, observedHead: Int64
    var wire: [String: Any] { request.wire.merging(["superseded_by_decision_revision": observedHead]) { _, new in new } }
  }
  private struct Journal {
    var pending = [Record](), superseded = [Superseded]()
    func wire(_ group: String) -> [String: Any] { ["schema_version": 2,
      "pending": pending.filter { $0.group == group }.map { $0.wire },
      "superseded": superseded.filter { $0.request.group == group }.map { $0.wire }] }
  }
  private func decisionHead(_ value: Any?, expected: Bool = false) throws -> Int64 {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      String(cString: number.objCType) != "d", String(cString: number.objCType) != "f",
      number.int64Value >= 0, number.int64Value <= (expected ? 9007199254740990 : 9007199254740991) else { throw Failure.invalid }
    return number.int64Value
  }
  private func validate(_ owner: String, _ journal: Journal) throws {
    _ = try uuid(owner)
    let all = journal.pending + journal.superseded.map { $0.request }
    guard journal.pending.count <= 32, journal.superseded.count <= 32,
      all.allSatisfy({ $0.owner == owner }), Set(all.map { $0.request }).count == all.count else { throw Failure.capacity }
    for row in all { _ = try uuid(row.owner); _ = try uuid(row.session); _ = try uuid(row.group); _ = try uuid(row.request)
      guard row.revision >= 0, row.revision <= 999999998, row.decisionRevision >= 0, row.decisionRevision <= 9007199254740990 else { throw Failure.invalid } }
    let groups = Dictionary(grouping: journal.pending, by: { $0.group })
    var reserved = 0
    for rows in groups.values {
      guard Set(rows.map { $0.session }).count == rows.count, rows.filter({ $0.choice }).count <= 1 else { throw Failure.invalid }
      if rows.count > 1 { reserved += rows.count }
    }
    guard journal.superseded.count + reserved <= 32 else { throw Failure.capacity }
    for old in journal.superseded {
      guard old.observedHead > old.request.decisionRevision, old.observedHead <= 9007199254740991 else { throw Failure.invalid }
    }
  }
  private func encode(_ owner: String, _ journal: Journal) throws -> Data {
    try validate(owner, journal)
    var rows = journal.pending.map { (kind: UInt8(0), row: $0, head: Int64(0)) }
    rows += journal.superseded.map { (kind: UInt8(1), row: $0.request, head: $0.observedHead) }
    rows.sort {
      if $0.row.group != $1.row.group { return $0.row.group < $1.row.group }
      if $0.kind != $1.kind { return $0.kind < $1.kind }
      return $0.row.request < $1.row.request
    }
    var bytes = Data([0x52, 0x53, 0x43, 0x32, 0, 0, 0, UInt8(rows.count)])
    func appendLong(_ value: Int64) { let number = UInt64(value)
      for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((number >> shift) & 255)) } }
    for entry in rows {
      let row = entry.row; bytes.append(entry.kind)
      for value in [row.owner, row.session, row.group, row.request] { bytes.append(Data(value.utf8)) }
      let revision = UInt32(row.revision)
      bytes.append(contentsOf: [UInt8((revision >> 24) & 255), UInt8((revision >> 16) & 255), UInt8((revision >> 8) & 255), UInt8(revision & 255)])
      appendLong(row.decisionRevision); bytes.append(row.choice ? 1 : 0); appendLong(entry.head)
    }
    return bytes
  }
  private func decode(_ owner: String, _ bytes: Data) throws -> Journal {
    guard bytes.count >= 8, bytes.count <= Self.maximum, Array(bytes.prefix(7)) == [0x52, 0x53, 0x43, 0x32, 0, 0, 0] else { throw Failure.invalid }
    let count = Int(bytes[7]); guard count <= 64, bytes.count == 8 + count * 166 else { throw Failure.invalid }
    var offset = 8; var journal = Journal()
    func takeUuid() throws -> String { defer { offset += 36 }
      guard let value = String(data: bytes.subdata(in: offset..<(offset + 36)), encoding: .ascii) else { throw Failure.invalid }
      return try uuid(value) }
    func takeLong() throws -> Int64 { defer { offset += 8 }
      let number = bytes[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
      guard number <= 9007199254740991 else { throw Failure.invalid }; return Int64(number) }
    for _ in 0..<count {
      let kind = bytes[offset]; offset += 1; guard kind <= 1 else { throw Failure.invalid }
      let owner = try takeUuid(), session = try takeUuid(), group = try takeUuid(), request = try takeUuid()
      let revision = bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }; offset += 4
      let decision = try takeLong(); let choice = bytes[offset]; offset += 1; guard choice <= 1 else { throw Failure.invalid }
      let head = try takeLong(); let row = Record(owner: owner, session: session, group: group, request: request,
        revision: revision, decisionRevision: decision, choice: choice == 1)
      if kind == 0 { guard head == 0 else { throw Failure.invalid }; journal.pending.append(row) }
      else { journal.superseded.append(Superseded(request: row, observedHead: head)) }
    }
    guard try encode(owner, journal) == bytes else { throw Failure.invalid }; return journal
  }
  private func load(_ owner: String) throws -> Journal {
    _ = try uuid(owner); try checkFile(directory, directory: true); let url = path(owner); try checkFile(url)
    guard manager.fileExists(atPath: url.path) else { return Journal() }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let encrypted = try handle.read(upToCount: Self.maximum + 30) ?? Data()
    guard encrypted.count >= 37, encrypted.count <= Self.maximum + 29, encrypted.first == 1 else { throw Failure.invalid }
    let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst())
    let records = try decode(owner, AES.GCM.open(box, using: key(create: false), authenticating: aad(owner)))
    // Recovering an uncertain prior write must re-establish custody durability.
    try handle.synchronize()
    try syncDirectory(directory)
    try syncDirectory(directory.deletingLastPathComponent())
    return records
  }
  private func write(_ owner: String, _ journal: Journal) throws {
    let bytes = try encode(owner, journal)
    try checkFile(directory, directory: true)
    if !manager.fileExists(atPath: path(owner).path), manager.fileExists(atPath: directory.path),
      try manager.contentsOfDirectory(atPath: directory.path).count >= 64 { throw Failure.capacity }
    let box = try AES.GCM.seal(bytes, using: key(create: true), authenticating: aad(owner))
    guard let encrypted = box.combined else { throw Failure.unavailable }
    try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
    var dir = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try dir.setResourceValues(values)
    let destination = path(owner); try checkFile(destination)
    try (Data([1]) + encrypted).write(to: destination, options: [.atomic, .completeFileProtection])
    let handle = try FileHandle(forWritingTo: destination); defer { try? handle.close() }; try handle.synchronize()
    try syncDirectory(directory)
    try syncDirectory(directory.deletingLastPathComponent())
    guard try encode(owner, load(owner)) == bytes else { throw Failure.unavailable }
  }
  private func syncDirectory(_ url: URL) throws {
    try checkFile(url, directory: true)
    let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
    guard fd >= 0 else { throw Failure.unavailable }; defer { Darwin.close(fd) }
    guard Darwin.fsync(fd) == 0 else { throw Failure.unavailable }
  }
  func read(owner: String, group: String) throws -> [String: Any] {
    Self.lock.lock(); defer { Self.lock.unlock() }; _ = try uuid(group)
    return try load(owner).wire(group)
  }
  func claim(owner: String, group: String, value: Any?, fence: Bool = false) throws -> [String: Any] {
    Self.lock.lock(); defer { Self.lock.unlock() }
    let row = try record(value); guard row.owner == owner, row.group == group, !fence || !row.choice else { throw Failure.invalid }
    var journal = try load(owner); let older = journal.pending.filter { $0.group == group }
    if older.contains(where: { $0.session == row.session }) || (!fence && !older.isEmpty) { return journal.wire(group) }
    if fence { guard !older.isEmpty, older.allSatisfy({ $0.session != row.session && $0.decisionRevision <= row.decisionRevision && $0.revision <= row.revision }) else { throw Failure.invalid } }
    journal.pending.append(row); try validate(owner, journal); try write(owner, journal); return journal.wire(group)
  }
  func complete(owner: String, group: String, value: Any?, head: Any?) throws -> [String: Any] {
    Self.lock.lock(); defer { Self.lock.unlock() }
    let row = try record(value), decision = try decisionHead(head)
    guard row.owner == owner, row.group == group, decision == row.decisionRevision + 1 else { throw Failure.invalid }
    var journal = try load(owner)
    let retained = journal.pending.first(where: { $0.request == row.request }) ?? journal.superseded.first(where: { $0.request.request == row.request })?.request
    guard let retained else { return journal.wire(group) }
    guard retained == row else { throw Failure.invalid }
    let fenced = journal.pending.filter { $0.group == group && $0.request != row.request && $0.decisionRevision < decision }
    let ids = Set(fenced.map { $0.request } + [row.request])
    journal.pending.removeAll(where: { ids.contains($0.request) })
    journal.superseded.removeAll(where: { $0.request.request == row.request })
    journal.superseded += fenced.map { Superseded(request: $0, observedHead: decision) }
    try validate(owner, journal); try write(owner, journal); return journal.wire(group)
  }
  func supersede(owner: String, group: String, values: Any?, head: Any?) throws -> [String: Any] {
    Self.lock.lock(); defer { Self.lock.unlock() }; _ = try uuid(owner); _ = try uuid(group)
    guard let values = values as? [Any], !values.isEmpty, values.count <= 32 else { throw Failure.invalid }
    let known = try values.map { try record($0) }, decision = try decisionHead(head)
    guard decision > 0, Set(known.map { $0.request }).count == known.count,
      known.allSatisfy({ $0.owner == owner && $0.group == group }) else { throw Failure.invalid }
    var journal = try load(owner); let actual = journal.pending.filter { $0.group == group }
    let expected = Dictionary(uniqueKeysWithValues: known.map { ($0.request, $0) })
    guard actual.allSatisfy({ expected[$0.request] == $0 }) else { throw Failure.invalid }
    let retained = Dictionary(uniqueKeysWithValues: (journal.pending + journal.superseded.map { $0.request }).map { ($0.request, $0) })
    for row in known {
      guard retained[row.request] == nil || retained[row.request] == row,
        retained[row.request] != nil || row.decisionRevision < decision else { throw Failure.invalid }
    }
    let fenced = known.filter { $0.decisionRevision < decision }; guard !fenced.isEmpty else { throw Failure.invalid }
    let removed = Set(fenced.map { $0.request }), existingHistory = Set(journal.superseded.map { $0.request.request })
    journal.pending.removeAll(where: { removed.contains($0.request) })
    journal.superseded += fenced.filter { !existingHistory.contains($0.request) }.map { Superseded(request: $0, observedHead: decision) }
    try validate(owner, journal); try write(owner, journal); return journal.wire(group)
  }
}
