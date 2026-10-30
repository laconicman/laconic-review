import Foundation
import OpenAPIRuntime

/// Turns an OpenAPI-runtime failure into a one-line diagnosis a human can act on.
/// `ClientError`'s default description hides the useful part — which field failed and what
/// shape arrived instead — behind `caused by "Unknown"`.
public enum ErrorExplain {
    public static func describe(_ error: Error) -> String {
        guard let e = error as? ClientError else { return String(describing: error) }
        switch e.underlyingError {
        case let d as DecodingError:
            return "\(e.operationID): response decoding failed — \(decoding(d)) — likely spec drift, check GitLabKit's openapi.yaml"
        case let u as URLError:
            return "\(e.operationID): network error — \(u.localizedDescription)"
        case let other:
            return "\(e.operationID): \(other)"
        }
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
