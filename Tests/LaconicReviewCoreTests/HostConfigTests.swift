import Foundation
import XCTest
@testable import LaconicReviewCore

/// Host detection and `git remote` parsing — the seam that decides which connection
/// `makeConnection` builds. `ProjectContext.parse`/`detect` are internal, hence `@testable`.
final class HostConfigTests: XCTestCase {

    // MARK: - remote parsing

    func testParseHTTPSRemote() {
        let parsed = ProjectContext.parse(remote: "https://github.com/laconicman/laconic-review.git")
        XCTAssertEqual(parsed, .init(baseURL: "https://github.com", projectPath: "laconicman/laconic-review"))
    }

    func testParseHTTPSRemoteWithPortAndNestedGroups() {
        let parsed = ProjectContext.parse(remote: "https://gitlab.example.com:8443/group/sub/project.git")
        XCTAssertEqual(parsed, .init(baseURL: "https://gitlab.example.com:8443", projectPath: "group/sub/project"))
    }

    func testParseSCPRemote() {
        let parsed = ProjectContext.parse(remote: "git@github.com:laconicman/laconic-review.git")
        XCTAssertEqual(parsed, .init(baseURL: "https://github.com", projectPath: "laconicman/laconic-review"))
    }

    func testParseSSHRemoteNormalizesToHTTPS() {
        // ssh:// carries the SSH port, not the web one — the API base is plain https.
        let parsed = ProjectContext.parse(remote: "ssh://git@gitlab.example.com:2222/group/project.git")
        XCTAssertEqual(parsed, .init(baseURL: "https://gitlab.example.com", projectPath: "group/project"))
    }

    func testParseMixedCaseHTTPSRemoteKeepsPort() {
        // Schemes are case-insensitive — `HTTPS://` must still be treated as web.
        let parsed = ProjectContext.parse(remote: "HTTPS://gitlab.example.com:8443/group/project.git")
        XCTAssertEqual(parsed, .init(baseURL: "https://gitlab.example.com:8443", projectPath: "group/project"))
    }

    func testParseRejectsHostWithoutProject() {
        XCTAssertNil(ProjectContext.parse(remote: "https://github.com"))
        XCTAssertNil(ProjectContext.parse(remote: "not a remote at all"))
    }

    // MARK: - host detection

    func testDetectGitHubHostnames() {
        for host in ["github.com", "www.github.com", "gist.github.com", "github.company.com"] {
            let url = URL(string: "https://\(host)")!
            XCTAssertEqual(ReviewHostKind.detect(explicit: nil, baseURL: url), .github, host)
        }
    }

    func testDetectGHESHostnames() {
        for host in ["ghe.example.com", "git.company.ghe.com"] {
            let url = URL(string: "https://\(host)")!
            XCTAssertEqual(ReviewHostKind.detect(explicit: nil, baseURL: url), .github, host)
        }
    }

    func testDetectGitLabAndUnknownDefaultToGitLab() {
        // `notgithub`/`mygithub` contain the substring but no `github` DNS label —
        // substring matching would misdetect these as GitHub.
        for host in ["gitlab.com", "git.company.com", "gitlab.example.org",
                     "notgithub.com", "mygithub.example.com"] {
            let url = URL(string: "https://\(host)")!
            XCTAssertEqual(ReviewHostKind.detect(explicit: nil, baseURL: url), .gitlab, host)
        }
    }

    func testExplicitHostOverrideWins() {
        let github = URL(string: "https://github.com")!
        let gitlab = URL(string: "https://gitlab.com")!
        XCTAssertEqual(ReviewHostKind.detect(explicit: .gitlab, baseURL: github), .gitlab)
        XCTAssertEqual(ReviewHostKind.detect(explicit: .github, baseURL: gitlab), .github)
    }

    // MARK: - token env defaults

    func testTokenEnvDefaultsPerHost() {
        XCTAssertEqual(ReviewHostKind.github.defaultTokenEnv, "GITHUB_TOKEN")
        XCTAssertEqual(ReviewHostKind.gitlab.defaultTokenEnv, "GITLAB_TOKEN")
    }
}
