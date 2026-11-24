import Foundation

/// Reads a secret from the login Keychain through the `security` tool — the same
/// recipe partner-ios documents for agents (`security find-generic-password
/// -s <service> -w`).
///
/// Going through `/usr/bin/security` rather than `SecItemCopyMatching` keeps the
/// read prompt-free: an item added by `security add-generic-password` trusts that
/// tool, so no per-binary Keychain dialog appears — which matters in the
/// agent/headless shells this exists for.
enum KeychainToken {
    /// Returns the password of the generic-password item stored under `service`.
    static func password(service: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        switch process.terminationStatus {
        case 0:
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            // `-w` appends a newline the token itself never carries.
            return String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .newlines)
        case 44: // the tool's exit status for "item not found"
            throw KeychainTokenError.itemNotFound(service: service)
        default:
            let message = String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw KeychainTokenError.failure(
                service: service, status: process.terminationStatus, message: message
            )
        }
    }
}

/// Why a Keychain token lookup failed.
public enum KeychainTokenError: Error, CustomStringConvertible, Equatable {
    /// No generic-password item exists for the service.
    case itemNotFound(service: String)
    /// `security` exited non-zero for any other reason — a denied prompt, a locked
    /// keychain, bad arguments.
    case failure(service: String, status: Int32, message: String)

    public var description: String {
        switch self {
        case .itemNotFound(let service):
            return "No Keychain item with service `\(service)` — add one with `security add-generic-password -s \(service)`."
        case .failure(let service, _, let message):
            return "Keychain lookup for `\(service)` failed: \(message)"
        }
    }
}
