import JPortalKit
import SwiftUI

@main
struct JPortalApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.prefs.themeMode.scheme)
                .tint(JP.primary)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var sessions = app.sessions
        ZStack {
            if app.sessions.session == nil {
                SignInScreen().transition(.opacity)
            } else {
                MainTabs().transition(.opacity)
            }
            if app.sessions.reauthRequested { ReauthHost() }
        }
        .animation(.easeInOut(duration: 0.25), value: app.sessions.session == nil)
        .sheet(isPresented: $sessions.needsSheet) { SignInSheet() }
    }
}

enum Tab: Hashable { case attendance, academics, subjects, me }

struct MainTabs: View {
    @State private var tab = Tab.attendance

    var body: some View {
        TabView(selection: $tab) {
            TabStack { AttendanceView() }
                .tabItem { Label("Attendance", systemImage: "checklist") }
                .tag(Tab.attendance)
            TabStack { AcademicsView() }
                .tabItem { Label("Academics", systemImage: "graduationcap") }
                .tag(Tab.academics)
            TabStack { SubjectsView() }
                .tabItem { Label("Subjects", systemImage: "book") }
                .tag(Tab.subjects)
            TabStack { MeView() }
                .tabItem { Label("Me", systemImage: "person") }
                .tag(Tab.me)
        }
    }
}

/// one tab's navigation stack, every route resolves the same way from any tab
struct TabStack<Root: View>: View {
    @ViewBuilder var root: () -> Root
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .subject(let sem, let code): SubjectDetailView(semesterCode: sem, subjectCode: code)
                    case .gradeCard(let code): GradeCardView(code: code)
                    case .marks(let code): MarksScreen(startAt: code)
                    case .choices: ChoicesView()
                    case .mooc: MoocView()
                    case .profile: ProfileView()
                    case .fees: FeesView()
                    case .bank: BankView()
                    case .hostel: HostelView()
                    case .feedback: FeedbackView()
                    case .settings: SettingsView()
                    case .about: AboutView()
                    }
                }
        }
    }
}

/// the one semester every screen follows: the head of the attendance list unless the user pinned another
struct SemesterSelection {
    let all: [Semester]
    let selected: Semester?
    var isCurrent: Bool { selected?.id == all.first?.id }

    init(_ app: AppModel) {
        all = app.repo.attendanceMeta.data?.semesters ?? []
        selected = all.byCode(app.prefs.pinnedSemester) ?? all.first
    }
}
