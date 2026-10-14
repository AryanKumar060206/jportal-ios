import JPortalKit
import SwiftUI
import WebKit

/// base64url(session json), the last-resort way in
func decodeSessionCode(_ code: String) -> Session? {
    var b64 = code.trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64), let s = try? JSONDecoder().decode(Session.self, from: data),
          !s.token.isBlank, !s.instituteId.isBlank else { return nil }
    return s
}

/// one sign-in web view and what it has said, kept alive across redraws
@Observable
final class SignInWeb {
    var ready = false
    var busy = false
    var error: String?
    var popup: WKWebView?
    @ObservationIgnored private(set) var web: WKWebView?
    @ObservationIgnored private var coordinator: PortalWeb.Coordinator?

    func start(_ app: AppModel, load: (WKWebView) -> Void) {
        guard web == nil else { return }
        let (w, c) = PortalWeb.make(
            onSignal: { [weak self] s in self?.handle(s, app) },
            onPopup: { [weak self] p in self?.popup = p }
        )
        web = w
        coordinator = c
        load(w)
    }

    func closePopup() {
        popup?.stopLoading()
        popup = nil
    }

    /// turns what the web page gave us into a signed-in session, or an error message
    private func handle(_ signal: WebSignal, _ app: AppModel) {
        switch signal {
        case .ready:
            ready = true
        case .credential(let token, _):
            busy = true
            popup = nil
            Task {
                do {
                    let config = await app.sessions.loadConfig()
                    let s = try await app.sessions.auth.exchangeGoogleToken(token, config: config)
                    app.sessions.signedIn(s)
                } catch {
                    self.error = describe(error)
                    busy = false
                }
            }
        case .loginResponse(let body):
            popup = nil
            if let s = try? app.sessions.auth.sessionFrom(JSON.parse(body)["response"]) {
                app.sessions.signedIn(s)
            } else {
                error = "The portal signed you in, but JPortal couldn't read it"
            }
        case .failed:
            error = "Google sign-in didn't load, check your connection"
        case .noAuto:
            break
        }
    }
}

/**
 * google's own button, rendered by google inside a small transparent web view
 * so it sits in our layout like any other control.
 */
struct GoogleButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var model = SignInWeb()
    @State private var config: PortalConfig??
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack {
                    if model.busy || config == nil {
                        ProgressView()
                    } else if let cid = config??.googleClientId, !cid.isEmpty {
                        if !model.ready { ProgressView() }
                        if let web = model.web {
                            WebViewHost(web: web).opacity(model.ready ? 1 : 0)
                        }
                        Color.clear.onAppear {
                            let w = Int(min(400, geo.size.width))
                            model.start(app) { $0.loadSimulatedRequest(URLRequest(url: PortalWeb.signinURL(clientId: cid, silent: false, dark: scheme == .dark, width: w)), responseHTML: PortalWeb.signinHTML) }
                        }
                    } else {
                        Button("Can't reach the portal, retry") { attempt += 1 }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 56)
            if let error = model.error {
                Text(error).font(.subheadline).foregroundStyle(JP.bad).multilineTextAlignment(.center)
            }
            if config == .some(nil), let e = app.sessions.configError {
                // the friendly line, then the system's own words, which are what tell a blocked network from a down portal
                Text("\(describe(e)): \(e.localizedDescription)")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .task(id: attempt) {
            config = nil
            config = .some(await app.sessions.loadConfig())
        }
        .sheet(item: Binding(get: { model.popup }, set: { if $0 == nil { model.closePopup() } })) { web in
            PopupSheet(web: web) { model.closePopup() }
        }
    }
}

/// the real portal login page, we just read its answer. for when google blocks our own page
struct PortalPageSignIn: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = SignInWeb()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(JP.bad).padding(8)
                }
                if let web = model.web { WebViewHost(web: web) }
            }
            .navigationTitle("Sign in on the portal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { model.start(app) { $0.load(URLRequest(url: PortalWeb.portalURL)) } }
        .sheet(item: Binding(get: { model.popup }, set: { if $0 == nil { model.closePopup() } })) { web in
            PopupSheet(web: web) { model.closePopup() }
        }
    }
}

