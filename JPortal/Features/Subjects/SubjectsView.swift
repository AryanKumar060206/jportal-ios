import JPortalKit
import SwiftUI

enum SubjectFilter: String, CaseIterable, Identifiable {
    case current = "This semester", labs = "Labs", graded = "Graded"
    var id: String { rawValue }
}

/// everything ever registered, searchable
struct SubjectsView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var filters: Set<SubjectFilter> = []

    var body: some View {
        let repo = app.repo
        let data = Academics.read(repo)
        let q = query.trimmed.lowercased()
        let groups = data.semesters.map { s in (s, s.subjects.filter { matches(s, $0, q) }) }.filter { !$0.1.isEmpty }

        Screen(refresh: {
            Academics.refreshAll(repo, force: true)
            await repo.subjectSemesters.await_(force: true)
        }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SubjectFilter.allCases) { f in
                        let on = filters.contains(f)
                        Button {
                            if on { filters.remove(f) } else { filters.insert(f) }
                        } label: {
                            Label(f.rawValue, systemImage: "checkmark")
                                .labelStyle(FilterLabel(on: on))
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(on ? JP.chip : .clear, in: Capsule())
                                .overlay(Capsule().stroke(on ? .clear : JP.outline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            if groups.isEmpty {
                if data.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    MessageState(icon: "magnifyingglass", title: !q.isEmpty ? "Nothing matches “\(query.trimmed)”" : !filters.isEmpty ? "Nothing matches these filters" : "No subjects yet")
                }
            }
            // registration is about this semester's paperwork, not a subject, so it steps aside while you search
            if q.isEmpty && filters.isEmpty {
                SectionHeader("Registration")
                RegistrationRows()
            }
            ForEach(groups, id: \.0.id) { s, list in
                SectionHeader(title: [s.number.map { "Semester \($0)" }, prettySemester(s.code)].compactMap { $0 }.joined(separator: " · ")) {
                    if s.current {
                        Text("Now").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 3).background(JP.chip, in: Capsule())
                    }
                }
                CardGroup {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, sub in
                        if i > 0 { Divided() }
                        NavigationLink(value: Route.subject(semester: sub.semesterCode, code: sub.code)) { SubjectRow(s: sub, q: q) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Subjects")
        .searchable(text: $query, prompt: "Search subjects, teachers, codes")
        .task { Academics.refreshAll(repo) }
        .task(id: (repo.gradeSemesters.data?.count ?? -1) * 1000 + (repo.subjectSemesters.data?.count ?? -1)) { Academics.refreshAll(repo) }
    }

    private func matches(_ s: SemesterInfo, _ sub: SubjectInfo, _ q: String) -> Bool {
        (!filters.contains(.current) || s.current)
            && (!filters.contains(.labs) || sub.lab)
            && (!filters.contains(.graded) || sub.grade != nil)
            && (q.isEmpty || sub.name.lowercased().contains(q) || sub.code.lowercased().contains(q) || sub.teachers.contains { $0.name.lowercased().contains(q) })
    }
}

private struct FilterLabel: LabelStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            if on { configuration.icon.font(.caption.weight(.bold)) }
            configuration.title
        }
    }
}

/// bold and tinted where the query hit, so you can see why a row is here
private func hit(_ text: String, _ q: String) -> AttributedString {
    var a = AttributedString(text)
    guard !q.isEmpty else { return a }
    var search = a.startIndex
    while let r = a[search...].range(of: q, options: .caseInsensitive) {
        a[r].foregroundColor = JP.primary
        a[r].font = .body.weight(.bold)
        search = r.upperBound
    }
    return a
}

private struct SubjectRow: View {
    let s: SubjectInfo
    let q: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit(s.name.titleCase, q)).font(.headline).lineLimit(2)
                Text(hit(s.code + (s.audit ? " · audit" : ""), q)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                ForEach(s.teachers, id: \.self) { t in
                    Text(hit("\(componentNames[t.component] ?? t.component): \(t.name.nameCase)", q)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // graded subjects show the grade, running ones show credits big, the way jportal's subjects page did
            if let g = s.grade {
                GradeLetter(grade: g)
            } else {
                Figure(value: fmt(s.credits), label: "credits", color: JP.credits)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct RegistrationRows: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let repo = app.repo
        let choiceSem = repo.choiceSemesters.data?.first
        let moocSem = repo.moocSemesters.data?.first
        let choices = choiceSem.map { repo.choices($0) }?.data
        let mooc = moocSem.map { repo.mooc($0) }?.data
        let electives = choices.map { Set($0.filter(\.isElective).map(\.basket)).count }
        let moocLine: String? = mooc.map { m in
            let approved = m.requests.count { $0.isApproved }
            let waiting = m.requests.count - approved
            let parts = [approved > 0 ? "\(approved) approved" : nil, waiting > 0 ? "\(waiting) in review" : nil, m.rejected.isEmpty ? nil : "\(m.rejected.count) rejected"].compactMap { $0 }
            return parts.isEmpty ? "No requests" : parts.joined(separator: " · ")
        }
        CardGroup {
            NavigationLink(value: Route.choices) {
                EntryRow(icon: "checklist", title: "Subject choices", subtitle: choiceSem.map { s in
                    [prettySemester(s.code), electives.flatMap { $0 > 0 ? "\($0) \($0 == 1 ? "elective" : "electives")" : nil }].compactMap { $0 }.joined(separator: " · ")
                })
            }
            Divided()
            NavigationLink(value: Route.mooc) {
                EntryRow(icon: "play.rectangle.on.rectangle", title: "MOOC status", subtitle: moocSem.map { s in [prettySemester(s.code), moocLine].compactMap { $0 }.joined(separator: " · ") })
            }
        }
        .buttonStyle(.plain)
        .task {
            await repo.choiceSemesters.await_()
            if let s = repo.choiceSemesters.data?.first { repo.choices(s).refresh() }
        }
        .task {
            await repo.moocSemesters.await_()
            if let s = repo.moocSemesters.data?.first { repo.mooc(s).refresh() }
        }
    }
}
