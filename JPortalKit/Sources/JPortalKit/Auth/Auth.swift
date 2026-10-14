import Foundation

/// what generate-token-google-signin hands back, trimmed to what we use
public struct Session: Codable, Sendable, Equatable {
    public var token: String
    /// the portal calls this Username, it's the display name and the refresh key
    public var username: String
    public var instituteId: String
    public var instituteName: String = ""
    public var clientId: String = ""
    public var memberId: String = ""
    public var userId: String = ""
    public var enrollmentNo: String = ""
    public var name: String = ""
    public var memberType: String = ""
    /// `new Date().toString()` from the moment of login, refresh wants it back verbatim
    public var tokenDate: String = ""
    public var obtainedAt: Int64 = 0

    public init(
        token: String, username: String, instituteId: String, instituteName: String = "", clientId: String = "",
        memberId: String = "", userId: String = "", enrollmentNo: String = "", name: String = "", memberType: String = "",
        tokenDate: String = "", obtainedAt: Int64 = 0
    ) {
        self.token = token
        self.username = username
        self.instituteId = instituteId
        self.instituteName = instituteName
        self.clientId = clientId
        self.memberId = memberId
        self.userId = userId
        self.enrollmentNo = enrollmentNo
        self.name = name
        self.memberType = memberType
        self.tokenDate = tokenDate
        self.obtainedAt = obtainedAt
    }

    /// tolerant of the field set other jportal builds write, missing keys take their defaults
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil ?? "" }
        token = s(.token)
        username = s(.username)
        instituteId = s(.instituteId)
        instituteName = s(.instituteName)
        clientId = s(.clientId)
        memberId = s(.memberId)
        userId = s(.userId)
        enrollmentNo = s(.enrollmentNo)
        name = s(.name)
        memberType = s(.memberType)
        tokenDate = s(.tokenDate)
        obtainedAt = (try? c.decodeIfPresent(Int64.self, forKey: .obtainedAt)) ?? nil ?? 0
    }

    /// exp claim of the jwt, in server time
    public var expiresAt: Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let exp = (try? JSON.parse(data))?["exp"].double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

public struct PortalConfig: Sendable, Equatable {
    public static let defaultLoginURL = "https://webportal.jiit.ac.in:6013/CLXSSOAPI/token/generate-token-google-signin"

    public var googleClientId: String = ""
    public var googleButtonShow: String = ""
    /// full url of the google token exchange, lives on a different port and api
    public var loginURL: String = PortalConfig.defaultLoginURL

    public var googleEnabled: Bool { googleButtonShow == "Y" && !googleClientId.isEmpty }

    init(json: JSON) {
        googleClientId = json.str("loadGoogleClientId")
        googleButtonShow = json.str("loadGoogleButtonShow")
        loginURL = json.optStr("URLapiBase")?.ifBlank ?? PortalConfig.defaultLoginURL
    }
}

public struct Auth: Sendable {
    let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public func config() async throws -> PortalConfig {
        PortalConfig(json: try await transport.get("/token/getlogoClientWise", token: nil))
    }

    /// trades a google id token (the gsi `credential`) for a portal session
    public func exchangeGoogleToken(_ credential: String, config: PortalConfig? = nil) async throws -> Session {
        var cfg = config
        if cfg == nil { cfg = try? await self.config() }
        let url = cfg?.loginURL ?? PortalConfig.defaultLoginURL
        let payload = Payload(["googleToken": .string(credential), "modulename": "studentportal"])
        return try sessionFrom(try await transport.post(url, token: nil, payload: payload, encrypt: false))
    }

    /// builds a session from the login `response` object, e.g. one sniffed out of the portal page
    public func sessionFrom(_ response: JSON) throws -> Session {
        let token = response.str("token")
        let value = response.str("value")
        if token.isEmpty || value.isEmpty { throw PortalError.malformed("login response without token") }
        let now = transport.clock.now()
        return Session(
            token: token,
            username: response.str("Username"),
            instituteId: value,
            instituteName: response.str("label"),
            clientId: response.str("clientid"),
            memberId: response.str("memberid"),
            userId: response.str("userid"),
            enrollmentNo: response.str("enrollmentno"),
            name: response.str("name"),
            memberType: response.str("membertype"),
            tokenDate: Auth.jsDateString(now),
            obtainedAt: Int64(now.timeIntervalSince1970 * 1000)
        )
    }

    /**
     * what the portal does on a 401: ask to extend the session, then retry with the
     * same token. returns true if the server said Success.
     */
    public func refresh(_ session: Session) async -> Bool {
        let payload = Payload(["username": .string(session.username), "tokendate": .string(session.tokenDate)])
        guard let res = try? await transport.post("/token/refreshTokenRequest", token: session.token, payload: payload, encrypt: false) else {
            return false
        }
        return res["msg"].string == "Success"
    }

    static func jsDateString(_ at: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = IST
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0530 (India Standard Time)'"
        return f.string(from: at)
    }
}
