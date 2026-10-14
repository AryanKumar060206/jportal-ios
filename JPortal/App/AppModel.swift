import Foundation
import JPortalKit
import Observation
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// user settings, saved as they change
@Observable
final class Prefs {
    private let d = UserDefaults.standard

    var themeMode: ThemeMode { didSet { d.set(themeMode.rawValue, forKey: "theme") } }
    var target: Int { didSet { d.set(target, forKey: "target") } }
    /// registration code the user pinned, nil means follow the current semester
    var pinnedSemester: String? { didSet { d.set(pinnedSemester, forKey: "semester") } }
    /// profile photo off until tapped, people open this app around other people
    var showPhoto: Bool { didSet { d.set(showPhoto, forKey: "show_photo") } }

    init() {
        themeMode = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        let t = d.integer(forKey: "target")
        target = t == 0 ? 75 : t
        pinnedSemester = d.string(forKey: "semester")
        showPhoto = d.bool(forKey: "show_photo")
    }

    func clearAccountBits() {
        pinnedSemester = nil
        showPhoto = false
    }
}

/// the app's object graph, one per process
@Observable
final class AppModel {
    let prefs = Prefs()
    let sessions: SessionManager
    let repo: Repository

    init() {
        let transport = Transport()
        sessions = SessionManager(transport: transport)
        repo = Repository(cache: Cache(), sessions: sessions)
    }

    func startDemo() async {
        await repo.wipe()
        await Demo.seed(repo.cache)
        sessions.signedIn(Demo.session)
    }

    func signOut() async {
        sessions.signOut()
        prefs.clearAccountBits()
        await repo.wipe()
    }
}
