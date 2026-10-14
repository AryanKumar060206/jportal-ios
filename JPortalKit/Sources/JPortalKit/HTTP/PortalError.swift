import Foundation

public enum PortalError: Error, Sendable, Equatable {
    /// 401, token is past its 2h life
    case sessionExpired
    /// 403, usually a bad Origin or a token the server refuses outright
    case forbidden
    /// 5xx, the portal falls over a lot during result season. shape is content type and size, never the body
    case serverUnavailable(code: Int, shape: String)
    /// 200 with nothing in it, what you get for a bad LocalName
    case emptyResponse
    /// the envelope said Failure
    case portal(errors: [String], code: Int)
    case malformed(String)
    /// tls failed: an expired or wrong certificate, or something in the middle. never worth a retry
    case untrusted(String)
    case network(String, timedOut: Bool)

    /// "NO ... FOUND" style answers, which really mean an empty list
    public var isNoData: Bool {
        guard case .portal(let errors, _) = self else { return false }
        return errors.contains { e in
            e.range(of: "NO ", options: .caseInsensitive) != nil && e.range(of: "FOUND", options: .caseInsensitive) != nil
        }
    }

    /// the portal's gateway drops the odd request under load and answers fine a second later
    var isTransient: Bool {
        switch self {
        case .serverUnavailable, .emptyResponse: return true
        // a timeout already cost us 45s, don't make it three
        case .network(_, let timedOut): return !timedOut
        default: return false
        }
    }
}

extension PortalError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sessionExpired: return "session expired"
        case .forbidden: return "forbidden"
        case .serverUnavailable(let code, _): return "server unavailable (\(code))"
        case .emptyResponse: return "empty response"
        case .portal(let errors, let code): return errors.isEmpty ? "portal error (\(code))" : errors.joined(separator: "; ")
        case .malformed(let m): return m
        case .untrusted(let m): return m
        case .network(let m, _): return m
        }
    }
}
