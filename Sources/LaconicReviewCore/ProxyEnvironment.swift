import CFNetwork
import Foundation

/// Reads the conventional proxy environment into a `URLSession` proxy dictionary.
///
/// `URLSession` does **not** honor `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY` — those
/// are the curl convention that launcher tools (notably `elsewhere run --exit … --`) export
/// into a child's environment. This type is the bridge: parse the variables once, hand the
/// resulting session to the GitLab client, and every request routes through the proxy.
///
/// Parsing rules (curl-derived, deliberately small):
/// - Lookup tries the lowercase spelling first. Where curl goes further — it *ignores*
///   uppercase `HTTP_PROXY` outright (httpoxy: a CGI `Proxy:` header must never become
///   config) — this is a CLI, not CGI, so we accept uppercase too; `elsewhere run`
///   exports uppercase and honoring it here is the point.
/// - The variable picks the *request* scheme it covers (`http_proxy` → http traffic,
///   `https_proxy` → https); the value's scheme picks the proxy *type*
///   (`http(s)://` → HTTP proxy, `socks*` → SOCKS).
/// - `ALL_PROXY` fills whichever slots remain unset — SOCKS stays the catch-all it is in
///   `CFNetwork` when its value is a socks URL.
/// - A value without `://` is treated as `host[:port]`; a missing port defaults by the
///   value's scheme (http→80, https→443, socks*→1080, otherwise 1080).
/// - `NO_PROXY` is a comma-separated host/suffix list → `ExceptionsList`; the single
///   wildcard `*` disables proxies entirely — including macOS *system* proxy settings,
///   so `session` returns an explicitly-direct session rather than `nil`.
/// - `user:password@` in a proxy URL maps to `kCFProxyUsernameKey`/`kCFProxyPasswordKey` —
///   shared keys, written only when every filled slot is the same `host:port` endpoint
///   and the cred-bearing variables agree on one pair; across distinct endpoints they
///   would leak Basic auth to the wrong proxy, so they're dropped instead.
///
/// Two limits the dictionary can't express, both fail closed toward *more* proxying:
/// a socks-valued scheme variable fills the single global SOCKS slot, so it may also
/// catch the other scheme's traffic; and an `https://` proxy *value* maps to a plain
/// HTTP CONNECT — a TLS-only proxy would fail, which errs toward not connecting rather
/// than silently going direct.
public enum ProxyEnvironment {
    /// What the environment resolves to — `.direct` is "explicitly no proxy" (`NO_PROXY=*`),
    /// distinct from `.none` ("nothing configured — keep the default session, system proxy
    /// settings included").
    public enum Resolution {
        case none
        case direct
        case proxy([String: Any])
        /// Convenience for tests and logging; `.direct`/`.none` carry no dictionary.
        public var proxyDictionary: [String: Any]? {
            guard case .proxy(let d) = self else { return nil }
            return d
        }
    }

