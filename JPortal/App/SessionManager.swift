import Foundation
import JPortalKit
import Observation
import Security

/// thrown when only a visible sign in can fix things, the ui answers with the sheet
struct SignInRequired: Error {}

/// the demo student has no portal behind it
struct DemoOnly: Error {}

/**
 * the portal token in the keychain, this device only: it never rides along
 * in a backup or onto a new phone.
 */
enum SessionStore {
    private static let service = "jportal.session"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "portal"]
    }

    static func load() -> Session? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/**
 * one place that knows whether we have a usable token. tokens live 2h and
 * refresh is unreliable, so an expired session asks the ui for a silent google
 * re-auth (hidden web view, auto_select) and waits for it.
 */
@Observable
final class SessionManager {
    let transport: Transport
    let auth: Auth

    private(set) var session: Session?
    /// true while a silent re-auth is wanted, the root view hosts the hidden web view for it
    private(set) var reauthRequested = false
    /// set when silent re-auth gave up: show the sign-in sheet, keep showing cached data
    var needsSheet = false
    private(set) var config: PortalConfig?

    @ObservationIgnored private var waiter: CheckedContinuation<Session?, Never>?
    @ObservationIgnored private var renewing: Task<Session, Error>?

    private static let margin: TimeInterval = 90
    private static let reauthTimeout: Duration = .seconds(30)

    init(transport: Transport) {
        self.transport = transport
        auth = Auth(transport: transport)
        session = SessionStore.load()
    }

    var isDemo: Bool { session.map(Demo.owns) ?? false }

    /// why the last config load failed, so the sign-in screen can say more than "can't reach"
    private(set) var configError: Error?

    func loadConfig() async -> PortalConfig? {
        if let config { return config }
        do {
            let c = try await auth.config()
            config = c
            configError = nil
            return c
        } catch {
            configError = error
            print("jportal: portal config failed: \(String(reflecting: error))")
            return nil
        }
    }

    func signedIn(_ s: Session) {
        SessionStore.save(s)
        session = s
        needsSheet = false
        finishReauth(s)
    }

    func reauthFailed() {
        finishReauth(nil)
    }

    func signOut() {
        SessionStore.clear()
        session = nil
        needsSheet = false
        renewing?.cancel()
        renewing = nil
        finishReauth(nil)
    }

    private func finishReauth(_ s: Session?) {
        reauthRequested = false
        waiter?.resume(returning: s)
        waiter = nil
    }

    private func fresh(_ s: Session) -> Bool {
        guard let exp = s.expiresAt else { return true }
        return transport.clock.now().addingTimeInterval(Self.margin) < exp
    }

    private func valid(forceRenew: Bool) async throws -> Session {
        guard let current = session else { throw SignInRequired() }
        if !forceRenew && fresh(current) { return current }
        // another caller is already renewing, share its answer
        if let renewing { return try await renewing.value }
        let task = Task { () throws -> Session in
            let renewed: Session? = await withCheckedContinuation { c in
                self.waiter = c
                self.reauthRequested = true
                Task {
                    try? await Task.sleep(for: Self.reauthTimeout)
                    if self.waiter != nil { self.reauthFailed() }
                }
            }
            guard let renewed else {
                self.needsSheet = true
                throw SignInRequired()
            }
            return renewed
        }
        renewing = task
        defer { renewing = nil }
        return try await task.value
    }

    /// runs [block] with a live portal, renewing once if the server says the token died
    func call<T: Sendable>(_ block: @Sendable (Portal) async throws -> T) async throws -> T {
        let s = try await valid(forceRenew: false)
        if Demo.owns(s) { throw DemoOnly() }
        do {
            return try await block(Portal(session: s, transport: transport))
        } catch PortalError.sessionExpired {
            return try await block(Portal(session: try await valid(forceRenew: true), transport: transport))
        }
    }
}
