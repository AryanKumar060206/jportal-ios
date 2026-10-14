import JPortalKit
import SwiftUI

enum AcademicsTab: String, CaseIterable, Identifiable {
    case overview = "Overview", marks = "Marks", exams = "Exams"
    var id: String { rawValue }
}

struct AcademicsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = AcademicsTab.overview
    /// projected sgpa per semester, kept while the tab lives
    @State private var projections: [Int: Double] = [:]
    @State private var marksPick: String?
    @State private var examsPick: String?

    var body: some View {
        let start = SemesterSelection(app).selected?.code
        Screen(refresh: { await refresh() }) {
            Picker("View", selection: $tab) {
                ForEach(AcademicsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .sensoryFeedback(.selection, trigger: tab)
            switch tab {
            case .overview: OverviewContent(projections: $projections)
            case .marks: MarksContent(picked: Binding(get: { marksPick ?? start }, set: { marksPick = $0 }))
            case .exams: ExamsContent(picked: Binding(get: { examsPick ?? start }, set: { examsPick = $0 }))
            }
        }
        .navigationTitle("Academics")
    }

    private func refresh() async {
        let repo = app.repo
        switch tab {
        case .overview:
            Academics.refreshAll(repo, force: true)
            async let a: Void = repo.credits.await_(force: true)
            async let b: Void = repo.program.await_(force: true)
            _ = await (a, b)
        case .marks:
            await repo.marksSemesters.await_(force: true)
            if let s = repo.marksSemesters.data?.byCode(marksPick) ?? repo.marksSemesters.data?.first { await repo.marks(s).await_(force: true) }
        case .exams:
            await repo.examSemesters.await_(force: true)
            if let s = repo.examSemesters.data?.byCode(examsPick) ?? repo.examSemesters.data?.first {
                await repo.examEvents(s).await_(force: true)
                for ev in repo.examEvents(s).data ?? [] { repo.examSchedule(ev).refresh(force: true) }
            }
        }
    }
}

// overview: the jportal grades page, headline numbers and the what-if chart

private struct OverviewContent: View {
    @Environment(AppModel.self) private var app
    @Binding var projections: [Int: Double]

    var body: some View {
        let repo = app.repo
        let data = Academics.read(repo)
        let credits = repo.credits.data
        StaleNotice(store: data.results)
        ResourceView(store: data.results, isEmpty: { $0.isEmpty }, emptyTitle: "No results yet, first semester?", emptyIcon: "graduationcap") { real in
            let maxSem = (repo.program.data?.maxSemesters).flatMap { $0 > 0 ? $0 : nil } ?? 8
            let nextCredits = credits.flatMap { $0.registeredCredits > 0 ? Double($0.registeredCredits) : nil } ?? real.last?.courseCredits ?? 20
            let points = Gpa.points(real, projections: projections, projectedCredits: nextCredits, maxSemesters: maxSem)
            let lastReal = real.map(\.semester).max() ?? 0
            let future = lastReal < maxSem ? Array((lastReal + 1)...maxSem) : []
            let latest = real.max { $0.semester < $1.semester }
            let projected = points.last.flatMap { $0.projected ? $0 : nil }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 28) {
                    Big(label: "CGPA", value: latest?.cgpa, color: JP.cgpa)
                    Big(label: "SGPA", value: latest?.sgpa, color: JP.sgpa)
                    if let projected { Big(label: "Projected", value: projected.cgpa, color: JP.tertiary) }
                }
                if let c = credits, c.required > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(c.earned)").font(.number).foregroundStyle(JP.credits)
                            Text("/ \(c.required) credits").font(.headline)
                        }
                        ProgressView(value: Double(c.earned), total: Double(c.required)).tint(JP.credits).scaleEffect(y: 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                GpaChart(points: points, future: future, maxSemester: maxSem) { s, v in projections[s] = v }
                HStack {
                    Text(projections.isEmpty ? "Tap a future semester, then drag to see where your CGPA lands" : "Dashed lines are what-ifs, not results")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if !projections.isEmpty { Button("Reset") { projections.removeAll() }.font(.subheadline.weight(.semibold)) }
                }
            }
            .padding(16)
            .card(JP.card, radius: 28)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // one row per semester opens its grade card
            let graded = data.semesters.filter { $0.result != nil }
            if !graded.isEmpty {
                SectionHeader("Semesters")
                CardGroup {
                    ForEach(Array(graded.enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Divided() }
                        NavigationLink(value: Route.gradeCard(s.code)) { SemesterRow(s: s) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: repo.attendanceMeta.data?.header?.semesterNumber) {
            Academics.refreshAll(repo)
            repo.credits.refresh()
            repo.program.refresh()
        }
        .task(id: (repo.gradeSemesters.data?.count ?? -1) * 1000 + (repo.subjectSemesters.data?.count ?? -1)) { Academics.refreshAll(repo) }
    }
}

private struct Big: View {
    let label: String
    let value: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "–").font(.number).foregroundStyle(color).contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SemesterRow: View {
    let s: SemesterInfo

    var body: some View {
        if let r = s.result {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.headline)
                    Text("\(prettySemester(s.code)) · \(fmt(r.earnedCredits)) credits").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Figure(value: String(format: "%.1f", r.sgpa), label: "SGPA", color: JP.sgpa)
                Figure(value: String(format: "%.2f", r.cgpa), label: "CGPA", color: JP.cgpa)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
}

struct GradeCardView: View {
    let code: String
    @Environment(AppModel.self) private var app

    var body: some View {
        let repo = app.repo
        let sem = repo.gradeSemesters.data?.byCode(code)
        let store = sem.map { repo.gradeCard($0) }
        let info = Academics.read(repo).semester(code)
        Screen(refresh: { await store?.await_(force: true) }) {
            StaleNotice(store: store)
            if let r = info?.result {
                HStack(spacing: 28) {
                    Big(label: "SGPA", value: r.sgpa, color: JP.sgpa)
                    Big(label: "CGPA", value: r.cgpa, color: JP.cgpa)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Credits").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(fmt(r.earnedCredits)).font(.number).foregroundStyle(JP.credits)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            ResourceView(store: store, isEmpty: { $0.entries.isEmpty }, emptyTitle: "Grade card not out yet") { card in
                CardGroup {
                    ForEach(Array(card.entries.enumerated()), id: \.offset) { i, e in
                        if i > 0 { Divided() }
                        NavigationLink(value: Route.subject(semester: code, code: e.code)) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name.titleCase).font(.headline).lineLimit(2)
                                    Text("\(e.code) · \(fmt(e.credits)) credits").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                GradeLetter(grade: e.grade)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(info?.title ?? prettySemester(code))
        .task(id: sem?.id) { store?.refresh() }
    }
}
