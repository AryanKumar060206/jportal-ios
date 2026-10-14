import JPortalKit
import SwiftUI

struct MeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let repo = app.repo
        let session = app.sessions.session
        let personal = repo.personal.data
        let info = personal?.general
        let fees = repo.fees.data
        let hostel = repo.hostel.data
        let feedback = repo.feedback.data ?? []
        let name = info?.name.nonBlank ?? session?.name ?? ""

        Screen(refresh: {
            async let a: Void = repo.personal.await_(force: true)
            async let b: Void = repo.fees.await_(force: true)
            async let c: Void = repo.feedback.await_(force: true)
            async let d: Void = repo.hostel.await_(force: true)
            _ = await (a, b, c, d)
        }) {
            NavigationLink(value: Route.profile) {
                HStack(spacing: 16) {
                    Avatar(base64: personal?.photo, name: name, size: 64, revealOnly: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.nameCase).font(.title3.weight(.semibold))
                        Text(session?.enrollmentNo ?? "").font(.subheadline)
                        if let info {
                            Text([info.program, info.branch, info.semester > 0 ? "Sem \(info.semester)" : ""].filter { !$0.isBlank }.joined(separator: " · "))
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(20)
                .card(JP.cardHigh, radius: 28)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            SectionHeader("Money and stay")
            CardGroup {
                let due = fees?.totalDue ?? 0
                NavigationLink(value: Route.fees) {
                    EntryRow(icon: "banknote", title: "Fees", subtitle: fees == nil ? nil : due > 0 ? "\(rupees(due)) due" : "Nothing due", alert: due > 0)
                }
                Divided()
                NavigationLink(value: Route.bank) { EntryRow(icon: "building.columns", title: "Bank details") }
                Divided()
                NavigationLink(value: Route.hostel) {
                    EntryRow(icon: "bed.double", title: "Hostel", subtitle: hostel.map { h in
                        h.hostel.map { [$0.hostel.titleCase, $0.room.nonBlank.map { "Room \($0)" }].compactMap { $0 }.joined(separator: " · ") } ?? "None allotted"
                    })
                }
            }
            .buttonStyle(.plain)

            SectionHeader("College")
            CardGroup {
                NavigationLink(value: Route.feedback) {
                    EntryRow(icon: "text.bubble", title: "Feedback", subtitle: feedback.isEmpty ? "No feedback window open" : "\(feedback.count) open", alert: !feedback.isEmpty)
                }
            }
            .buttonStyle(.plain)

            SectionHeader("App")
            CardGroup {
                NavigationLink(value: Route.settings) { EntryRow(icon: "gearshape", title: "Settings", subtitle: "Theme, goal") }
                Divided()
                NavigationLink(value: Route.about) { EntryRow(icon: "info.circle", title: "About JPortal", subtitle: "Credits, licenses, sign out") }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Me")
        .task {
            repo.personal.refresh()
            repo.fees.refresh()
            repo.feedback.refresh()
            repo.hostel.refresh()
        }
    }
}

/// the portal's photo, hidden behind initials until tapped: people open this app around other people
struct Avatar: View {
    let base64: String?
    let name: String
    let size: CGFloat
    var revealOnly = false
    @Environment(AppModel.self) private var app

    var body: some View {
        let image = base64.flatMap(decode)
        let shown = app.prefs.showPhoto && image != nil
        ZStack {
            if shown, let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(JP.primary)
                Text(initials).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Color(uiColor: .systemBackground))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onTapGesture {
            // on the me card a shown photo's tap belongs to the card
            guard image != nil, !(revealOnly && app.prefs.showPhoto) else { return }
            withAnimation { app.prefs.showPhoto.toggle() }
        }
        .accessibilityLabel(shown ? "Photo" : "Initials, \(name)")
        .accessibilityHint(image == nil ? "" : shown ? "Double tap to hide photo" : "Double tap to show photo")
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }

    private func decode(_ b64: String) -> UIImage? {
        guard b64.count > 32 else { return nil }
        let raw = b64.split(separator: ",").last.map(String.init) ?? b64
        return Data(base64Encoded: raw, options: .ignoreUnknownCharacters).flatMap(UIImage.init(data:))
    }
}

/// a page over one store: stale strip, loading/error states, then [content]
struct StorePage<T: Codable & Sendable, Content: View>: View {
    let title: String
    let store: Store<T>
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        Screen(refresh: { await store.await_(force: true) }) {
            StaleNotice(store: store)
            ResourceView(store: store) { content($0) }
        }
        .navigationTitle(title)
        .task { store.refresh() }
    }
}

struct ProfileView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        StorePage(title: "Profile", store: app.repo.personal) { p in
            let g = p.general
            VStack(spacing: 4) {
                Avatar(base64: p.photo, name: g.name, size: 112)
                Text(g.name.nameCase).font(.title2.weight(.semibold)).padding(.top, 8)
                Text(g.enrollmentNo).foregroundStyle(.secondary)
                Text("Tap to copy").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            infoGroup("Academics", [
                ("Program", [g.program, g.branch].filter { !$0.isBlank }.joined(separator: " · ")),
                ("Semester", g.semester > 0 ? "\(g.semester)" : nil),
                ("Batch", [g.batch, g.section].filter { !$0.isBlank }.joined(separator: " · ")),
                ("Admitted", g.admissionYear),
                ("APAAR ID", g.apaarId),
            ])
            infoGroup("Contact", [
                ("College email", g.collegeEmail),
                ("Personal email", g.personalEmail),
                ("Phone", g.phone),
                ("Address", [g.currentAddress1, g.currentAddress3, g.currentCity, g.currentState, g.currentPin].filter { !$0.isBlank }.joined(separator: ", ")),
            ])
            infoGroup("Family", [
                ("Father", g.fatherName.nameCase),
                ("Mother", g.motherName.nameCase),
                ("Parent phone", g.parentPhone),
                ("Parent email", g.parentEmail),
            ])
            infoGroup("Personal", [
                ("Date of birth", g.dateOfBirth),
                ("Blood group", g.bloodGroup),
                ("Gender", g.gender),
                ("Category", g.category),
                ("Nationality", g.nationality),
            ])
            if !p.qualifications.isEmpty {
                infoGroup("Before JIIT", p.qualifications.map { q in
                    ("\(q.code) · \(q.board) · \(q.year)", q.percent > 0 ? String(format: "%.1f%%", q.percent) : q.cgpa > 0 ? "CGPA \(fmt(q.cgpa))" : nil)
                })
            }
        }
    }
}

/// a titled group of info rows, blank ones dropped so the dividers land between real rows
@ViewBuilder
func infoGroup(_ title: String, _ rows: [(String, String?)]) -> some View {
    let kept = rows.filter { !($0.1 ?? "").isBlank }
    if !kept.isEmpty {
        SectionHeader(title)
        CardGroup {
            ForEach(Array(kept.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divided() }
                InfoRow(r.0, r.1)
            }
        }
    }
}

struct FeesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        StorePage(title: "Fees", store: app.repo.fees) { f in
            if f.heads.isEmpty {
                MessageState(icon: "banknote", title: "No fee records")
            } else {
                CardGroup {
                    ForEach(Array(f.heads.sorted { $0.semester > $1.semester }.enumerated()), id: \.offset) { i, h in
                        if i > 0 { Divided() }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Semester \(h.semester)").font(.headline)
                                // academicyear is the same stale value on every head, so it stays out
                                Text([h.type.nonBlank, h.waived > 0 ? "\(rupees(h.waived)) waived" : nil, h.refunded > 0 ? "\(rupees(h.refunded)) refunded" : nil]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(rupees(h.paid)) paid").font(.subheadline.weight(.bold))
                                Text("of \(rupees(h.fee))").font(.footnote).foregroundStyle(.secondary)
                                if h.due > 0 { Text("\(rupees(h.due)) due").font(.caption.weight(.semibold)).foregroundStyle(JP.bad) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 8)
                if f.advance > 0 {
                    Text("\(rupees(f.advance)) held as advance").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.top, 12)
                }
            }
        }
    }
}

/// "•••• 4821": enough to recognise it, not enough to read it off over a shoulder
private func masked(_ account: String) -> String { account.count > 4 ? "•••• \(account.suffix(4))" : account }

struct BankView: View {
    @Environment(AppModel.self) private var app
    // plain state: leaving the page always masks it again
    @State private var shown = false

    var body: some View {
        StorePage(title: "Bank details", store: app.repo.bank) { b in
            CardGroup {
                InfoRow(label: "Account number", value: shown ? b.account : masked(b.account), copy: b.account) {
                    Button {
                        shown.toggle()
                    } label: {
                        Image(systemName: shown ? "eye.slash" : "eye").padding(8)
                    }
                    .accessibilityLabel(shown ? "Hide" : "Show")
                }
                let rows: [(String, String)] = [
                    ("IFSC", b.ifsc),
                    ("Bank", b.bank.titleCase),
                    ("Account holder", b.holder.nameCase),
                    ("Branch", [b.address, b.city, b.state, b.pin].filter { !$0.isBlank }.joined(separator: ", ")),
                    ("Status", b.frozen == "Y" ? "Locked by the accounts office" : "Editable on the portal"),
                ].filter { !$0.1.isBlank }
                ForEach(rows, id: \.0) { r in
                    Divided()
                    InfoRow(r.0, r.1)
                }
            }
            .padding(.top, 8)
            Text("Tap to copy").font(.footnote).foregroundStyle(.secondary).padding(20)
        }
        .task(id: shown) {
            guard shown else { return }
            try? await Task.sleep(for: .seconds(30))
            shown = false
        }
    }
}

struct HostelView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        StorePage(title: "Hostel", store: app.repo.hostel) { a in
            if let h = a.hostel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(h.hostel.titleCase).font(.title3.weight(.semibold))
                    Text("Room").font(.subheadline.weight(.medium)).padding(.top, 6)
                    Text(h.room.nonBlank ?? "–").font(.number)
                    let chips = [h.floor.nonBlank.map { "Floor \($0)" }, h.bed.nonBlank, h.roomType.nonBlank?.titleCase, h.hostelType.nonBlank?.titleCase].compactMap { $0 }
                    if !chips.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.self) { c in
                                Text(c).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color(uiColor: .systemBackground).opacity(0.55), in: Capsule())
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .foregroundStyle(JP.onHero)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .card(JP.hero, radius: 28)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                infoGroup("Dates", [("Allotted", [h.from, h.until].filter { !$0.isBlank }.joined(separator: " to ")), ("Left on", h.leftOn)])
            } else {
                MessageState(icon: "bed.double", title: "No hostel allotted", subtitle: "Day scholar, or the allotment isn't in yet.")
            }
        }
    }
}

