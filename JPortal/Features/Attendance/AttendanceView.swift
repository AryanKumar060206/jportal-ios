import JPortalKit
import SwiftUI

/**
 * a subject row. the percentage is always the portal's own, the class list
 * only adds the counts, the recent dots and the verdict.
 */
struct SubjectLine: Identifiable {
    let subject: SubjectAttendance
    let tally: Tally?
    /// class list still on its way, nothing final to show yet
    let counting: Bool
    let started: Bool
    let percent: Double
    let recent: [Bool]

    var id: String { subject.subjectId }

    init(_ subject: SubjectAttendance, _ daily: Store<DailyAttendance>) {
        self.subject = subject
        let classes = daily.data?.classes ?? []
        let t = daily.data.map { AttendanceMath.tally($0.classes) }
        tally = t.flatMap { $0.total > 0 ? $0 : nil }
        counting = daily.data == nil && daily.error == nil
        percent = subject.percent ?? 0
        started = tally != nil || percent > 0
        recent = AttendanceMath.recent(classes)
    }
}

struct AttendanceView: View {
    @Environment(AppModel.self) private var app
    @State private var editTarget = false

    var body: some View {
        let repo = app.repo
        let meta = repo.attendanceMeta
        let sel = SemesterSelection(app)
        let semNumber = meta.data?.header?.semesterNumber ?? ""
        let detail = sel.selected.map { repo.attendance($0, semNumber) }
        let lines = sel.selected.map { s in (detail?.data?.subjects ?? []).map { SubjectLine($0, repo.daily(s, $0)) } } ?? []
        let target = app.prefs.target

        Screen(refresh: { await refreshAll(sel.selected, semNumber, force: true) }) {
            if let at = detail?.fetchedAt {
                Text("Updated \(ago(at))").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
            }
            StaleNotice(store: detail)
            if sel.selected == nil {
                ResourceView(store: meta, isEmpty: { $0.semesters.isEmpty }, emptyTitle: "No semesters on the portal yet") { _ in EmptyView() }
            } else {
                ResourceView(store: detail, isEmpty: { $0.subjects.isEmpty }, emptyTitle: "No attendance for this semester yet", emptyIcon: "calendar.badge.clock") { _ in
                    Overview(lines: lines, target: target) { editTarget = true }
                    ForEach(lines) { line in
                        NavigationLink(value: Route.subject(semester: sel.selected!.code, code: line.subject.code)) {
                            SubjectCard(line: line, target: target)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Attendance")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SemesterMenu(semesters: sel.all, selected: sel.selected, currentLabel: true, highlighted: !sel.isCurrent) { _, i in
                    app.prefs.pinnedSemester = i == 0 ? nil : sel.all[i].code
                }
            }
        }
        .task(id: sel.selected?.id) { await refreshAll(sel.selected, semNumber, force: false) }
        .task(id: detail?.fetchedAt) {
            // the class lists back the counts and the verdict, fetch them all behind the portal's percentages
            guard let s = sel.selected else { return }
            for subject in detail?.data?.subjects ?? [] { repo.daily(s, subject).refresh() }
        }
        .sheet(isPresented: $editTarget) {
            TargetSheet(value: app.prefs.target) { app.prefs.target = $0 }
        }
    }

    private func refreshAll(_ sem: Semester?, _ semNumber: String, force: Bool) async {
        let repo = app.repo
        await repo.attendanceMeta.await_(force: force)
        guard let s = sem ?? SemesterSelection(app).selected else { return }
        let n = repo.attendanceMeta.data?.header?.semesterNumber ?? semNumber
        await repo.attendance(s, n).await_(force: force)
        await withTaskGroup(of: Void.self) { g in
            for subject in repo.attendance(s, n).data?.subjects ?? [] {
                let store = repo.daily(s, subject)
                g.addTask { await store.await_(force: force) }
            }
        }
    }
}

private struct Overview: View {
    let lines: [SubjectLine]
    let target: Int
    let onTarget: () -> Void

    var body: some View {
        let counted = lines.compactMap(\.tally)
        let total = Tally(attended: counted.reduce(0) { $0 + $1.attended }, total: counted.reduce(0) { $0 + $1.total })
        // one number, shown once every subject is in, so it never climbs while lists land
        let waiting = lines.count { $0.counting }
        let uncounted = lines.count { $0.started && $0.tally == nil }
        let startedLines = lines.filter(\.started)
        let percent: Double = waiting > 0 ? 0 : total.total > 0 ? total.percent
            : startedLines.isEmpty ? 0 : startedLines.map(\.percent).reduce(0, +) / Double(startedLines.count)
        let low = lines.count { $0.started && $0.percent < Double(target) }

        HStack(spacing: 20) {
            AttendanceRing(percent: percent, target: target, size: 116, stroke: 12) {
                if waiting > 0 {
                    ProgressView()
                } else {
                    VStack(spacing: 0) {
                        Text("\(Int(percent.rounded()))").font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("percent").font(.caption2)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(waiting > 0 ? "Counting classes"
                    : startedLines.isEmpty ? "No classes yet"
                    : low == 0 ? "All clear"
                    : low == 1 ? "1 subject below target" : "\(low) subjects below target")
                    .font(.title3.weight(.semibold))
                Text(waiting > 0 ? "\(lines.count - waiting) of \(lines.count) subjects in"
                    : total.total == 0 ? "Nothing marked this semester"
                    : uncounted > 0 ? "\(total.attended) of \(total.total) classes, \(uncounted) not counted"
                    : "\(total.attended) of \(total.total) classes attended")
                    .font(.subheadline)
                    .lineLimit(2)
                Button(action: onTarget) {
                    Text("Target \(target)%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(low == 0 ? JP.good : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .systemBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Change your attendance goal")
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(JP.onHero)
        .padding(20)
        .card(JP.hero, radius: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SubjectCard: View {
    let line: SubjectLine
    let target: Int

    var body: some View {
        let below = line.started && line.percent < Double(target)
        HStack(spacing: 16) {
            AttendanceRing(percent: line.started ? line.percent : 0, target: target, size: 60, stroke: 6, shortfall: true) {
                if line.started || !line.counting {
                    Text(line.started ? "\(Int(line.percent.rounded()))" : "–")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(line.started ? .primary : .secondary)
                }
            }
            .opacity(line.counting && !line.started ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.subject.name.titleCase).font(.headline).lineLimit(2).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    ComponentTags(subject: line.subject)
                    if line.counting {
                        RoundedRectangle(cornerRadius: 4).fill(JP.cardHigh).frame(width: 34, height: 12)
                    } else if let t = line.tally {
                        Text("\(t.attended)/\(t.total)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .accessibilityLabel("\(t.attended) of \(t.total) classes")
                        RecentDots(recent: line.recent).padding(.leading, 4)
                    }
                }
                verdict
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card(below ? JP.bad.opacity(0.08) : JP.card)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var verdict: some View {
        if line.counting {
            RoundedRectangle(cornerRadius: 4).fill(JP.cardHigh).frame(width: 84, height: 12).padding(.vertical, 3)
        } else if let t = line.tally {
            let miss = t.canMiss(target)
            let need = t.mustAttend(target)
            Text(need == Int.max ? "Can't reach \(target)% now" : need > 0 ? "Attend the next \(need)" : miss > 0 ? "Can miss \(miss)" : "Right on the edge, don't miss")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(need > 0 ? JP.bad : miss > 0 ? JP.good : JP.warn)
        } else if line.started {
            Text("Portal's %, class list didn't load").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        } else {
            Text("No classes marked yet").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/**
 * one mark per recent class, newest on the right: a filled dot for present,
 * a cross for absent. the shape carries it, the colour only backs it up.
 */
struct RecentDots: View {
    let recent: [Bool]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, present in
                if present {
                    Circle().fill(JP.good).frame(width: 7, height: 7)
                } else {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(JP.bad).frame(width: 8, height: 8)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("last \(recent.count) classes: \(recent.count { $0 }) present, \(recent.count { !$0 }) absent")
    }
}

/// attendance goal picker
struct TargetSheet: View {
    @State var value: Int
    let onDone: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Attendance goal").font(.title2.weight(.bold)).padding(.top, 24)
            Text("Subjects under this get flagged.").foregroundStyle(.secondary)
            AttendanceRing(percent: Double(value), target: 75, size: 120, stroke: 12) {
                Text("\(value)%").font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }), in: 50...100, step: 1)
                .sensoryFeedback(.selection, trigger: value)
                .accessibilityValue("\(value) percent")
            HStack {
                Spacer()
                Button("Done") {
                    onDone(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .presentationDetents([.height(380)])
        .onDisappear { onDone(value) }
    }
}
