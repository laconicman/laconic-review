import CFNetwork
import Foundation
import Testing
@testable import LaconicReviewCore

@Suite("ProxyEnvironment")
struct ProxyEnvironmentTests {

    private func dict(_ env: [String: String]) -> [String: Any]? {
        ProxyEnvironment.proxyDictionary(environment: env)
    }

    private func value(_ key: String, in dict: [String: Any]?) -> Any? {
        dict?[key]
    }

    @Test("no proxy env → nil dictionary")
    func empty() {
        #expect(dict([:]) == nil)
        #expect(dict(["NO_PROXY": "localhost"]) == nil) // exceptions alone are not a proxy
    }

    @Test("elsewhere run's export: http lanes + socks catch-all + bypass list")
    func elsewhereShape() {
        let d = dict([
            "HTTP_PROXY": "http://127.0.0.1:18080",
            "HTTPS_PROXY": "http://127.0.0.1:18080",
            "ALL_PROXY": "socks5h://127.0.0.1:18080",
            "NO_PROXY": "localhost,127.0.0.1,*.flat.lab",
        ])
        #expect(value(kCFNetworkProxiesHTTPEnable as String, in: d) as? Bool == true)
        #expect(value(kCFNetworkProxiesHTTPProxy as String, in: d) as? String == "127.0.0.1")
        #expect(value(kCFNetworkProxiesHTTPPort as String, in: d) as? Int == 18080)
        #expect(value(kCFNetworkProxiesHTTPSProxy as String, in: d) as? String == "127.0.0.1")
        #expect(value(kCFNetworkProxiesSOCKSEnable as String, in: d) as? Bool == true)
        #expect(value(kCFNetworkProxiesSOCKSPort as String, in: d) as? Int == 18080)
        // `*.flat.lab` is the env-file spelling; CFNetwork wants the bare suffix `flat.lab`.
        #expect(
            value(kCFNetworkProxiesExceptionsList as String, in: d) as? [String]
                == ["localhost", "127.0.0.1", "flat.lab"]
        )
    }

    @Test("proxy exit URL (http) exported as ALL_PROXY fills both HTTP slots")
    func proxyExit() {
        let d = dict(["ALL_PROXY": "http://127.0.0.1:10808"])
        #expect(value(kCFNetworkProxiesHTTPProxy as String, in: d) as? String == "127.0.0.1")
        #expect(value(kCFNetworkProxiesHTTPSProxy as String, in: d) as? String == "127.0.0.1")
        #expect(value(kCFNetworkProxiesSOCKSEnable as String, in: d) == nil)
    }

    @Test("scheme-specific var wins over ALL_PROXY for its own slot")
    func specificBeatsAll() {
        let d = dict([
            "HTTP_PROXY": "http://a:1",
            "ALL_PROXY": "http://b:2",
        ])
        #expect(value(kCFNetworkProxiesHTTPProxy as String, in: d) as? String == "a")
        #expect(value(kCFNetworkProxiesHTTPSProxy as String, in: d) as? String == "b")
    }

    @Test("lowercase wins where both spellings exist")
    func casePrecedence() {
        let d = dict(["http_proxy": "http://lower:1", "HTTP_PROXY": "http://upper:2"])
        #expect(value(kCFNetworkProxiesHTTPProxy as String, in: d) as? String == "lower")
    }

    @Test("scheme-less value parses as http host:port; socks scheme maps to SOCKS slot")
    func schemes() {
        let bare = dict(["http_proxy": "proxy.local:3128"])
        #expect(value(kCFNetworkProxiesHTTPProxy as String, in: bare) as? String == "proxy.local")
        #expect(value(kCFNetworkProxiesHTTPPort as String, in: bare) as? Int == 3128)

        let socks = dict(["https_proxy": "socks5h://10.0.0.1:9000"])
        #expect(value(kCFNetworkProxiesSOCKSProxy as String, in: socks) as? String == "10.0.0.1")
        #expect(value(kCFNetworkProxiesHTTPSEnable as String, in: socks) == nil)
    }

    @Test("missing port defaults by value scheme")
    func defaultPorts() {
        #expect(value(kCFNetworkProxiesHTTPPort as String, in: dict(["http_proxy": "http://p"])) as? Int == 80)
        #expect(value(kCFNetworkProxiesSOCKSPort as String, in: dict(["all_proxy": "socks5://p"])) as? Int == 1080)
    }

    @Test("garbage values are ignored, not fatal")
    func malformed() {
        #expect(dict(["http_proxy": "   "]) == nil)
        #expect(dict(["http_proxy": ":::"]) == nil)
    }

    @Test("NO_PROXY=* resolves to an explicitly-direct session, overriding system proxies")
    func wildcardBypass() {
        // `.direct` is not `.none`: the session exists and carries an empty dictionary —
        // that is what disables macOS system proxy settings too.
        guard case .direct = ProxyEnvironment.resolve(environment: [
            "HTTP_PROXY": "http://p:1", "NO_PROXY": "*",
        ]) else {
            Issue.record("expected .direct")
            return
        }
        let session = ProxyEnvironment.session(environment: [
            "HTTP_PROXY": "http://p:1", "NO_PROXY": "*",
        ])
        #expect(session?.configuration.connectionProxyDictionary as? [String: Any] != nil)
        #expect(session?.configuration.connectionProxyDictionary?.isEmpty == true)
        // `*` alone — with no proxy variable at all — must still mean "explicitly direct":
        // `.none` would fall back to `.shared`, which honors macOS *system* proxies.
        guard case .direct = ProxyEnvironment.resolve(environment: ["NO_PROXY": "*"]) else {
            Issue.record("expected .direct for bare NO_PROXY=*")
            return
        }
    }

    @Test("a socks-valued https_proxy claims https — ALL_PROXY must not overwrite it")
    func claimedScheme() {
        let d = dict([
            "https_proxy": "socks5h://secure:1080",
            "ALL_PROXY": "http://b:2",
        ])
        #expect(value(kCFNetworkProxiesHTTPSProxy as String, in: d) == nil) // not `b`
        #expect(value(kCFNetworkProxiesSOCKSProxy as String, in: d) as? String == "secure")
        #expect(value(kCFNetworkProxiesHTTPProxy as String, in: d) as? String == "b")
    }

    @Test("proxy URL userinfo maps to the credential keys")
    func credentials() {
        let d = dict(["https_proxy": "http://u%40corp:pw@proxy.local:3128"])
        #expect(value(kCFProxyUsernameKey as String, in: d) as? String == "u@corp")
        #expect(value(kCFProxyPasswordKey as String, in: d) as? String == "pw")
    }

    @Test("creds are dropped when slots route to the same host on different ports")
    func credentialsDistinctPorts() {
        let d = dict([
            "http_proxy": "http://u:p@proxy.local:8080",
            "https_proxy": "http://u:p@proxy.local:9090",
        ])
        #expect(value(kCFProxyUsernameKey as String, in: d) == nil)
        #expect(value(kCFProxyPasswordKey as String, in: d) == nil)
    }

    @Test("creds are dropped when cred-bearing variables disagree on the same endpoint")
    func credentialsDisagreeing() {
        let d = dict([
            "http_proxy": "http://u1:p1@proxy.local:8080",
            "https_proxy": "http://u2:p2@proxy.local:8080",
        ])
        #expect(value(kCFProxyUsernameKey as String, in: d) == nil)
    }

    @Test("creds are written when both variables name the same endpoint and pair")
    func credentialsSharedEndpoint() {
        let d = dict([
            "http_proxy": "http://u:p@proxy.local:8080",
            "https_proxy": "http://u:p@proxy.local:8080",
        ])
        #expect(value(kCFProxyUsernameKey as String, in: d) as? String == "u")
        #expect(value(kCFProxyPasswordKey as String, in: d) as? String == "p")
    }
}
