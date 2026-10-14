import JPortalKit
import SwiftUI

/// every in-app destination, pushed onto the tab's navigation stack
enum Route: Hashable {
    case subject(semester: String, code: String)
    case gradeCard(String)
    case marks(String)
    case choices, mooc
    case profile, fees, bank, hostel, feedback, settings, about
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(JP.primary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// rows stacked on one rounded card, like an inset grouped list
struct CardGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .card()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
    }
}

struct Divided: View {
    var body: some View { Divider().padding(.leading, 20) }
}

/// thin strip above content when what you see is cached and the refresh failed
struct StaleNotice<T: Codable & Sendable>: View {
    let store: Store<T>?

    var body: some View {
        if let store, store.error != nil, store.data != nil {
            HStack(spacing: 10) {
                Image(systemName: isOffline(store.error) ? "wifi.slash" : "exclamationmark.triangle")
                Text("\(describe(store.error)). Showing what was saved \(ago(store.fetchedAt)).")
                    .font(.footnote)
                Spacer(minLength: 0)
                Button("Retry") { store.refresh(force: true) }.font(.footnote.weight(.semibold))
            }
            .padding(12)
            .card(JP.chip, radius: 14)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .transition(.opacity)
        }
    }

    private func isOffline(_ e: Error?) -> Bool {
        if case .network = e as? PortalError { return true }
        return false
    }
}

/// a centered message with the frog's opinion of it
struct MessageState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var action: (label: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary).padding(.bottom, 4)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let action {
                Button(action.label, action: action.run).buttonStyle(.bordered).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

/**
 * the one rule for what a screen shows before its content: nothing until the
 * disk was checked, a spinner while the first fetch runs, an error with retry,
 * or an empty state. otherwise the content.
 */
struct ResourceView<T: Codable & Sendable, Content: View>: View {
    let store: Store<T>?
    var isEmpty: (T) -> Bool = { _ in false }
    var emptyTitle = "Nothing here yet"
    var emptyIcon = "tray"
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        if let store {
            if let data = store.data {
                if isEmpty(data) {
                    MessageState(icon: emptyIcon, title: emptyTitle)
                } else {
                    content(data)
                }
            } else if let error = store.error, !store.refreshing {
                MessageState(icon: "exclamationmark.icloud", title: describe(error), action: ("Try again", { store.refresh(force: true) }))
            } else if store.checked || store.refreshing {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
            } else {
                // never empty: swiftui skips .task on a view with no content, and callers hang their loads here
                Color.clear.frame(maxWidth: .infinity, minHeight: 1)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }
}

/// a semester chip that opens a menu of the given semesters
struct SemesterMenu: View {
    let semesters: [Semester]
    let selected: Semester?
    var currentLabel = false
    var highlighted = true
    let pick: (Semester, Int) -> Void

    var body: some View {
        if let selected {
            Menu {
                ForEach(Array(semesters.enumerated()), id: \.element.id) { i, s in
                    Button {
                        pick(s, i)
                    } label: {
                        if s.code == selected.code {
                            Label(prettySemester(s.code) + (currentLabel && i == 0 ? " · current" : ""), systemImage: "checkmark")
                        } else {
                            Text(prettySemester(s.code) + (currentLabel && i == 0 ? " · current" : ""))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(prettySemester(selected.code))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(highlighted ? JP.chip : .clear, in: Capsule())
                .overlay(Capsule().stroke(highlighted ? .clear : JP.outline))
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Semester, \(prettySemester(selected.code))")
        }
    }
}

/// a view's own semester picker row with the "updated" line, for lists the portal keeps apart from attendance's
struct SemesterPickerRow: View {
    let semesters: [Semester]
    let selected: Semester?
    let fetchedAt: Date?
    let pick: (String) -> Void

    var body: some View {
        HStack {
            SemesterMenu(semesters: semesters, selected: selected) { s, _ in pick(s.code) }
            Spacer()
            if let fetchedAt {
                Text("Updated \(ago(fetchedAt))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

/// jportal's grade column: the letter in its colour, sitting on a faint wash of the same colour
struct GradeLetter: View {
    let grade: String
    var size: CGFloat = 44

    var body: some View {
        let color = JP.grade(grade)
        Text(grade.isBlank ? "–" : grade)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel("Grade \(grade.isBlank ? "not out" : grade)")
    }
}

/// jportal's value-over-label column
struct Figure: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ScoreChip: View {
    let score: EventScore
    var color: Color = JP.card

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(score.event).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                switch score.marks {
                case .value(let o, let m):
                    Text(fmt(o)).font(.title3.weight(.bold)).foregroundStyle(m > 0 ? JP.marksInk(o / m) : .primary)
                    Text("of \(fmt(m))").font(.caption)
                case .absent:
                    Text("A").font(.title3.weight(.bold)).foregroundStyle(JP.bad)
                    Text("absent").font(.caption)
                default:
                    Text("–").font(.title3.weight(.bold))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(color, radius: 14)
        .accessibilityElement(children: .combine)
    }
}

/// an icon tile, a title and an optional line under it
struct EntryRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var alert = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(alert ? JP.onTertiaryContainer : .secondary)
                .frame(width: 44, height: 44)
                .background(alert ? JP.tertiaryContainer : JP.cardHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// label over value, a tap copies [copy] (the value unless told otherwise)
struct InfoRow<Trailing: View>: View {
    let label: String
    let value: String?
    var copy: String?
    @ViewBuilder var trailing: () -> Trailing
    @State private var copied = false

    var body: some View {
        if let value, !value.isBlank {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copied ? "\(label) copied" : label).font(.caption).foregroundStyle(copied ? JP.good : .secondary)
                    Text(value).font(.body).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture {
                UIPasteboard.general.string = copy ?? value
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { copied = false }
                }
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
            .accessibilityHint("Double tap to copy")
        }
    }
}

extension InfoRow where Trailing == EmptyView {
    init(_ label: String, _ value: String?, copy: String? = nil) {
        self.init(label: label, value: value, copy: copy) { EmptyView() }
    }
}

/// a screen of cards on the app's background, pull to refresh
struct Screen<Content: View>: View {
    var refresh: (() async -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { content() }
                .padding(.bottom, 24)
        }
        .background(JP.background)
        .refreshable { await refresh?() }
    }
}

/// "L" "T" "P" tags of a subject
struct ComponentTags: View {
    let subject: SubjectAttendance

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { k in
                Text(k)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(JP.chip, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityLabel(componentNames[k] ?? k)
            }
        }
    }

    private var tags: [String] {
        [subject.lectureComponent.map { _ in "L" }, subject.tutorialComponent.map { _ in "T" }, subject.practicalComponent.map { _ in "P" }].compactMap { $0 }
    }
}

/// one tick per minute, every countdown on screen reads this one clock
struct MinuteClock<Content: View>: View {
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        TimelineView(.everyMinute) { ctx in content(ctx.date) }
    }
}
