import JPortalKit
import SwiftUI

/**
 * the marks pdf, read into something you'd actually want to look at. exam
 * columns keep the portal's own names and order, the college's scheme is the
 * college's business.
 */
struct MarksContent: View {
    @Binding var picked: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        let repo = app.repo
        let sems = repo.marksSemesters
        let list = sems.data ?? []
        let sem = list.byCode(picked) ?? list.first
        let store = sem.map { repo.marks($0) }

        SemesterPickerRow(semesters: list, selected: sem, fetchedAt: store?.fetchedAt) { picked = $0 }
        if sems.data != nil && list.isEmpty {
            MessageState(icon: "doc.text", title: "No marks uploaded yet")
        } else {
            StaleNotice(store: store)
            ResourceView(store: store, isEmpty: { $0.subjects.isEmpty }, emptyTitle: "No marks uploaded yet", emptyIcon: "doc.text") { report in
                Summary(report: report)
                ForEach(report.subjects) { s in
                    NavigationLink(value: Route.subject(semester: sem!.code, code: s.code)) { SubjectMarksCard(s: s) }.buttonStyle(.plain)
                }
            }
        }
        Color.clear.frame(height: 0)
            .task { sems.refresh() }
            .task(id: sem?.id) { store?.refresh() }
    }
}

private func weighted(_ s: SubjectMarks) -> [(obtained: Double, max: Double)] { s.scores.compactMap { $0.weighted?.value } }

private struct Summary: View {
    let report: MarksReport

    var body: some View {
        let all = report.subjects.flatMap(weighted)
        let got = all.reduce(0) { $0 + $1.obtained }
        let max = all.reduce(0) { $0 + $1.max }
        VStack(alignment: .leading, spacing: 4) {
            Text("So far, all subjects").font(.subheadline.weight(.medium))
            HStack(alignment: .lastTextBaseline) {
                Text(fmt(got)).font(.number)
                Text("of \(fmt(max))").font(.headline)
                Spacer()
                if max > 0 { Text("\(Int(got * 100 / max))%").font(.title.weight(.bold)) }
            }
        }
        .foregroundStyle(JP.onHero)
        .padding(20)
        .card(JP.hero, radius: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct SubjectMarksCard: View {
    let s: SubjectMarks

    var body: some View {
        let shown = s.scores.filter { $0.marks != .notApplicable || $0.weighted != .notApplicable }
        let w = weighted(s)
        let got = w.reduce(0) { $0 + $1.obtained }
        let max = w.reduce(0) { $0 + $1.max }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name.titleCase).font(.headline).lineLimit(2)
                    Text(s.code).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer()
                if max > 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(fmt(got)).font(.title2.weight(.bold))
                        Text("of \(fmt(max)) so far").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if max > 0 {
                ProgressView(value: Swift.min(1, got / max)).tint(JP.marks(got / max))
            }
            if !shown.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(shown, id: \.event) { ScoreChip(score: $0, color: JP.cardHigh) } }
                }
            }
        }
        .padding(16)
        .card()
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

/// a subject's "all marks" button lands here, the same view as the tab
struct MarksScreen: View {
    @State var startAt: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        Screen(refresh: {
            await app.repo.marksSemesters.await_(force: true)
            if let s = app.repo.marksSemesters.data?.byCode(startAt) { await app.repo.marks(s).await_(force: true) }
        }) {
            MarksContent(picked: $startAt)
        }
        .navigationTitle("Marks")
    }
}
