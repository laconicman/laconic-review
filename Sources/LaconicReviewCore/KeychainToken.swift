import Foundation

/// Reads a secret from the user's default Keychain through the `security` tool —
/// the same recipe partner-ios documents for agents
/// (`security find-generic-password -s <service> -w`).
///
/// Going through `/usr/bin/security` rather than `SecItemCopyMatching` keeps the
/// read prompt-free: an item added by `security add-generic-password` trusts that
/// tool, so no per-binary Keychain dialog appears — which matters in the
/// agent/headless shells this exists for.
///
/// The read is scoped to `security default-keychain` — the keychain
/// `add-generic-password` writes to when none is named — so a same-named item in
/// another keychain on the search list (a VPN or System keychain, say) can't win.
enum KeychainToken {
    /// Returns the password of the generic-password item stored under `service`.
    static func password(service: String) throws -> String {
        let result = try run([
            "find-generic-password", "-s", service, "-w", try defaultKeychain(service: service),
        ])
        switch result.status {
        case 0:
            // `-w` appends a newline the token itself never carries.
            return result.stdout.trimmingCharacters(in: .newlines)
        case 44: // the tool's exit status for "item not found"
            throw KeychainTokenError.itemNotFound(service: service)
        default:
            throw KeychainTokenError.failure(
                service: service, status: result.status, message: result.stderr
            )
        }
    }

    /// Path of the default keychain — printed quoted, e.g. `"/Users/x/Library/
    /// Keychains/login.keychain-db"`.
    private static func defaultKeychain(service: String) throws -> String {
        let result = try run(["default-keychain"])
        let path = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard result.status == 0, !path.isEmpty else {
            throw KeychainTokenError.failure(
                service: service, status: result.status,
                message: "cannot resolve the default keychain"
                    + (result.stderr.isEmpty ? "" : ": \(result.stderr)")
            )
        }
        return path
    }

    /// Runs `/usr/bin/security <arguments>`; returns exit status plus raw stdout and
    /// trimmed stderr.
    private static func run(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
            return "No Keychain item with service `\(service)` — add one with `security add-generic-password -a \"$USER\" -s \(service) -w` (prompts for the token)."
        case .failure(let service, _, let message):
            return "Keychain lookup for `\(service)` failed: \(message)"
        }
    }
}
