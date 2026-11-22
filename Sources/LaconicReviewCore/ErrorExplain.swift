import Foundation
import OpenAPIRuntime

/// Turns an OpenAPI-runtime failure into a one-line diagnosis a human can act on.
/// `ClientError`'s default description hides the useful part — which field failed and what
/// shape arrived instead — behind `caused by "Unknown"`.
public enum ErrorExplain {
    /// - Parameter host: the GitLab host the client was pointed at — used to diagnose
    ///   DNS-level misrouting (see ``connectivityHint(host:)``) on transport failures.
    public static func describe(_ error: Error, host: String? = nil) -> String {
        guard let e = error as? ClientError else { return String(describing: error) }
        switch e.underlyingError {
        case let d as DecodingError:
            return "\(e.operationID): response decoding failed — \(decoding(d)) — likely spec drift, check GitLabKit's openapi.yaml"
        case let u as URLError:
            var line = "\(e.operationID): network error — \(u.localizedDescription)"
            if ProxyEnvironment.proxyDictionary(environment: ProcessInfo.processInfo.environment) != nil {
                line += " (via proxy env)"
            }
            // getaddrinfo runs only on transport-path failures — DNS misrouting is the
            // plausible cause there; spending a resolve on `.cancelled` or a 404 would
            // just add latency to the error path.
            let transportCodes: Set<URLError.Code> = [
                .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
                .networkConnectionLost, .timedOut, .notConnectedToInternet,
            ]
            if transportCodes.contains(u.code), let hint = connectivityHint(host: host) {
                line += " \(hint)"
            }
            return line
        case let other:
            return "\(e.operationID): \(other)"
        }
    }

    /// Spot the failure mode where a hostname resolves to a *synthetic* address — the
    /// fake-IP ranges tun-based VPNs hand out while owning the system resolver (sing-box /
    /// Clash-style clients use 198.18/15 and 240/4). A corp name landing there means the
    /// corp tunnel is down or another VPN's resolver hijacked the name — the TCP connect
    /// "succeeds" locally, then dies because the remote exit can't reach the intranet.
    private static func connectivityHint(host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }
        let synthetic = resolveIPv4(host).filter(isSyntheticAddress)
        guard !synthetic.isEmpty else { return nil }
        return "`\(host)` resolves to \(synthetic.joined(separator: ", ")) — reserved/fake-IP"
            + " space: a tunnel's fake resolver may own the name. Connect the corp VPN, drop"
            + " the conflicting tunnel, or `elsewhere run --exit <corp> -- laconic-review …`."
    }

    /// Reserved ranges tun engines use for fake-IP — never a routable intranet host:
    /// 198.18.0.0/15 (benchmarking; sing-box/Clash default), 240.0.0.0/4 (Class E),
    /// 100.64.0.0/10 (CGNAT — also some tunnels; Tailscale legitimately, but still worth
    /// flagging for a *corporate* name), plus the TEST-NET documentation ranges.
    private static func isSyntheticAddress(_ ip: String) -> Bool {
        let o = ip.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return false }
        let (a, b, c) = (o[0], o[1], o[2])
        if a >= 240 { return true }                          // 240.0.0.0/4
        if a == 198 && (18...19).contains(b) { return true } // 198.18.0.0/15
        if a == 100 && (64...127).contains(b) { return true } // 100.64.0.0/10
        return ((a, b) == (192, 0) && c == 2)                // 192.0.2.0/24
            || ((a, b) == (198, 51) && c == 100)             // 198.51.100.0/24
            || ((a, b) == (203, 0) && c == 113)              // 203.0.113.0/24
    }

    /// One-shot IPv4 resolution — runs only on the failure path and is bounded: on a
    /// broken resolver (exactly the scenario being diagnosed) `getaddrinfo` itself can
    /// hang for seconds, so the call runs off-thread with a 3 s ceiling.
    private static func resolveIPv4(_ host: String) -> [String] {
        // The box carries the result off the worker: read only after the semaphore
        // confirms the write finished, so a timed-out resolve never races the read.
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var addresses: [String] = []
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            var result: UnsafeMutablePointer<addrinfo>?
            if getaddrinfo(host, nil, &hints, &result) == 0, let list = result {
                defer { freeaddrinfo(list) }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var current: UnsafeMutablePointer<addrinfo>? = list
                while let info = current {
                    if let sockaddr = info.pointee.ai_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0.pointee }) {
                        var addr = sockaddr.sin_addr
                        if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                            let bytes = buffer.map { UInt8(bitPattern: $0) }
                            let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
                            box.lock.lock()
                            box.addresses.append(String(decoding: bytes[..<end], as: UTF8.self))
                            box.lock.unlock()
                        }
                    }
                    current = info.pointee.ai_next
                }
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 3) == .success else { return [] }
        box.lock.lock()
        defer { box.lock.unlock() }
        var seen = Set<String>()
        return box.addresses.filter { seen.insert($0).inserted }
    }

    private static func decoding(_ e: DecodingError) -> String {
        func path(_ c: DecodingError.Context) -> String {
            c.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch e {
        case .typeMismatch(_, let c): return "type mismatch at `\(path(c))` (\(c.debugDescription))"
        case .valueNotFound(_, let c): return "missing value at `\(path(c))` (\(c.debugDescription))"
        case .keyNotFound(let k, let c): return "missing key `\(k.stringValue)` at `\(path(c))`"
        case .dataCorrupted(let c): return "corrupted JSON (\(c.debugDescription))"
        @unknown default: return String(describing: e)
        }
    }
}
