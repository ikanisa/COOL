import Foundation
import CryptoKit
import Security
import Darwin

/// Device-only multi-owner custody. No purge, expiry, plaintext or retry API.
final class ContributionCommandStore {
  private static let processLock = NSLock()
  private let root: URL, keyProvider: ((String, Bool) throws -> SymmetricKey)?
  private let manager = FileManager.default
  private var directory: URL { root.appendingPathComponent("CollectContributionCommandsV1", isDirectory: true) }
  private var service: String { (Bundle.main.bundleIdentifier ?? "app.cool.mobile") + ".contribution-commands.v1" }
  init(directoryRoot: URL? = nil, keyProvider: ((String, Bool) throws -> SymmetricKey)? = nil) {
    root = (directoryRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).resolvingSymlinksInPath()
    self.keyProvider = keyProvider
  }
  private func path(_ partition: String) throws -> URL {
    try ContributionCommandCipher.validatePartition(partition)
    return directory.appendingPathComponent(partition + ".enc")
  }
  private func metadata(_ url: URL, isDirectory: Bool = false) throws -> stat? {
    var value = stat()
    guard Darwin.lstat(url.path, &value) == 0 else {
      if errno == ENOENT { return nil }; throw ContributionCommandFailure.unavailable
    }
    guard (value.st_mode & mode_t(S_IFMT)) == mode_t(isDirectory ? S_IFDIR : S_IFREG),
      url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL,
      isDirectory || value.st_nlink == 1 else { throw ContributionCommandFailure.invalid }
    return value
  }
  private func ensureDirectory() throws {
    if try metadata(root, isDirectory: true) == nil {
      try manager.createDirectory(at: root, withIntermediateDirectories: true,
        attributes: directoryAttributes())
      try syncDirectory(root.deletingLastPathComponent())
    }
    let created = try metadata(directory, isDirectory: true) == nil
    if created {
      try manager.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: directoryAttributes())
    }
    guard try metadata(directory, isDirectory: true) != nil else { throw ContributionCommandFailure.unavailable }
    var dir = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try dir.setResourceValues(values)
    if created { try syncDirectory(root) }
  }
  private func directoryAttributes() -> [FileAttributeKey: Any] {
    var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    attributes[.protectionKey] = FileProtectionType.complete
    #endif
    return attributes
  }
  private func entries() throws -> [(URL, Int64)] {
    var entries = [(URL, Int64)]()
    for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      guard let value = try metadata(url) else { throw ContributionCommandFailure.unavailable }
      if url.lastPathComponent == ".lock" {
        guard value.st_size == 0 else { throw ContributionCommandFailure.invalid }; continue
      }
      // Preserve interrupted staging files and refuse an ambiguous journal.
      guard url.lastPathComponent.range(of: "^[0-9a-f]{64}\\.enc$", options: .regularExpression) != nil,
        value.st_size >= 38, value.st_size <= ContributionCommandCipher.maxCiphertextBytes else { throw ContributionCommandFailure.invalid }
      entries.append((url, value.st_size))
    }
    guard entries.count <= ContributionCommandCipher.maxPartitions,
      entries.reduce(Int64(0), { $0 + $1.1 }) <= ContributionCommandCipher.maxAggregateBytes else { throw ContributionCommandFailure.capacity }
    return entries
  }
  private func locked<T>(_ body: () throws -> T) throws -> T {
    guard Self.processLock.lock(before: Date(timeIntervalSinceNow: 2)) else { throw ContributionCommandFailure.busy }
    defer { Self.processLock.unlock() }
    try ensureDirectory()
    let url = directory.appendingPathComponent(".lock"), before = try metadata(directory.appendingPathComponent(".lock"))
    let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw ContributionCommandFailure.unavailable }; defer { Darwin.close(fd) }
    var opened = stat()
    guard Darwin.fstat(fd, &opened) == 0, (opened.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), opened.st_nlink == 1,
      opened.st_size == 0, before == nil || (before!.st_dev == opened.st_dev && before!.st_ino == opened.st_ino) else { throw ContributionCommandFailure.invalid }
    // POSIX whole-file record lock; the process mutex also fences local engines.
    var recordLock = Darwin.flock()
    recordLock.l_type = Int16(F_WRLCK); recordLock.l_whence = Int16(SEEK_SET)
    recordLock.l_start = 0; recordLock.l_len = 0
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while Darwin.fcntl(fd, F_SETLK, &recordLock) != 0 {
      guard errno == EACCES || errno == EAGAIN else { throw ContributionCommandFailure.unavailable }
      guard ProcessInfo.processInfo.systemUptime < deadline else { throw ContributionCommandFailure.busy }
      usleep(10000)
    }
    defer { recordLock.l_type = Int16(F_UNLCK); _ = Darwin.fcntl(fd, F_SETLK, &recordLock) }
    guard let pinned = try metadata(url), pinned.st_dev == opened.st_dev, pinned.st_ino == opened.st_ino else { throw ContributionCommandFailure.invalid }
    return try body()
  }
  private func syncDirectory(_ url: URL) throws {
    guard let before = try metadata(url, isDirectory: true) else { throw ContributionCommandFailure.unavailable }
    let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard fd >= 0 else { throw ContributionCommandFailure.unavailable }; defer { Darwin.close(fd) }
    var opened = stat()
    guard Darwin.fstat(fd, &opened) == 0, before.st_dev == opened.st_dev, before.st_ino == opened.st_ino,
      Darwin.fsync(fd) == 0 else { throw ContributionCommandFailure.unavailable }
  }
  private func load(_ partition: String) throws -> ContributionCommandSnapshot {
    let retained = try entries()
    if !retained.isEmpty { _ = try key(create: false) }
    let url = try path(partition)
    guard let before = try metadata(url) else { return try ContributionCommandSnapshot(partition: partition, revision: 0, payload: nil) }
    let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard fd >= 0 else { throw ContributionCommandFailure.unavailable }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
    var opened = stat()
    guard Darwin.fstat(fd, &opened) == 0, opened.st_dev == before.st_dev, opened.st_ino == before.st_ino, opened.st_nlink == 1 else { throw ContributionCommandFailure.invalid }
    var bytes = Data()
    while let part = try handle.read(upToCount: 8192), !part.isEmpty {
      guard bytes.count + part.count <= ContributionCommandCipher.maxCiphertextBytes else { throw ContributionCommandFailure.capacity }
      bytes.append(part)
    }
    let snapshot = try ContributionCommandCipher(key: { try self.key(create: $0) }).decrypt(partition, bytes)
    try handle.synchronize(); try syncDirectory(directory); try syncDirectory(root)
    return snapshot
  }
  private func persist(_ snapshot: ContributionCommandSnapshot) throws {
    let retained = try entries(), target = try path(snapshot.partition)
    let encrypted = try ContributionCommandCipher(key: { try self.key(create: $0) }).encrypt(snapshot)
    guard retained.contains(where: { $0.0 == target }) || retained.count < ContributionCommandCipher.maxPartitions,
      retained.filter({ $0.0 != target }).reduce(Int64(encrypted.count), { $0 + $1.1 }) <= ContributionCommandCipher.maxAggregateBytes else { throw ContributionCommandFailure.capacity }
    let staging = target.appendingPathExtension("new")
    guard try metadata(staging) == nil else { throw ContributionCommandFailure.unavailable }
    let fd = Darwin.open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw ContributionCommandFailure.unavailable }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    do {
      #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
      try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: staging.path)
      #endif
      try handle.write(contentsOf: encrypted); try handle.synchronize(); try handle.close()
    } catch { try? handle.close(); throw error }
    // No rollback after a possible promotion; lost acknowledgement is uncertainty.
    guard Darwin.rename(staging.path, target.path) == 0 else { throw ContributionCommandFailure.unavailable }
    try syncDirectory(directory); try syncDirectory(root)
    guard try load(snapshot.partition) == snapshot else { throw ContributionCommandFailure.unavailable }
  }
  private func key(create: Bool) throws -> SymmetricKey {
    if let keyProvider { return try keyProvider(service, create) }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "data-key", kSecAttrSynchronizable as String: false, kSecReturnData as String: true,
      kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var output: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &output)
    if status == errSecSuccess, let row = output as? [String: Any], let bytes = row[kSecValueData as String] as? Data,
      bytes.count == 32, (row[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String) { return SymmetricKey(data: bytes) }
    guard status == errSecItemNotFound, create, try entries().isEmpty else { throw ContributionCommandFailure.unavailable }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ContributionCommandFailure.unavailable }
    let insertion: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: "data-key", kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false, kSecValueData as String: Data(bytes)]
    let added = SecItemAdd(insertion as CFDictionary, nil)
    if added == errSecDuplicateItem { return try key(create: false) }
    guard added == errSecSuccess else { throw ContributionCommandFailure.unavailable }; return SymmetricKey(data: Data(bytes))
  }
  func read(partition: String) throws -> [String: Any] {
    try ContributionCommandCipher.validatePartition(partition)
    return try locked { try load(partition).wire }
  }
  func compareAndSet(partition: String, expected: Any?, payload: String) throws -> [String: Any] {
    try ContributionCommandCipher.validatePartition(partition); _ = try ContributionCommandCipher.payloadBytes(payload)
    guard let number = expected as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      String(cString: number.objCType) != "d", String(cString: number.objCType) != "f",
      number.int64Value >= 0, number.int64Value < ContributionCommandCipher.maxRevision else { throw ContributionCommandFailure.invalid }
    return try locked {
      let current = try load(partition)
      guard current.revision == number.int64Value else { return current.wire.merging(["committed": false]) { _, new in new } }
      let proposed = try ContributionCommandSnapshot(partition: partition, revision: current.revision + 1, payload: payload)
      try persist(proposed)
      guard try load(partition) == proposed else { throw ContributionCommandFailure.unavailable }
      return proposed.wire.merging(["committed": true]) { _, new in new }
    }
  }
}
