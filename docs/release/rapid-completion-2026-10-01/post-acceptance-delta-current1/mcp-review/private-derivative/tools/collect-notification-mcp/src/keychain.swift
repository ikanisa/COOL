import Foundation
import Security
import LocalAuthentication

// One task-specific Keychain item. No browser store, generic credential lookup,
// phone number, or secret-bearing command argument is used. Opt-in rotated
// session credentials remain inside this same device-local protected item.
let base: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.ikanisa.collect.notification-operator",
    kSecAttrAccount as String: "lhbowpbcpwoiparwnwgt"
]
func fail(_ status: OSStatus) -> Never {
    FileHandle.standardError.write(Data("Collect operator Keychain status \(status)\n".utf8))
    exit(2)
}
switch CommandLine.arguments.dropFirst().first {
case "read":
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext()
    context.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { fail(status) }
    FileHandle.standardOutput.write(data)
case "write":
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count > 0, data.count <= 16384,
          (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { fail(errSecParam) }
    let updates: [String: Any] = [kSecValueData as String: data]
    var status = SecItemUpdate(base as CFDictionary, updates as CFDictionary)
    if status == errSecItemNotFound {
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        status = SecItemAdd(query as CFDictionary, nil)
    }
    guard status == errSecSuccess else { fail(status) }
case "delete":
    let status = SecItemDelete(base as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { fail(status) }
default:
    fail(errSecParam)
}
