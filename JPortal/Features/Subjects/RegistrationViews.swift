import JPortalKit
import SwiftUI

private func ordinal(_ n: Int) -> String {
    let suffix = (11...13).contains(n % 100) ? "th" : n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th"
    return "\(n)\(suffix)"
}

private let frozeIn: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "dd-MM-yyyy hh:mm a"
    return f
}()

struct ChoicesView: View {
    @Environment(AppModel.self) private var app
    @State private var picked: String?

    var body: some View {
        let repo = app.repo
        let list = repo.choiceSemesters.data ?? []
        let sem = list.byCode(picked) ?? list.first
        let store = sem.map { repo.choices($0) }
        let frozen = store?.data?.lazy.compactMap { frozeIn.date(from: $0.frozenAt.trimmed) }.first

        Screen(refresh: { await repo.choiceSemesters.await_(force: true); await store?.await_(force: true) }) {
            if let frozen {
                Text("Frozen on \(frozen.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
            }
            SemesterPickerRow(semesters: list, selected: sem, fetchedAt: store?.fetchedAt) { picked = $0 }
            if repo.choiceSemesters.data != nil && list.isEmpty {
                MessageState(icon: "checklist", title: "No choices this semester")
            } else {
                StaleNotice(store: store)
                ResourceView(store: store, isEmpty: { $0.isEmpty }, emptyTitle: "No choices this semester") { choices in
                    // baskets in the portal's order, picks in yours. 0 is what you got without picking, it goes first
                    let baskets = choices.reduce(into: [String]()) { if !$0.contains($1.basket) { $0.append($1.basket) } }
                    ForEach(baskets, id: \.self) { code in
                        let rows = choices.filter { $0.basket == code }
                        let ranked = rows.contains(where: \.isElective)
                        SectionHeader(title: rows[0].basketName.nonBlank?.titleCase ?? code) {
                            if ranked {
                                Text("\(rows.count { $0.isAllotted }) of \(rows.count) allotted").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        CardGroup {
                            let sorted = ranked ? rows.sorted { $0.preference < $1.preference } : rows
                            ForEach(Array(sorted.enumerated()), id: \.offset) { i, c in
                                if i > 0 { Divided() }
                                ChoiceRow(c: c, ranked: ranked)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Subject choices")
        .task { repo.choiceSemesters.refresh() }
        .task(id: sem?.id) { store?.refresh() }
    }
}

private struct ChoiceRow: View {
    let c: SubjectChoice
    let ranked: Bool

    var body: some View {
        let got = c.isAllotted
        HStack(spacing: 14) {
            if ranked {
                Text(c.preference > 0 ? ordinal(c.preference) : "–")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(got ? JP.onHero : .secondary)
                    .background(got ? JP.hero : JP.cardHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name.titleCase).font(.headline).lineLimit(2)
                Text([c.code, c.isAudit ? "audit" : nil].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if ranked && got {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(JP.primary).accessibilityLabel("Allotted")
            }
            Figure(value: fmt(c.credits), label: "credits", color: JP.credits)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(ranked && !got ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct MoocView: View {
    @Environment(AppModel.self) private var app
    @State private var picked: String?

    var body: some View {
        let repo = app.repo
        let list = repo.moocSemesters.data ?? []
        let sem = list.byCode(picked) ?? list.first
        let store = sem.map { repo.mooc($0) }

        Screen(refresh: { await repo.moocSemesters.await_(force: true); await store?.await_(force: true) }) {
            SemesterPickerRow(semesters: list, selected: sem, fetchedAt: store?.fetchedAt) { picked = $0 }
            if repo.moocSemesters.data != nil && list.isEmpty {
                MessageState(icon: "play.rectangle.on.rectangle", title: "No MOOC requests")
            } else {
                StaleNotice(store: store)
                ResourceView(store: store, isEmpty: { $0.requests.isEmpty && $0.rejected.isEmpty }, emptyTitle: "No MOOC requests") { m in
                    if m.dues > 0 {
                        Label("\(rupees(m.dues)) due", systemImage: "indianrupeesign.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(JP.onTertiaryContainer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .card(JP.tertiaryContainer, radius: 16)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                    ForEach(Array(m.requests.enumerated()), id: \.offset) { _, r in MoocCard(r: r, rejected: false) }
                    ForEach(Array(m.rejected.enumerated()), id: \.offset) { _, r in MoocCard(r: r, rejected: true) }
                }
            }
        }
        .navigationTitle("MOOC status")
        .task { repo.moocSemesters.refresh() }
        .task(id: sem?.id) { store?.refresh() }
    }
}

private struct MoocCard: View {
    let r: MoocRequest
    let rejected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name.titleCase).font(.headline)
                    Text(r.code).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer()
                if rejected {
                    Label("Rejected", systemImage: "xmark.circle.fill").foregroundStyle(JP.bad)
                } else if r.isApproved {
                    Label("Approved", systemImage: "checkmark.circle.fill").foregroundStyle(JP.primary)
                } else {
                    Label("In review", systemImage: "clock").foregroundStyle(JP.tertiary)
                }
            }
            .font(.subheadline.weight(.semibold))
            if let rep = r.replaces {
                Text("In place of \(rep.name.titleCase) · \(rep.code)")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .card(JP.cardHigh, radius: 8)
            }
            let stages = r.stages
            if !stages.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { i, st in
                        StageRow(st: st, last: i == stages.count - 1, nextDone: i + 1 < stages.count && stages[i + 1].done)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .card(JP.card, radius: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// done stages are filled with a tick, waiting ones hollow, the line between them fills once both ends are done
private struct StageRow: View {
    let st: MoocStage
    let last: Bool
    let nextDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 3) {
                if st.done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(JP.primary, in: Circle())
                } else {
                    Circle().stroke(Color.secondary, lineWidth: 2).frame(width: 18, height: 18)
                }
                if !last {
                    Capsule().fill(st.done && nextDone ? JP.primary : JP.outline).frame(width: 2).frame(minHeight: 22)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(st.title).font(.subheadline.weight(.semibold))
                let line = [st.at?.formatted(date: .abbreviated, time: .shortened), st.by?.nameCase].compactMap { $0 }.joined(separator: " · ")
                Text(line.isEmpty ? (st.done ? "Done" : "Waiting") : line).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.bottom, last ? 0 : 14)
        }
        .accessibilityElement(children: .combine)
    }
}
