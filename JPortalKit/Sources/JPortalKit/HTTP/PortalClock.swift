import Foundation

/**
 * the portal validates dateseq and token expiry against its own clock, which
 * drifts (measured ~8.5 min slow). every response's Date header nudges our view of it.
 */
public final class PortalClock: @unchecked Sendable {
    private let system: @Sendable () -> Date
    private let lock = NSLock()
    private var _skew: TimeInterval = 0

    public init(system: @escaping @Sendable () -> Date = { Date() }) {
        self.system = system
    }

    public var skew: TimeInterval { lock.withLock { _skew } }

    public func now() -> Date { system().addingTimeInterval(skew) }

    public func observe(_ dateHeader: String?) {
        guard let header = dateHeader, let server = PortalClock.rfc1123.date(from: header) else { return }
        let s = server.timeIntervalSince(system())
        lock.withLock { _skew = s }
    }

    public func restore(_ skew: TimeInterval) {
        lock.withLock { _skew = skew }
    }

    private static let rfc1123: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}
