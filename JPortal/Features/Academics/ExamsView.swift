import EventKit
import EventKitUI
import JPortalKit
import SwiftUI

/// the date sheet for one exam semester, every event's papers flattened
struct ExamsContent: View {
    @Binding var picked: String?
    @Environment(AppModel.self) private var app
    @State private var showDone = false
    @State private var open: Paper?

    var body: some View {
        let repo = app.repo
        let sems = repo.examSemesters
        let list = sems.data ?? []
        let sem = list.byCode(picked) ?? list.first
        let store = sem.map { repo.examEvents($0) }
        let events = store?.data ?? []
        let sheets = events.map { ($0, repo.examSchedule($0)) }
        let papers = sheets.flatMap { ev, st in (st.data ?? []).map { Paper(event: ev, slot: $0) } }
        let loadingPapers = sheets.contains { $0.1.data == nil && $0.1.error == nil }

        SemesterPickerRow(semesters: list, selected: sem, fetchedAt: store?.fetchedAt) { picked = $0 }
        if sems.data != nil && list.isEmpty {
            MessageState(icon: "moon.zzz", title: "No exams on the calendar", subtitle: "Enjoy it while it lasts.")
        } else {
            StaleNotice(store: store)
            ResourceView(store: store) { _ in
                MinuteClock { now in
                    let plan = ExamPlan.of(papers, now: now)
                    let today = Day(now)
                    let pending = sheets.filter { ev, st in st.data?.isEmpty == true && (ev.startDay.map { $0 >= today } ?? false) }.map(\.0)
                    VStack(alignment: .leading, spacing: 0) {
                        if papers.isEmpty {
                            if loadingPapers {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                            } else if let first = pending.min(by: { ($0.from ?? .max) < ($1.from ?? .max) }) {
                                MessageState(icon: "eyes", title: "Date sheet's not out yet",
                                             subtitle: "\(first.short) starts around \(first.startDay?.formatted("EEEdMMM") ?? "soon"). It shows up here once the portal has it.")
                            } else {
                                MessageState(icon: "moon.zzz", title: "No exams on the calendar", subtitle: "Enjoy it while it lasts.")
                            }
                        } else {
                            if let next = plan.next {
                                NextUp(paper: next, now: now).onTapGesture { open = next }
                            } else {
                                MessageState(icon: "party.popper", title: "That's a wrap", subtitle: "Every paper on this sheet is done.")
                            }
                            if !plan.days.isEmpty {
                                SectionHeader("Date sheet")
                                ForEach(plan.days) { d in
                                    if d.free > 0 { Gap(free: d.free) }
                                    DayHeader(day: d.date, today: plan.today)
                                    CardGroup {
                                        ForEach(Array(d.papers.enumerated()), id: \.element.id) { i, p in
                                            if i > 0 { Divided() }
                                            PaperRow(p: p, plan: plan).onTapGesture { open = p }
                                        }
                                    }
                                }
                            }
                            if !pending.isEmpty {
                                CardGroup {
                                    ForEach(pending) { ev in
                                        HStack {
                                            Image(systemName: "hourglass").foregroundStyle(.secondary)
                                            Text("\(ev.short) date sheet isn't out yet").font(.subheadline)
                                            Spacer()
                                        }
                                        .padding(16)
                                    }
                                }
                                .padding(.top, 12)
                            }
                            if !plan.done.isEmpty {
                                Button {
                                    withAnimation { showDone.toggle() }
                                } label: {
                                    HStack {
                                        Text("Done · \(plan.done.count)").font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Image(systemName: showDone ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                    .padding(.bottom, 8)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(JP.primary)
                                if showDone {
                                    CardGroup {
                                        ForEach(Array(plan.done.enumerated()), id: \.element.id) { i, p in
                                            if i > 0 { Divided() }
                                            PaperRow(p: p, plan: plan).onTapGesture { open = p }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Color.clear.frame(height: 0)
            .task { sems.refresh() }
            .task(id: sem?.id) { store?.refresh() }
            .task(id: events.map(\.id)) {
                // room and seat land about a day out, so look harder then instead of waiting out the hour long cache
                let today = Day.today()
                for (_, st) in sheets {
                    let due = (st.data ?? []).contains { s in !s.seated && (s.day.map { $0 >= today && $0 <= today.adding(days: 2) } ?? false) }
                    let stale = st.fetchedAt.map { Date().timeIntervalSince($0) > 600 } ?? true
                    st.refresh(force: due && stale)
                }
            }
            .sheet(item: $open) { p in PaperSheet(paper: p) }
    }
}

private func window(_ p: Paper) -> String? {
    guard let s = p.slot.start else { return (p.slot.until.isBlank ? p.slot.from : p.slot.until).trimmed.nonBlank }
    guard let e = p.slot.end else { return s.label }
    return "\(s.isMorning == e.isMorning ? s.short : s.label) – \(e.label)"
}

private func relative(_ day: Day, _ today: Day) -> String {
    let d = today.days(until: day)
    switch d {
    case -1: return "Yesterday"
    case ..<0: return "\(-d) days ago"
    case 0: return "Today"
    case 1: return "Tomorrow"
    default: return "in \(d) days"
    }
}

private func seatLine(_ s: ExamSlot) -> String {
    [s.room.nonBlank, s.seat.nonBlank.map { "seat \($0)" }].compactMap { $0 }.joined(separator: " · ")
}

/// the countdown card for the next paper
private struct NextUp: View {
    let paper: Paper
    let now: Date

    var body: some View {
        let s = paper.slot
        VStack(alignment: .leading, spacing: 12) {
            Text("Next up · \(paper.event.short)").font(.subheadline.weight(.semibold))
            Text(paper.subjectTitle).font(.title.weight(.bold)).lineLimit(2)
            countdown
            let when = Pill(icon: "clock", text: [paper.day?.formatted("EEEdMMM"), s.start?.label].compactMap { $0 }.joined(separator: " · "))
            let room = Pill(icon: "door.left.hand.open", text: s.seated ? seatLine(s) : "Room soon")
            // side by side when they fit, stacked when a long room or big text wouldn't
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { when; room }
                VStack(alignment: .leading, spacing: 8) { when; room }
            }
        }
        .foregroundStyle(JP.onTertiaryContainer)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(JP.tertiaryContainer, radius: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var countdown: some View {
        let (n, unit): (String, String) = {
            if paper.status(now) == .live { return ("Now", "in progress") }
            guard let when = paper.when else { return ("?", "date not out") }
            let days = Day(now).days(until: Day(when))
            if days >= 1 { return ("\(days)", days == 1 ? "day to go" : "days to go") }
            let mins = max(0, Int(when.timeIntervalSince(now) / 60))
            return mins >= 60 ? ("\(mins / 60)", mins / 60 == 1 ? "hour to go" : "hours to go") : ("\(mins)", "minutes to go")
        }()
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(n).font(.system(size: 52, weight: .bold, design: .rounded))
            Text(unit).font(.title3.weight(.medium))
        }
    }
}

private struct Pill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.12), in: Capsule())
    }
}

private struct Gap: View {
    let free: Int

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(JP.outline).frame(height: 1)
            Label(free == 1 ? "1 day free" : "\(free) days free", systemImage: "bed.double").font(.caption.weight(.medium)).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(JP.outline).frame(height: 1)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
    }
}

private struct DayHeader: View {
    let day: Day?
    let today: Day

    var body: some View {
        HStack {
            Text(day?.formatted("EEEEdMMMM") ?? "Date not out yet").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
            if let day { Text(relative(day, today)).font(.subheadline.weight(.semibold)).foregroundStyle(JP.primary) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PaperRow: View {
    let p: Paper
    let plan: ExamPlan

    var body: some View {
        let done = plan.status(p) == .done
        let next = p.key == plan.next?.key
        let s = p.slot
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(s.start?.short ?? "–").font(.title3.weight(.bold)).foregroundStyle(next ? JP.tertiary : JP.primary)
                Text(s.start?.meridiem ?? "").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.subjectTitle).font(.headline).lineLimit(2)
                let meta = [p.event.short, done ? nil : s.end.map { "till \($0.label)" }, p.duration.map { minutesLabel(Int($0 / 60)) }, seatLine(s).nonBlank]
                    .compactMap { $0 }.joined(separator: " · ")
                Text(meta).font(.subheadline).foregroundStyle(.secondary)
                if !done && !s.seated {
                    Text("Room and seat come out about a day before").font(.caption).foregroundStyle(.tertiary)
                }
                if let clash = plan.clashes[p.key], !done {
                    Label("Clashes with \(clash.subjectTitle)", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(JP.bad)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(next ? JP.tertiaryContainer.opacity(0.5) : .clear)
        .opacity(done ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// one paper in full, with a way into the calendar
private struct PaperSheet: View {
    let paper: Paper
    @State private var adding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = paper.slot
        NavigationStack {
            List {
                Section {
                    LabeledContent("Exam", value: paper.event.short)
                    LabeledContent("Code", value: s.code)
                    if let d = paper.day { LabeledContent("Date", value: d.formatted("EEEEdMMMMyyyy")) }
                    if let w = window(paper) { LabeledContent("Time", value: w) }
                    LabeledContent("Room", value: s.room.nonBlank ?? "Not out yet")
                    LabeledContent("Seat", value: s.seat.nonBlank ?? "Not out yet")
                }
                if paper.when != nil {
                    Section {
                        Button {
                            adding = true
                        } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                    } footer: {
                        Text(s.seated ? "Adds the paper with its room and seat." : "Room and seat come out about a day before, check back then.")
                    }
                }
            }
            .navigationTitle(paper.subjectTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $adding) { EventEditor(paper: paper).ignoresSafeArea() }
    }
}

/// the system's own new-event screen, prefilled. it runs out of process, so no calendar permission is needed
private struct EventEditor: UIViewControllerRepresentable {
    let paper: Paper

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let s = paper.slot
        event.title = "\(paper.event.short): \(paper.subjectTitle)"
        if let start = paper.start {
            event.startDate = start
            event.endDate = paper.over ?? start.addingTimeInterval(3 * 3600)
            event.addAlarm(EKAlarm(relativeOffset: -3600))
        } else if let d = paper.day {
            event.isAllDay = true
            event.startDate = d.date()
            event.endDate = d.date()
        }
        event.location = seatLine(s).nonBlank
        event.notes = s.code
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }
}
