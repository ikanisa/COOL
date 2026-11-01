import Foundation
import CryptoKit

enum ContributionCommandFailure: Error { case invalid, unavailable, capacity, busy }

struct ContributionCommandSnapshot: Equatable {
  let partition: String, revision: Int64, payload: String?
  init(partition: String, revision: Int64, payload: String?) throws {
    try ContributionCommandCipher.validatePartition(partition)
    guard revision >= 0, revision <= ContributionCommandCipher.maxRevision,
      (revision == 0 ? payload == nil : payload != nil) else { throw ContributionCommandFailure.invalid }
    if let payload { _ = try ContributionCommandCipher.payloadBytes(payload) }
    self.partition = partition; self.revision = revision; self.payload = payload
  }
  var wire: [String: Any] { ["schema_version": 1, "partition_id": partition,
    "revision": revision, "payload": payload as Any? ?? NSNull()] }
}

/// This purpose and partition are authenticated independently of the old caches.
final class ContributionCommandCipher {
  static let maxRevision: Int64 = 9007199254740991
  static let maxPayloadBytes = 1024 * 1024, maxCiphertextBytes = 1024 * 1024 + 37
  static let maxPartitions = 64, maxAggregateBytes: Int64 = 16 * 1024 * 1024
  private let key: (Bool) throws -> SymmetricKey
  init(key: @escaping (Bool) throws -> SymmetricKey) { self.key = key }
  static func validatePartition(_ partition: String) throws {
    guard partition.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ContributionCommandFailure.invalid }
  }
  static func payloadBytes(_ value: String) throws -> Data {
    let bytes = Data(value.utf8)
    guard !bytes.isEmpty, bytes.count <= maxPayloadBytes else { throw ContributionCommandFailure.capacity }
    return bytes
  }
  private func aad(_ partition: String) throws -> Data {
    try Self.validatePartition(partition)
    return Data(("collect.contribution-commands.v1\0" + partition).utf8)
  }
  func encrypt(_ snapshot: ContributionCommandSnapshot) throws -> Data {
    guard snapshot.revision > 0, let payload = snapshot.payload else { throw ContributionCommandFailure.invalid }
    var bytes = Data(); let revision = UInt64(snapshot.revision)
    for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((revision >> shift) & 255)) }
    bytes.append(try Self.payloadBytes(payload))
    let sealed = try AES.GCM.seal(bytes, using: key(true), authenticating: aad(snapshot.partition))
    guard let combined = sealed.combined else { throw ContributionCommandFailure.unavailable }
    return Data([1]) + combined
  }
  func decrypt(_ partition: String, _ encrypted: Data) throws -> ContributionCommandSnapshot {
    guard encrypted.count >= 38, encrypted.count <= Self.maxCiphertextBytes, encrypted.first == 1 else { throw ContributionCommandFailure.invalid }
    let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst())
    let bytes = try AES.GCM.open(box, using: key(false), authenticating: aad(partition))
    guard bytes.count >= 9, bytes.count <= Self.maxPayloadBytes + 8 else { throw ContributionCommandFailure.invalid }
    let revision = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    guard revision > 0, revision <= UInt64(Self.maxRevision),
      let payload = String(data: bytes.dropFirst(8), encoding: .utf8) else { throw ContributionCommandFailure.invalid }
    return try ContributionCommandSnapshot(partition: partition, revision: Int64(revision), payload: payload)
  }
}
