import Foundation
import Security
import LocalAuthentication
import CryptoKit

// Separate hardware key, fixed project and signing protocol. These commands
// never read the operator session item or export a private key.
let tag = Data("com.ikanisa.collect.receipt-operations.lhbowpbcpwoiparwnwgt.v2".utf8)
let audience = "collect.receipt-supervisor.v2/lhbowpbcpwoiparwnwgt"
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
          CFGetTypeID(version) != CFBooleanGetTypeID(), version == 2,
          body["audience"] as? String == audience,
          let action = body["action"] as? String,
          ["prove_key", "begin_run", "list_events", "ensure_receipt", "reconcile_backlog", "complete_run", "reconcile_request"].contains(action),
          let principal = body["principal_id"] as? String, canonicalUUID(principal),
          let request = body["request_id"] as? String, canonicalUUID(request),
          let issued = body["issued_at"] as? String,
          issued.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$", options: .regularExpression) != nil,
          let payload = body["payload"] as? [String: Any] else { return false }
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = format.date(from: issued), format.string(from: date) == issued,
          date.timeIntervalSince(now) >= -30, date.timeIntervalSince(now) <= 10 else { return false }
    func positive(_ item: Any?, max: Int = 1_000_000_000) -> Bool {
        guard let n = item as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
        return n.doubleValue == floor(n.doubleValue) && n.doubleValue >= 1 && n.doubleValue <= Double(max)
    }
    if action == "reconcile_request" {
        guard Set(payload.keys) == Set(["target_request_id"]),
              let target = payload["target_request_id"] as? String, canonicalUUID(target), target != request else { return false }
    } else if action == "prove_key" || action == "begin_run" {
        guard payload.isEmpty else { return false }
    } else {
        guard let run = payload["run_id"] as? String, canonicalUUID(run), positive(payload["fence_version"]) else { return false }
        if action == "complete_run" {
            guard Set(payload.keys) == Set(["run_id", "fence_version"]) else { return false }
        } else if action == "ensure_receipt" {
            guard Set(payload.keys) == Set(["run_id", "fence_version", "event_id", "expected_source_version"]),
                  let event = payload["event_id"] as? String, canonicalUUID(event), positive(payload["expected_source_version"]) else { return false }
        } else {
            guard Set(payload.keys) == Set(["run_id", "fence_version", "limit"]), positive(payload["limit"], max: 25) else { return false }
        }
    }
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
          let result = result, CFGetTypeID(result) == SecKeyGetTypeID() else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
    return result as! SecKey
}
func publicMetadata(_ key: SecKey) -> [String: Any] {
    guard let publicKey = SecKeyCopyPublicKey(key),
          let raw = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
          raw.count == 65, raw.first == 4 else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
    let prefix = Data([0x30,0x59,0x30,0x13,0x06,0x07,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01,
                       0x06,0x08,0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07,0x03,0x42,0x00])
    let spki = prefix + raw
    return ["contract_version": 2, "scope": "rw_receipt_operations",
            "public_key_spki_base64": spki.base64EncodedString(),
            "key_sha256": SHA256.hash(data: spki).map { String(format: "%02x", $0) }.joined()]
}
func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
    FileHandle.standardOutput.write(data)
}
guard CommandLine.arguments.count == 2 else { refuse("UNATTENDED_KEY_ARGUMENTS_INVALID") }
switch CommandLine.arguments[1] {
case "create-key":
    var existing = query
    existing[kSecReturnRef as String] = true
    var found: CFTypeRef?
    let status = SecItemCopyMatching(existing as CFDictionary, &found)
    guard status == errSecItemNotFound else { refuse(status == errSecSuccess ? "UNATTENDED_KEY_ALREADY_EXISTS" : "UNATTENDED_KEY_UNAVAILABLE") }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error) else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
                                      kSecAttrApplicationTag as String: tag,
                                      kSecAttrAccessControl as String: access]
    ]
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
    emit(publicMetadata(key))
case "read-public":
    emit(publicMetadata(privateKey()))
