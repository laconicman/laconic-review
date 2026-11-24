import Foundation
import XCTest
@testable import LaconicReviewCore

/// End-to-end through the real default Keychain via `/usr/bin/security` — the same
/// tool production shells out to, so add/read/delete never prompt. Each test gets a
/// unique service name; `tearDown` removes whatever the test created.
final class KeychainTokenTests: XCTestCase {
    private var service = ""
    private var keychainPath = ""

    override func setUpWithError() throws {
        service = "laconic-review-test-\(UUID().uuidString)"
        // The suite needs a writable, unlocked Keychain — a locked one (CI sandboxes,
        // a logged-out session) would fail every test before token resolution runs.
        // Every operation is pinned to the default Keychain's path: `add` writes
        // there, while an unscoped `delete` searches only the search list — which
        // need not contain the default.
        guard let path = defaultKeychainPath() else {
            throw XCTSkip("cannot resolve the default Keychain")
        }
        keychainPath = path
        let probe = runSecurity([
            "add-generic-password", "-a", "laconic-review-test", "-s", service,
            "-w", "probe", keychainPath,
        ])
        guard probe.status == 0 else {
            throw XCTSkip("default Keychain not writable: \(probe.message)")
        }
        _ = runSecurity(["delete-generic-password", "-s", service, keychainPath])
    }

    override func tearDown() {
        guard !keychainPath.isEmpty else { return }
        _ = runSecurity(["delete-generic-password", "-s", service, keychainPath])
    }

    func testPasswordRoundTrip() throws {
        try addItem(password: "test-token-123")
        XCTAssertEqual(try KeychainToken.password(service: service), "test-token-123")
    }

    func testResolveTokenFallsBackToKeychain() throws {
        try addItem(password: "fallback-token")
        let token = try ProjectContext.resolveToken(
            env: "LACONIC_REVIEW_TEST_UNSET", keychainService: service, environment: [:]
        )
        XCTAssertEqual(token, "fallback-token")
    }

    func testMissingItemThrowsItemNotFound() {
        XCTAssertThrowsError(try KeychainToken.password(service: service)) { error in
            XCTAssertEqual(error as? KeychainTokenError, .itemNotFound(service: service))
        }
    }

    // MARK: - helpers

    private func addItem(password: String) throws {
        let result = runSecurity([
            "add-generic-password", "-a", "laconic-review-test", "-s", service,
            "-w", password, keychainPath,
        ])
        XCTAssertEqual(result.status, 0, result.message)
    }

    /// Path of the default Keychain — printed quoted, e.g. `"/Users/x/Library/
    /// Keychains/login.keychain-db"`; same resolution `KeychainToken` uses.
    private func defaultKeychainPath() -> String? {
        let result = runSecurity(["default-keychain"])
        guard result.status == 0 else { return nil }
        let path = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return path.isEmpty ? nil : path
    }

    /// Runs `/usr/bin/security <arguments>`; returns the exit status, stdout, and
    /// trimmed stderr text.
    @discardableResult
    private func runSecurity(_ arguments: [String]) -> (status: Int32, stdout: String, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try? process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
