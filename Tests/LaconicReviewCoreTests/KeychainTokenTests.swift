import Foundation
import XCTest
@testable import LaconicReviewCore

/// End-to-end through the real login Keychain via `/usr/bin/security` — the same
/// tool production shells out to, so add/read/delete never prompt. Each test gets a
/// unique service name; `tearDown` removes whatever the test created.
final class KeychainTokenTests: XCTestCase {
    private var service = ""

    override func setUp() {
        service = "laconic-review-test-\(UUID().uuidString)"
    }

    override func tearDown() {
        _ = runSecurity(["delete-generic-password", "-s", service])
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
            "add-generic-password", "-a", "laconic-review-test", "-s", service, "-w", password,
        ])
        XCTAssertEqual(result.status, 0, result.message)
    }

    /// Runs `/usr/bin/security <arguments>`; returns the exit status and stderr text.
    @discardableResult
    private func runSecurity(_ arguments: [String]) -> (status: Int32, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        process.standardOutput = Pipe()
        let stderr = Pipe()
        process.standardError = stderr
        try? process.run()
        process.waitUntilExit()
        let message = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, message)
    }
}