struct FeedbackView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        StorePage(title: "Feedback", store: app.repo.feedback) { events in
            if events.isEmpty {
                MessageState(icon: "text.bubble", title: "No feedback window open", subtitle: "When the college opens one, it shows up here.")
            } else {
                CardGroup {
                    ForEach(Array(events.enumerated()), id: \.offset) { i, e in
                        if i > 0 { Divided() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.description.nonBlank ?? e.code).font(.headline)
                            Text(e.code).font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                }
                .padding(.top, 8)
                Text("Fill these in on the portal. Submitting from JPortal for iOS isn't built yet.")
                    .font(.footnote).foregroundStyle(.secondary).padding(20)
                Link(destination: PortalWeb.portalURL) {
                    Label("Open the portal", systemImage: "safari")
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $prefs.themeMode) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Stepper("Attendance goal: \(prefs.target)%", value: $prefs.target, in: 50...100)
            } footer: {
                Text("Subjects under this get flagged, and it sets how many classes you can miss.")
            }
            Section {
                Toggle("Show profile photo", isOn: $prefs.showPhoto)
            } footer: {
                Text("Off by default, people open this app around other people.")
            }
        }
        .navigationTitle("Settings")
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmSignOut = false

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        List {
            Section {
                VStack(spacing: 8) {
                    FrogMark(size: 96)
                    Text("JPortal").font(.title.weight(.bold))
                    Text("\(version) · iOS").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                Text("The JIIT webportal, as an app. Unofficial, not affiliated with or endorsed by JIIT.")
            }
            Section("Credits") {
                Link("JPortal for Android, by codelif", destination: URL(string: "https://github.com/codelif/jportal-android")!)
                Link("JPortal, by Yash Malik", destination: URL(string: "https://github.com/codeblech/jportal")!)
                Link("jsjiit (ISC) and pyjiit (MIT)", destination: URL(string: "https://github.com/codeblech/jsjiit")!)
            }
            Section {
                Text("GPL-3.0-only. Your portal session stays in this device's keychain and only ever goes to the portal. No analytics, no crash reporting.")
                    .font(.footnote)
            }
            Section {
                Button(app.sessions.isDemo ? "Leave the demo" : "Sign out", role: .destructive) { confirmSignOut = true }
            }
        }
        .navigationTitle("About")
        .confirmationDialog("Sign out of JPortal?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOut() } }
        } message: {
            Text("Saved attendance, marks and grades are cleared from this device.")
        }
    }
}
