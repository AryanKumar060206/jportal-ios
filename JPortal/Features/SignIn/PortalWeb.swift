import JPortalKit
import SwiftUI
import UIKit
import WebKit

/// what the sign-in pages tell swift
enum WebSignal {
    case credential(token: String, auto: Bool)
    case loginResponse(body: String)
    case ready
    case noAuto(String)
    case failed(String)
}

/**
 * google refuses to sign in inside anything it recognises as an embedded web
 * view, and the portal's client id only trusts the portal's origin. so: look
 * like safari, and serve our own tiny page as if it came from the portal's
 * origin (loadSimulatedRequest, the ios twin of android's request intercept).
 */
enum PortalWeb {
    static let origin = "https://webportal.jiit.ac.in:6011"
    static let portalURL = URL(string: "\(origin)/studentportal/")!
    private static let signinPath = "/studentportal/jportal-signin"

    static func signinURL(clientId: String, silent: Bool, dark: Bool, width: Int) -> URL {
        var c = URLComponents(string: origin + signinPath)!
        c.queryItems = [
            URLQueryItem(name: "cid", value: clientId),
            URLQueryItem(name: "mode", value: silent ? "silent" : "button"),
            URLQueryItem(name: "theme", value: dark ? "dark" : "light"),
            URLQueryItem(name: "w", value: String(width)),
        ]
        return c.url!
    }

    /// mobile safari's own user agent for this ios version, minus nothing: wkwebview's default lacks the Version/ and Safari/ parts google looks for
    static var userAgent: String {
        let v = UIDevice.current.systemVersion
        let under = v.replacingOccurrences(of: ".", with: "_")
        let major = v.split(separator: ".").first.map(String.init) ?? "18"
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(under) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).0 Mobile/15E148 Safari/604.1"
    }

    // the page talks to `jportal.postMessage`, same as on android
    private static let bridge = """
    (function () {
      if (location.origin !== '\(origin)') return;
      window.jportal = { postMessage: function (s) { try { window.webkit.messageHandlers.jportal.postMessage(String(s)); } catch (e) {} } };
    })();
    """

    // wraps xhr and fetch so the portal's own login response reaches us (the portal page way in)
    private static let hook = """
    (function () {
      if (location.origin !== '\(origin)' || window.__jp) return; window.__jp = true;
      var hit = function (u) { return String(u).indexOf('generate-token-google-signin') >= 0; };
      var post = function (b) { try { jportal.postMessage(JSON.stringify({ type: 'login', body: b })); } catch (e) {} };
      var open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (m, u) { this.__jpu = u; return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function () {
        if (hit(this.__jpu)) { var x = this; x.addEventListener('load', function () { post(x.responseText); }); }
        return send.apply(this, arguments);
      };
      var f = window.fetch;
      if (f) window.fetch = function (u) {
        var p = f.apply(this, arguments);
        if (hit(u && u.url || u)) p.then(function (r) { r.clone().text().then(post); });
        return p;
      };
    })();
    """

    static var signinHTML: String {
        guard let url = Bundle.main.url(forResource: "signin", withExtension: "html"), let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    /// a web view wired for sign-in. popups (google's account chooser) go to [onPopup], nil when they close
    static func make(onSignal: @escaping (WebSignal) -> Void, onPopup: @escaping (WKWebView?) -> Void) -> (WKWebView, Coordinator) {
        let coordinator = Coordinator(onSignal: onSignal, onPopup: onPopup)
        let config = WKWebViewConfiguration()
        // google's session cookie lives in the default store, it's what makes silent re-auth possible later
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let ucc = config.userContentController
        ucc.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(WeakHandler(coordinator), name: "jportal")
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = userAgent
        web.uiDelegate = coordinator
        web.navigationDelegate = coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        coordinator.web = web
        return (web, coordinator)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        let onSignal: (WebSignal) -> Void
        let onPopup: (WKWebView?) -> Void
        weak var web: WKWebView?
        private var popup: WKWebView?

        init(onSignal: @escaping (WebSignal) -> Void, onPopup: @escaping (WKWebView?) -> Void) {
            self.onSignal = onSignal
            self.onPopup = onPopup
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            // only the portal origin may talk to us
            let o = message.frameInfo.securityOrigin
            guard o.protocol == "https", o.host == "webportal.jiit.ac.in", o.port == 6011,
                  let text = message.body as? String, let obj = try? JSON.parse(text) else { return }
            let s = { (k: String) in obj.str(k) }
            switch s("type") {
            case "credential": onSignal(.credential(token: s("credential"), auto: s("by").hasPrefix("auto")))
            case "login": onSignal(.loginResponse(body: s("body")))
            case "ready": onSignal(.ready)
            case "no_auto": onSignal(.noAuto(s("why")))
            case "fail": onSignal(.failed(s("why")))
            default: break
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // google's popup keeps window.opener, so it must be built from the config webkit hands us
            let p = WKWebView(frame: .zero, configuration: configuration)
            p.customUserAgent = PortalWeb.userAgent
            p.uiDelegate = self
            p.navigationDelegate = self
            popup = p
            onPopup(p)
            return p
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView === popup {
                popup = nil
                onPopup(nil)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if webView === web { onSignal(.failed("load")) }
        }
    }

    /// webkit holds message handlers strongly, this keeps the coordinator collectable
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(ucc, didReceive: message)
        }
    }
}

/// hosts a web view made elsewhere
struct WebViewHost: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// full screen host for google's sign-in popup
struct PopupSheet: View {
    let web: WKWebView
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            WebViewHost(web: web)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sign in with Google")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss) }
                }
        }
    }
}

extension WKWebView: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
