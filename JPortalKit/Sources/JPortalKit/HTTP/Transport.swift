import Foundation

public final class Transport: Sendable {
    public static let defaultBaseURL = "https://webportal.jiit.ac.in:6011/StudentPortalAPI"

    public let baseURL: String
    public let clock: PortalClock
    private let session: URLSession
    private let userAgent: String?
    private let retryDelays: [Duration]

    struct Raw {
        let code: Int
        let body: Data
        let contentType: String?
    }

    public init(
        baseURL: String = Transport.defaultBaseURL,
        clock: PortalClock = PortalClock(),
        userAgent: String? = nil,
        connectTimeout: TimeInterval = 15,
        readTimeout: TimeInterval = 45,
        retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]
    ) {
        self.baseURL = baseURL
        self.clock = clock
        self.userAgent = userAgent
        self.retryDelays = retryDelays
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = readTimeout
        config.timeoutIntervalForResource = connectTimeout + readTimeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    /**
     * posts to [path] (relative to [baseURL], or absolute) and unwraps the
     * {status, response} envelope. [encrypt] sends the payload as the portal's
     * aes blob instead of json, which endpoint wants which is in the bundle.
     * pass [retry] false for anything that writes.
     */
    public func post(_ path: String, token: String?, payload: Payload?, encrypt: Bool, retry: Bool = true) async throws -> JSON {
        try await retryTransient(retry) {
            // the body is built per attempt, a retry needs it keyed to the corrected clock
            try await self.retryOnFreshSkew {
                let body = payload.map { p in encrypt ? PortalCipher.encrypt(p.serialized, at: self.clock.now()) : p.serialized }
                return try await self.exchange(path, method: "POST", token: token, body: body)
            }
        }
    }

    public func get(_ path: String, token: String?) async throws -> JSON {
        try await retryTransient(true) {
            try await self.retryOnFreshSkew { try await self.exchange(path, method: "GET", token: token, body: nil) }
        }
    }

    /// raw bytes for pdf endpoints, errors still come back as json envelopes
    public func bytes(_ path: String, token: String?) async throws -> Data {
        try await retryTransient(true) {
            let raw = try await self.exchange(path, method: "GET", token: token, body: nil)
            if raw.body.isEmpty { throw PortalError.emptyResponse }
            if raw.contentType?.contains("json") == true {
                _ = try self.unwrap(raw)
                throw PortalError.malformed("expected a file, got json")
            }
            return raw.body
        }
    }

    private func retryTransient<T>(_ enabled: Bool, _ send: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await send()
            } catch let e as PortalError {
                guard enabled, attempt < retryDelays.count, e.isTransient else { throw e }
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    /**
     * a fresh process doesn't know the server clock yet. around midnight our
     * dateseq and the server's disagree, and the portal answers with nothing.
     * that empty answer still carries a Date header, so retry once with it.
     */
    private func retryOnFreshSkew(_ send: () async throws -> Raw) async throws -> JSON {
        let before = dateSeq(clock.now())
        let raw = try await send()
        do {
            return try unwrap(raw)
        } catch PortalError.emptyResponse {
            if dateSeq(clock.now()) == before { throw PortalError.emptyResponse }
            return try unwrap(try await send())
        }
    }

    func exchange(_ path: String, method: String, token: String?, body: String?) async throws -> Raw {
        let urlString = path.hasPrefix("https://") || path.hasPrefix("http://") ? path : baseURL + path
        guard let url = URL(string: urlString) else { throw PortalError.malformed("bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        req.setValue(PortalCipher.localName(clock.now()), forHTTPHeaderField: "LocalName")
        if let userAgent { req.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let body { req.httpBody = Data(body.utf8) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError {
            switch e.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed, .clientCertificateRejected:
                throw PortalError.untrusted(e.localizedDescription)
            case .cancelled:
                throw CancellationError()
            default:
                throw PortalError.network(e.localizedDescription, timedOut: e.code == .timedOut)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw PortalError.malformed("not http") }
        clock.observe(http.value(forHTTPHeaderField: "Date"))
        return Raw(code: http.statusCode, body: data, contentType: http.value(forHTTPHeaderField: "Content-Type"))
    }

    func unwrap(_ raw: Raw) throws -> JSON {
        switch raw.code {
        case 401: throw PortalError.sessionExpired
        case 403: throw PortalError.forbidden
        default: break
        }
        let text = String(decoding: raw.body, as: UTF8.self)
        let shape = "\(raw.contentType ?? "no type"), \(raw.body.count) bytes"
        if text.trimmed.isEmpty {
            if raw.code >= 500 { throw PortalError.serverUnavailable(code: raw.code, shape: shape) }
            if raw.code >= 400 { throw PortalError.portal(errors: [], code: raw.code) }
            throw PortalError.emptyResponse
        }
        guard let root = (try? JSON.parse(raw.body))?.object else {
            if raw.code >= 500 { throw PortalError.serverUnavailable(code: raw.code, shape: shape) }
            throw PortalError.malformed("not an envelope (http \(raw.code))")
        }
        let status = root["status"]?.object
        let state = status?["responseStatus"]?.string
        if state == "Success" && raw.code < 400 { return root["response"] ?? .null }
        if raw.code >= 500 && status == nil { throw PortalError.serverUnavailable(code: raw.code, shape: shape) }
        let errors = (status?["errors"]?.array ?? []).compactMap(\.string)
        throw PortalError.portal(errors: errors, code: raw.code)
    }
}

/// the portal never redirects a real answer, a 3xx is something in the way
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