case "sign":
    var data = Data()
    do {
        while let chunk = try FileHandle.standardInput.read(upToCount: 8193 - data.count), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= 8192 else { refuse("UNATTENDED_SIGN_ARGUMENTS_INVALID") }
        }
    } catch { refuse("UNATTENDED_SIGN_ARGUMENTS_INVALID") }
    guard canonicalEnvelope(data) else { refuse("UNATTENDED_SIGN_ARGUMENTS_INVALID") }
    let key = privateKey()
    guard SecKeyIsAlgorithmSupported(key, .sign, .ecdsaSignatureMessageX962SHA256),
          let signature = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, nil) as Data? else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
    let metadata = publicMetadata(key)
    emit(["contract_version": 2, "key_sha256": metadata["key_sha256"]!, "signature_base64": signature.base64EncodedString()])
case "delete-local":
    // Run only after confirmed server revocation. Deletion cannot recall an
    // already committed observation or replace server revocation evidence.
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { refuse("UNATTENDED_KEY_UNAVAILABLE") }
case "self-test":
    // Synthetic exact-byte parsing only. No Keychain access or key creation.
    let now = Date(timeIntervalSince1970: 1790809200)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let id = "99800000-0000-4000-8000-000000000001"
    let request = "99800000-0000-4000-8000-000000000002"
    let event = "99800000-0000-4000-8000-000000000003"
    let base: [String: Any] = ["contract_version": 2, "audience": audience, "action": "begin_run",
        "principal_id": id, "request_id": request, "issued_at": formatter.string(from: now), "payload": [String: Any]()]
    func encoded(_ body: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes]) }
    var checks = 0
    func check(_ value: Bool) { guard value else { refuse("UNATTENDED_SELF_TEST_FAILED") }; checks += 1 }
    for action in ["prove_key", "begin_run", "list_events", "ensure_receipt", "reconcile_backlog", "complete_run", "reconcile_request"] {
        var body = base; body["action"] = action
        if action == "reconcile_request" { body["payload"] = ["target_request_id": event] }
        else if action == "ensure_receipt" { body["payload"] = ["run_id": id, "fence_version": 1, "event_id": event, "expected_source_version": 1] }
        else if action == "list_events" || action == "reconcile_backlog" { body["payload"] = ["run_id": id, "fence_version": 1, "limit": 25] }
        else if action == "complete_run" { body["payload"] = ["run_id": id, "fence_version": 1] }
        check(canonicalEnvelope(encoded(body), now: now))
    }
    for patch in [["action": "send"], ["audience": "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt"], ["contract_version": true], ["principal_id": "invalid"], ["payload": ["recipient": "+250788000000"]], ["issued_at": "2026-02-30T00:00:00.000Z"]] as [[String: Any]] {
        check(!canonicalEnvelope(encoded(base.merging(patch) { _, new in new }), now: now))
    }
    check(!canonicalEnvelope(encoded(base), now: now.addingTimeInterval(31)))
    check(!canonicalEnvelope(encoded(base), now: now.addingTimeInterval(-11)))
    var bad = base; bad["action"] = "ensure_receipt"
    for payload in [["run_id": id, "fence_version": true, "event_id": event, "expected_source_version": 1],
                    ["run_id": id, "fence_version": 1, "event_id": event, "expected_source_version": 0],
                    ["run_id": id, "fence_version": 1, "event_id": event, "expected_source_version": 1, "body": "private"]] as [[String: Any]] {
        bad["payload"] = payload; check(!canonicalEnvelope(encoded(bad), now: now))
    }
    let duplicate = String(data: encoded(base), encoding: .utf8)!.replacingOccurrences(of: "\"action\":\"begin_run\"", with: "\"action\":\"prove_key\",\"action\":\"begin_run\"")
    check(!canonicalEnvelope(Data(duplicate.utf8), now: now))
    emit(["checks": checks, "status": "pass", "keychain_called": false, "key_created": false])
default:
    refuse("UNATTENDED_KEY_ARGUMENTS_INVALID")
}
