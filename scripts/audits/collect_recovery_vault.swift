// macOS encrypted recovery destination. No database access or secret output.
// Build a stable executable; its Keychain item must remain with the archive.
import Foundation
import Security
import LocalAuthentication
import Darwin

enum VaultError: Error { case refused(String) }
let files = FileManager.default
let service = "app.collect.production-recovery"
let root = files.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/CollectRecovery", isDirectory: true)

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VaultError.refused(message) }
}

func run(_ arguments: [String], password: Data? = nil) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = arguments
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output
    try process.run()
    if var secret = password {
        secret.append(0) // hdiutil -stdinpass accepts a NUL-terminated password.
        try input.fileHandleForWriting.write(contentsOf: secret)
        secret.resetBytes(in: 0..<secret.count)
    }
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0,
                "hdiutil \(arguments[0]) failed (\(process.terminationStatus)); raw output withheld")
    return data
}

func plist(_ data: Data) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any] else { throw VaultError.refused("Unexpected disk-image response") }
    return value
}

func keyQuery(_ identifier: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: identifier]
}

func readKey(_ identifier: String) throws -> Data {
    var query = keyQuery(identifier)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    // Fail rather than silently authorize a different executable to read the key.
    let context = LAContext()
    context.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = context
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    try require(status == errSecSuccess, "Keychain read failed (\(status)); no fallback key file")
    guard let data = result as? Data else { throw VaultError.refused("Missing Keychain data") }
    try require(data.count == 64, "Unexpected recovery-key length")
    return data
}

func createKey(_ identifier: String) throws -> Data {
    var random = [UInt8](repeating: 0, count: 32)
    try require(SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess,
                "Secure random generation failed")
    let data = Data(random.map { String(format: "%02x", $0) }.joined().utf8)
    _ = random.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    var query = keyQuery(identifier)
    query[kSecAttrLabel as String] = "Collect recovery: \(identifier)"
    query[kSecAttrSynchronizable as String] = false
    query[kSecValueData as String] = data
    let status = SecItemAdd(query as CFDictionary, nil)
    try require(status == errSecSuccess, "Keychain creation failed (\(status)); existing keys never overwritten")
    try require(try readKey(identifier) == data, "Keychain readback differs")
    return data
}

func encryption(_ image: URL) throws -> [String: Any] {
    // An attached read/write sparsebundle is locked. Query its verified mount
    // metadata instead of opening the backing image again with isencrypted.
    if let attached = try attachedImage(image) {
        try require(attached["image-encrypted"] as? Bool == true, "Attached image is not encrypted")
        return ["encrypted": true, "verified_via": "attached_image_metadata"]
    }
    let result = try plist(run(["isencrypted", image.path, "-plist"]))
    try require(result["encrypted"] as? Bool == true, "Image is not encrypted")
    return result
}

func attachedImage(_ image: URL) throws -> [String: Any]? {
    let response = try plist(run(["info", "-plist"]))
    return (response["images"] as? [[String: Any]] ?? []).first {
        ($0["image-path"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL.path } == image.path
    }
}

do {
    umask(0o077)
    let arguments = Array(CommandLine.arguments.dropFirst())
    try require(arguments.count == 2, "Usage: collect-recovery-vault create|attach|readonly|detach|inspect collect-<unique-id>")
    let action = arguments[0], identifier = arguments[1]
    try require(["create", "attach", "readonly", "detach", "inspect"].contains(action), "Unknown action")
    try require(identifier.range(of: #"\Acollect-[a-z0-9-]{8,70}\z"#, options: .regularExpression) != nil,
                "Invalid artifact identifier")
    try require(root.resolvingSymlinksInPath().path == root.path, "Recovery root must not be a symbolic link")
    try files.createDirectory(at: root, withIntermediateDirectories: true,
                              attributes: [.posixPermissions: 0o700])
    try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    let image = root.appendingPathComponent(identifier + ".sparsebundle").standardizedFileURL
    let mount = root.appendingPathComponent(identifier + ".mount").standardizedFileURL
    try require(image.resolvingSymlinksInPath() == image && mount.resolvingSymlinksInPath() == mount,
                "Symbolic-link targets are refused")
    var result: [String: Any] = ["action": action, "image": image.path,
                                "mount": mount.path, "keychain_service": service,
                                "keychain_account": identifier, "secret_values_output": false]
    if action == "create" {
        try require(!files.fileExists(atPath: image.path), "Existing image is never overwritten")
        var key = try createKey(identifier)
        defer { key.resetBytes(in: 0..<key.count) }
        _ = try run(["create", "-size", "2g", "-type", "SPARSEBUNDLE", "-fs", "APFS",
                     "-volname", identifier, "-nospotlight", "-encryption", "AES-256",
                     "-stdinpass", "-quiet", image.path], password: key)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: image.path)
    }
    result["encryption"] = try encryption(image)
    if action == "attach" || action == "readonly" {
        try require(try attachedImage(image) == nil, "Image is already attached")
        if files.fileExists(atPath: mount.path) {
            try require(try files.contentsOfDirectory(atPath: mount.path).isEmpty, "Mount point is not empty")
        } else {
            try files.createDirectory(at: mount, withIntermediateDirectories: false,
                                      attributes: [.posixPermissions: 0o700])
        }
        var key = try readKey(identifier)
        defer { key.resetBytes(in: 0..<key.count) }
        var options = ["attach", image.path, "-stdinpass", "-nobrowse", "-noautoopen",
                       "-owners", "on", "-mountpoint", mount.path, "-plist"]
        if action == "readonly" { options.append("-readonly") }
        let attachment = try plist(run(options, password: key))
        let entities = attachment["system-entities"] as? [[String: Any]] ?? []
        try require(entities.contains { $0["mount-point"] as? String == mount.path }, "Mount target mismatch")
        if action == "attach" { try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mount.path) }
    } else if action == "detach" {
        guard let attached = try attachedImage(image),
              let entities = attached["system-entities"] as? [[String: Any]],
              entities.contains(where: { $0["mount-point"] as? String == mount.path }),
              let device = entities.first?["dev-entry"] as? String else {
            throw VaultError.refused("Expected image/mount is not attached; nothing detached")
        }
        try require(device.range(of: #"\A/dev/disk[0-9]+\z"#, options: .regularExpression) != nil,
                    "Unexpected image device")
        _ = try run(["detach", device, "-quiet"])
        try require(try attachedImage(image) == nil, "Image is still attached")
    }
    result["attached"] = try attachedImage(image) != nil
    let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data([10]))
} catch VaultError.refused(let message) {
    FileHandle.standardError.write(Data(("REFUSED: " + message + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Vault operation failed; sensitive details withheld. Inspect the exact artifact before retrying.\n".utf8))
    exit(1)
}
