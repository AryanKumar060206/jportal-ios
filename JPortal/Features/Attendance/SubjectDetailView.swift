import JPortalKit
import SwiftUI

/// one subject in one semester: attendance if the portal still keeps it, teachers, marks and the grade
struct SubjectDetailView: View {
    let semesterCode: String
    let subjectCode: String

    @Environment(AppModel.self) private var app
    @State private var day: Day?

    var body: some View {
        let repo = app.repo
        let target = app.prefs.target
        let meta = repo.attendanceMeta.data
        let attSem = meta?.semesters.byCode(semesterCode)
        let detail = attSem.map { repo.attendance($0, meta?.header?.semesterNumber ?? "") }
        let subject = detail?.data?.subjects.first { $0.code == subjectCode }
        let daily = attSem.flatMap { s in subject.map { repo.daily(s, $0) } }
        let classes = daily?.data?.classes ?? []
        let tally = AttendanceMath.tally(classes)

        let faculty = repo.subjectSemesters.data?.byCode(semesterCode).map { repo.subjects($0) }?.data?.rows.filter { $0.code == subjectCode } ?? []
        let marks = repo.marksSemesters.data?.byCode(semesterCode).map { repo.marks($0) }?.data?.subjects.first { $0.code == subjectCode }
        let grade = repo.gradeSemesters.data?.byCode(semesterCode).map { repo.gradeCard($0) }?.data?.entries.first { $0.code == subjectCode }
        let name = subject?.name ?? faculty.first?.name ?? grade?.name ?? marks?.name

        Screen(refresh: {
            async let a: Void = daily?.await_(force: true) ?? ()
            async let b: Void = detail?.await_(force: true) ?? ()
            _ = await (a, b)
        }) {
            if let name {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.titleCase).font(.largeTitle.weight(.bold))
                    Text("\(subjectCode) · \(prettySemester(semesterCode))").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                StaleNotice(store: daily)
                hero(subject, tally, target, grade, faculty)
                if let subject {
                    components(subject, Dictionary(faculty.map { ($0.component, $0.facultyName) }, uniquingKeysWith: { a, _ in a }))
                } else if !faculty.isEmpty {
                    SectionHeader("Taught by")
                    CardGroup {
                        let rows = faculty.filter { !$0.facultyName.isBlank }.reduce(into: [SubjectFaculty]()) { acc, f in if !acc.contains(where: { $0.component == f.component }) { acc.append(f) } }
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, f in
                            if i > 0 { Divided() }
                            InfoRow(componentNames[f.component] ?? f.component, f.facultyName.nameCase)
                        }
                    }
                }
                let cal = AttendanceMath.calendar(classes)
                if !cal.isEmpty {
                    SectionHeader("Calendar")
                    AttendanceCalendar(marks: cal, selected: $day)
                    if let d = day {
                        let list = classes.filter { $0.date == d }
                        if list.isEmpty {
                            Text(d > Day.today() ? "Nothing marked yet for \(d.formatted("EEEdMMM"))" : "No class on \(d.formatted("EEEdMMM"))")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                        } else {
                            VStack(spacing: 0) { ForEach(Array(list.enumerated()), id: \.offset) { _, c in ClassRow(c: c) } }
                                .padding(.top, 6)
                        }
                    }
                }
                let trend = AttendanceMath.trend(classes).map(\.1)
                if trend.count >= 3 {
                    SectionHeader("How it's been going")
                    TrendChart(values: trend, target: target).padding(.horizontal, 20)
                }
                if let marks, marks.scores.contains(where: { $0.marks != .notApplicable }) {
                    SectionHeader(title: "Marks") {
                        NavigationLink("All marks", value: Route.marks(semesterCode)).font(.subheadline)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(marks.scores.filter { $0.marks != .notApplicable || $0.weighted != .notApplicable }, id: \.event) { ScoreChip(score: $0) }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                if subject != nil, let f = faculty.first {
                    Text("\(fmt(f.credits)) credits" + (f.isAudit ? " · audit" : ""))
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
                }
                if !classes.isEmpty {
                    SectionHeader("Every class")
                    LazyVStack(spacing: 0) {
                        ForEach(Array(AttendanceMath.chronological(classes).reversed().enumerated()), id: \.offset) { _, c in ClassRow(c: c) }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            repo.attendanceMeta.refresh()
            repo.subjectSemesters.refresh()
            repo.marksSemesters.refresh()
            repo.gradeSemesters.refresh()
        }
        .task(id: attSem?.id) { detail?.refresh() }
        .task(id: subject?.subjectId) { daily?.refresh() }
        .task(id: repo.subjectSemesters.data?.count) { if let s = repo.subjectSemesters.data?.byCode(semesterCode) { repo.subjects(s).refresh() } }
        .task(id: repo.marksSemesters.data?.count) { if let s = repo.marksSemesters.data?.byCode(semesterCode) { repo.marks(s).refresh() } }
        .task(id: repo.gradeSemesters.data?.count) { if let s = repo.gradeSemesters.data?.byCode(semesterCode) { repo.gradeCard(s).refresh() } }
    }

    @ViewBuilder
    private func hero(_ subject: SubjectAttendance?, _ tally: Tally, _ target: Int, _ grade: GradeEntry?, _ faculty: [SubjectFaculty]) -> some View {
        VStack(spacing: 14) {
            if let subject {
                let pct = subject.percent ?? 0
                // same rule as the list card: nothing counted and nothing from the portal means it hasn't started
                let started = tally.total > 0 || pct > 0
                AttendanceRing(percent: started ? pct : 0, target: target, size: 184, stroke: 16, shortfall: true) {
                    VStack(spacing: 2) {
                        Text(started ? "\(Int(pct.rounded()))%" : "–").font(.number).foregroundStyle(started ? .primary : .secondary)
                        if tally.total > 0 { Text("\(tally.attended) of \(tally.total)").font(.subheadline.weight(.medium)) }
                    }
                }
                if tally.total > 0 {
                    Verdict(miss: tally.canMiss(target), need: tally.mustAttend(target), target: target, exact: tally.attended * 100 == target * tally.total)
                } else if !started {
                    Text("No classes marked yet").font(.subheadline).foregroundStyle(.secondary)
                }
                if let g = grade?.grade.nonBlank {
                    Text("Grade \(g)").font(.headline).foregroundStyle(JP.grade(g))
                }
            } else {
                // no attendance kept for this semester any more, the grade is the headline
                GradeLetter(grade: grade?.grade ?? "", size: 120)
                let credits = faculty.first?.credits ?? grade?.credits
                let line = [credits.map { "\(fmt($0)) credits" }, grade.flatMap { $0.gradePoint > 0 ? "\(fmt($0.gradePoint)) grade points" : nil }].compactMap { $0 }.joined(separator: " · ")
                Text(line.isEmpty ? "Grade not out yet" : line).font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func components(_ s: SubjectAttendance, _ faculty: [String: String]) -> some View {
        let rows: [(String, String, Double?)] = [
            s.lectureComponent.map { _ in ("L", "Lecture", s.lecturePercent) },
            s.tutorialComponent.map { _ in ("T", "Tutorial", s.tutorialPercent) },
            s.practicalComponent.map { _ in ("P", "Practical", s.practicalPercent) },
        ].compactMap { $0 }
        if !rows.isEmpty {
            SectionHeader("Components")
            VStack(spacing: 8) {
                ForEach(rows, id: \.0) { k, name, pct in
                    HStack(spacing: 14) {
                        Text(k).font(.headline).frame(width: 36, height: 36).background(JP.chip, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.subheadline.weight(.semibold))
                            if let f = faculty[k] { Text(f.nameCase).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if let pct { Text("\(Int(pct.rounded()))%").font(.headline.weight(.bold)) }
                    }
                    .padding(14)
                    .card(JP.card, radius: 18)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            Text("Component percentages are the portal's own, updated once a day.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}

private struct Verdict: View {
    let miss: Int
    let need: Int
    let target: Int
    let exact: Bool

    var body: some View {
        let (text, color): (String, Color) =
            if need == Int.max { ("Can't reach \(target)% any more this semester", JP.bad) }
            else if need > 0 { ("Attend the next \(need) \(need == 1 ? "class" : "classes") to reach \(target)%", JP.bad) }
            else if miss > 0 { ("You can miss \(miss) \(miss == 1 ? "class" : "classes") and stay above \(target)%", JP.good) }
            // no absence to spare yet not under: 18/27 is 66.7, 18/28 is 64.3
            else { ("\(exact ? "Exactly on" : "Just above") \(target)%, the next absence drops you under", JP.warn) }
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(color.opacity(0.14), in: Capsule())
            .padding(.horizontal, 16)
    }
}

private struct ClassRow: View {
    let c: ClassRecord

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: c.isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(c.isPresent ? JP.good : JP.bad)
                .accessibilityLabel(c.isPresent ? "Present" : "Absent")
            VStack(alignment: .leading, spacing: 2) {
                Text(c.date?.formatted("EEEdMMM") ?? c.datetime).font(.body)
                let time = [c.start?.label, c.end?.label].compactMap { $0 }.joined(separator: " – ")
                let meta = [time, c.classType != "Regular" ? c.classType : "", c.takenBy.nameCase].filter { !$0.isBlank }.joined(separator: " · ")
                Text(meta).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