    /// Parse the environment into a ``Resolution`` — see the enum docstring for semantics.
    public static func resolve(environment env: [String: String]) -> Resolution {
        var dict: [String: Any] = [:]
        // A scheme is "claimed" only when its variable actually parsed — a garbage value
        // must not shadow ALL_PROXY into silence.
        let httpSpec = envValue("http_proxy", "HTTP_PROXY", in: env).flatMap(parse)
        let httpsSpec = envValue("https_proxy", "HTTPS_PROXY", in: env).flatMap(parse)
        apply(httpSpec, httpSlot: true, httpsSlot: false, socksSlot: true, into: &dict)
        apply(httpsSpec, httpSlot: false, httpsSlot: true, socksSlot: true, into: &dict)
        let allSpec = envValue("all_proxy", "ALL_PROXY", in: env).flatMap(parse)
        apply(
            allSpec,
            httpSlot: allSpec?.kind == .http && httpSpec == nil,
            httpsSlot: allSpec?.kind == .http && httpsSpec == nil,
            socksSlot: true, fillOnly: true, into: &dict
        )
        // `NO_PROXY=*` must win even with no proxy variables at all: `.none` would fall
        // back to the default session, which still honors macOS *system* proxy settings.
        let exceptions = envValue("no_proxy", "NO_PROXY", in: env)?.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty } ?? []
        if exceptions.contains("*") { return .direct }
        let proxyKeys: Set<String> = [
            kCFNetworkProxiesHTTPEnable as String, kCFNetworkProxiesHTTPSEnable as String,
            kCFNetworkProxiesSOCKSEnable as String,
        ]
        guard dict.keys.contains(where: proxyKeys.contains) else { return .none }
        // Credentials are global keys — writing them when the filled slots route to
        // different endpoints would hand one proxy's Basic auth to another. An endpoint
        // is host *and* port: `proxy:8080` vs `proxy:9090` are different services on one
        // host. Only write creds when every filled slot is the same endpoint and the
        // cred-bearing variables agree on one user/password pair.
        let endpoints = [
            (kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort),
            (kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort),
            (kCFNetworkProxiesSOCKSProxy, kCFNetworkProxiesSOCKSPort),
        ].compactMap { hostKey, portKey -> String? in
            guard let host = dict[hostKey as String] as? String,
                  let port = dict[portKey as String] as? Int else { return nil }
            return "\(host):\(port)"
        }
        let credSpecs = [httpSpec, httpsSpec, allSpec].compactMap { $0 }.filter { $0.user != nil }
        if Set(endpoints).count == 1, let creds = credSpecs.first,
           credSpecs.allSatisfy({ $0.user == creds.user && $0.password == creds.password }) {
            dict[kCFProxyUsernameKey as String] = creds.user
            if let password = creds.password {
                dict[kCFProxyPasswordKey as String] = password
            }
        }
        if !exceptions.isEmpty {
            // CFNetwork wants host/domain suffixes; `*.` is the env-file spelling of one.
            dict[kCFNetworkProxiesExceptionsList as String] = exceptions.map {
                $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0
            }
        }
        return .proxy(dict)
    }

    /// The dictionary for `URLSessionConfiguration.connectionProxyDictionary`, or `nil`
    /// when no proxy variable is set — the caller then keeps the default transport.
    public static func proxyDictionary(environment env: [String: String]) -> [String: Any]? {
        resolve(environment: env).proxyDictionary
    }

    /// A `URLSession` honoring the environment's proxy variables — `nil` when none are set.
    /// `NO_PROXY=*` returns a session with an *empty* proxy dictionary, which is what
    /// "direct" means on macOS: it also overrides system proxy settings the default
    /// session would honor. Ephemeral configuration: no caches or cookies persist.
    public static func session(
        environment env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URLSession? {
        let configuration = URLSessionConfiguration.ephemeral
        switch resolve(environment: env) {
        case .none:
            return nil
        case .direct:
            configuration.connectionProxyDictionary = [:]
        case .proxy(let dict):
            configuration.connectionProxyDictionary = dict
        }
        return URLSession(configuration: configuration)
    }

    // MARK: - Env plumbing

    /// Lowercase spelling wins; falls back to uppercase (`elsewhere run` exports uppercase).
    private static func envValue(_ lower: String, _ upper: String, in env: [String: String]) -> String? {
        env[lower] ?? env[upper]
    }

    private enum ProxyKind { case http, socks }

    private struct ProxySpec {
        let kind: ProxyKind
        let host: String
        let port: Int
        let user: String?
        let password: String?
    }

    /// Write `spec` into the slots it qualifies for; `fillOnly` keeps existing slots intact
    /// (that is how `ALL_PROXY` behaves relative to the scheme-specific variables).
    private static func apply(
        _ spec: ProxySpec?, httpSlot: Bool, httpsSlot: Bool, socksSlot: Bool,
        fillOnly: Bool = false, into dict: inout [String: Any]
    ) {
        guard let spec else { return }
        switch spec.kind {
        case .http:
            if httpSlot && (!fillOnly || dict[kCFNetworkProxiesHTTPEnable as String] == nil) {
                dict[kCFNetworkProxiesHTTPEnable as String] = true
                dict[kCFNetworkProxiesHTTPProxy as String] = spec.host
                dict[kCFNetworkProxiesHTTPPort as String] = spec.port
            }
            if httpsSlot && (!fillOnly || dict[kCFNetworkProxiesHTTPSEnable as String] == nil) {
                dict[kCFNetworkProxiesHTTPSEnable as String] = true
                dict[kCFNetworkProxiesHTTPSProxy as String] = spec.host
                dict[kCFNetworkProxiesHTTPSPort as String] = spec.port
            }
        case .socks:
            if socksSlot && (!fillOnly || dict[kCFNetworkProxiesSOCKSEnable as String] == nil) {
                dict[kCFNetworkProxiesSOCKSEnable as String] = true
                dict[kCFNetworkProxiesSOCKSProxy as String] = spec.host
                dict[kCFNetworkProxiesSOCKSPort as String] = spec.port
            }
        }
    }

    private static func parse(_ value: String) -> ProxySpec? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URLComponents(string: candidate), let host = url.host else { return nil }
        let user = url.user.map { $0.removingPercentEncoding ?? $0 }
        let password = url.password.map { $0.removingPercentEncoding ?? $0 }
        switch url.scheme?.lowercased() {
        case "http", "https":
            let fallback = url.scheme?.lowercased() == "https" ? 443 : 80
            return ProxySpec(kind: .http, host: host, port: url.port ?? fallback, user: user, password: password)
        case "socks", "socks4", "socks4a", "socks5", "socks5h":
            // `socks5h` means remote DNS — which is also the only DNS mode CFNetwork's
            // SOCKS entry offers, so both spellings collapse into it correctly.
            return ProxySpec(kind: .socks, host: host, port: url.port ?? 1080, user: user, password: password)
        default:
            return nil
        }
    }
}
