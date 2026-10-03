import Foundation
import Security
import LocalAuthentication
import CryptoKit

// Separate hardware key, fixed project and signing protocol. These commands
// never read the operator session item or export a private key.
let tag = Data("com.ikanisa.collect.receipt-supervisor.lhbowpbcpwoiparwnwgt.v1".utf8)
let audience = "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt"
let query: [String: Any] = [
    kSecClass as String: kSecClassKey,
    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
    kSecAttrApplicationTag as String: tag,
    kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave
]
func refuse(_ code: String) -> Never {
    FileHandle.standardError.write(Data((code + "\n").utf8))
    exit(2)
}
func canonicalUUID(_ value: String) -> Bool {
    return UUID(uuidString: value)?.uuidString.lowercased() == value
}
func canonicalEnvelope(_ data: Data, now: Date = Date()) -> Bool {
    guard data.count <= 8192,
          let value = try? JSONSerialization.jsonObject(with: data),
          let body = value as? [String: Any],
          Set(body.keys) == Set(["contract_version", "audience", "action", "principal_id", "request_id", "issued_at", "payload"]),
          let version = body["contract_version"] as? NSNumber,
          CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
          body["audience"] as? String == audience,
          let action = body["action"] as? String,
          ["prove_key", "shadow_health", "reconcile"].contains(action),
          let principal = body["principal_id"] as? String, canonicalUUID(principal),
          let request = body["request_id"] as? String, canonicalUUID(request),
          let issued = body["issued_at"] as? String,
          issued.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$", options: .regularExpression) != nil,
          let payload = body["payload"] as? [String: Any] else { return false }
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = format.date(from: issued), format.string(from: date) == issued,
          date.timeIntervalSince(now) >= -30, date.timeIntervalSince(now) <= 10 else { return false }
    if action == "reconcile" {
        guard Set(payload.keys) == Set(["target_request_id"]),
              let target = payload["target_request_id"] as? String, canonicalUUID(target) else { return false }
    } else if !payload.isEmpty { return false }
    // The caller uses the same sorted, ASCII-only envelope. Exact equality
    // rejects duplicate keys, ignored whitespace and ambiguous JSON variants.
    return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])) == data
}
func privateKey() -> SecKey {
    var read = query
    read[kSecReturnRef as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext()
    context.interactionNotAllowed = true
    read[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?
    guard SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess,
          let result = result, CFGetTypeID(result) == SecKeyGetTypeID() else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
    return result as! SecKey
}
func publicMetadata(_ key: SecKey) -> [String: Any] {
    guard let publicKey = SecKeyCopyPublicKey(key),
          let raw = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
          raw.count == 65, raw.first == 4 else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
    let prefix = Data([0x30,0x59,0x30,0x13,0x06,0x07,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01,
                       0x06,0x08,0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07,0x03,0x42,0x00])
    let spki = prefix + raw
    return ["contract_version": 1, "scope": "rw_receipt_shadow",
            "public_key_spki_base64": spki.base64EncodedString(),
            "key_sha256": SHA256.hash(data: spki).map { String(format: "%02x", $0) }.joined()]
}
func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
    FileHandle.standardOutput.write(data)
}
guard CommandLine.arguments.count == 2 else { refuse("SUPERVISOR_KEY_ARGUMENTS_INVALID") }
switch CommandLine.arguments[1] {
case "create-key":
    var existing = query
    existing[kSecReturnRef as String] = true
    var found: CFTypeRef?
    let status = SecItemCopyMatching(existing as CFDictionary, &found)
    guard status == errSecItemNotFound else { refuse(status == errSecSuccess ? "SUPERVISOR_KEY_ALREADY_EXISTS" : "SUPERVISOR_KEY_UNAVAILABLE") }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error) else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
                                      kSecAttrApplicationTag as String: tag,
                                      kSecAttrAccessControl as String: access]
    ]
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
    emit(publicMetadata(key))
case "read-public":
    emit(publicMetadata(privateKey()))
case "sign":
    var data = Data()
    do {
        while let chunk = try FileHandle.standardInput.read(upToCount: 8193 - data.count), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 8192 else { refuse("SUPERVISOR_SIGN_ARGUMENTS_INVALID") }
        }
    } catch { refuse("SUPERVISOR_SIGN_ARGUMENTS_INVALID") }
    guard canonicalEnvelope(data) else { refuse("SUPERVISOR_SIGN_ARGUMENTS_INVALID") }
    let key = privateKey()
    guard SecKeyIsAlgorithmSupported(key, .sign, .ecdsaSignatureMessageX962SHA256),
          let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, nil) as Data? else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
    let metadata = publicMetadata(key)
    emit(["contract_version": 1, "key_sha256": metadata["key_sha256"]!, "signature_base64": signature.base64EncodedString()])
case "delete-local":
    // Run only after confirmed server revocation. Deletion cannot recall an
    // already committed observation or replace server revocation evidence.
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { refuse("SUPERVISOR_KEY_UNAVAILABLE") }
case "self-test":
    // Synthetic parsing only. This path makes no Keychain call or key pair.
    let now = Date(timeIntervalSince1970: 1790809200)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var body: [String: Any] = ["contract_version": 1, "audience": audience, "action": "shadow_health",
        "principal_id": "99800000-0000-4000-8000-000000000001", "request_id": "99800000-0000-4000-8000-000000000002",
        "issued_at": formatter.string(from: now), "payload": [String: Any]()]
    func encoded(_ body: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]) }
    var checks = 0
    func check(_ value: Bool) { guard value else { refuse("SUPERVISOR_SELF_TEST_FAILED") }; checks += 1 }
    check(canonicalEnvelope(encoded(body), now: now))
    for patch in [["action": "send"], ["audience": "other_project"], ["contract_version": true], ["principal_id": "invalid"], ["principal_id": "ABCDEF00-0000-4000-8000-000000000001"], ["request_id": "ABCDEF00-0000-4000-8000-000000000002"], ["issued_at": "2026-02-30T00:00:00.000Z"], ["payload": ["recipient": "+250788000000"]]] as [[String: Any]] {
        check(!canonicalEnvelope(encoded(body.merging(patch) { _, new in new }), now: now))
    }
    check(!canonicalEnvelope(encoded(body), now: now.addingTimeInterval(31)))
    check(!canonicalEnvelope(encoded(body), now: now.addingTimeInterval(-11)))
    let duplicate = String(data: encoded(body), encoding: .utf8)!.replacingOccurrences(of: "\"action\":\"shadow_health\"", with: "\"action\":\"prove_key\",\"action\":\"shadow_health\"")
    check(!canonicalEnvelope(Data(duplicate.utf8), now: now))
    body["action"] = "reconcile"
    body["payload"] = ["target_request_id": "99800000-0000-4000-8000-000000000003"]
    check(canonicalEnvelope(encoded(body), now: now))
    body["payload"] = ["target_request_id": "invalid"]
    check(!canonicalEnvelope(encoded(body), now: now))
    emit(["checks": checks, "status": "pass", "keychain_called": false, "key_created": false])
default:
    refuse("SUPERVISOR_KEY_ARGUMENTS_INVALID")
}