private struct SessionCodeForm: View {
    @Environment(AppModel.self) private var app
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Session code", text: $code, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .card(JP.cardHigh, radius: 12)
                .onChange(of: code) { error = nil }
            Text(error ?? "From another device running JPortal")
                .font(.caption).foregroundStyle(error == nil ? Color.secondary : JP.bad)
            Button {
                if let s = decodeSessionCode(code) { app.sessions.signedIn(s) } else { error = "That code doesn't look right" }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.isBlank)
        }
    }
}

/// the other ways in, tucked under the google button
private struct OtherWays: View {
    @State private var portal = false
    @State private var code = false

    var body: some View {
        VStack(spacing: 12) {
            Button("Having trouble? Use the portal page") { portal = true }
            if code {
                SessionCodeForm().transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button("I have a session code") { withAnimation { code = true } }
            }
        }
        .font(.subheadline.weight(.medium))
        .fullScreenCover(isPresented: $portal) { PortalPageSignIn() }
    }
}

struct SignInScreen: View {
    @Environment(AppModel.self) private var app
    @State private var startingDemo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 56)
                FrogMark(size: 144)
                Text("JPortal").font(.system(size: 40, weight: .bold, design: .rounded)).padding(.top, 20)
                Text("Your attendance, marks and grades, without the portal.")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 8)
                GoogleButton().padding(.top, 48)
                Text("Use your JIIT Google account.").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                OtherWays().padding(.top, 28)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(JP.background)
        .overlay(alignment: .topTrailing) {
            Button {
                startingDemo = true
                Task { await app.startDemo() }
            } label: {
                if startingDemo { ProgressView() } else { Text("Demo").fontWeight(.semibold) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

/// shown over cached data when the token died and silent re-auth couldn't fix it
struct SignInSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Sign in again").font(.title2.weight(.bold))
                Text("Your portal session ran out.").foregroundStyle(.secondary)
                GoogleButton()
                OtherWays()
                Button("Sign out instead", role: .destructive) { Task { await app.signOut() } }
                    .font(.subheadline)
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
    }
}

/**
 * silent re-auth: an invisible web view running one tap with auto_select.
 * google hands back a credential without any ui when it still has a session.
 */
struct ReauthHost: View {
    @Environment(AppModel.self) private var app
    @State private var holder = ReauthHolder()

    var body: some View {
        Color.clear
            .frame(width: 320, height: 200)
            .background { if let web = holder.web { WebViewHost(web: web) } }
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                guard let cid = (await app.sessions.loadConfig())?.googleClientId, !cid.isEmpty else {
                    app.sessions.reauthFailed()
                    return
                }
                holder.start(app, cid)
            }
    }
}

@Observable
final class ReauthHolder {
    @ObservationIgnored private var coordinator: PortalWeb.Coordinator?
    var web: WKWebView?

    func start(_ app: AppModel, _ cid: String) {
        guard web == nil else { return }
        let (w, c) = PortalWeb.make(
            onSignal: { s in
                switch s {
                case .credential(let token, _):
                    Task {
                        do {
                            let s = try await app.sessions.auth.exchangeGoogleToken(token, config: app.sessions.config)
                            app.sessions.signedIn(s)
                        } catch {
                            app.sessions.reauthFailed()
                        }
                    }
                case .noAuto, .failed: app.sessions.reauthFailed()
                default: break
                }
            },
            // a popup means google wants the user, that's the sheet's job
            onPopup: { p in if p != nil { app.sessions.reauthFailed() } }
        )
        coordinator = c
        web = w
        w.loadSimulatedRequest(URLRequest(url: PortalWeb.signinURL(clientId: cid, silent: true, dark: false, width: 320)), responseHTML: PortalWeb.signinHTML)
    }
}
