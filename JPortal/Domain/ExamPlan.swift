import Foundation
import JPortalKit

struct Paper: Hashable, Identifiable {
    let event: ExamEvent
    let slot: ExamSlot

    var id: String { key }
    var key: String { "\(event.id)|\(slot.code)|\(slot.date)" }
    var day: Day? { slot.day }
    var start: Date? { day.flatMap { d in slot.start.map { d.date(at: $0) } } }
    var end: Date? { day.flatMap { d in slot.end.map { d.date(at: $0) } } }
    var duration: TimeInterval? { start.flatMap { s in end.map { $0.timeIntervalSince(s) } } }

    /// when it's surely over. no end time, three hours covers the longest sitting
    var over: Date? { end ?? start?.addingTimeInterval(3 * 3600) ?? day.map { $0.adding(days: 1).date() } }

    enum Status { case upcoming, live, done }

    func status(_ now: Date) -> Status {
        guard let o = over else { return .upcoming }
        if now >= o { return .done }
        if let s = start, now >= s { return .live }
        return .upcoming
    }

    var subjectTitle: String { slot.subjectName.titleCase }

    /// sort key, unknown dates last
    var when: Date? { start ?? day?.date() }
}

/// a day on the date sheet, [free] is the clear days since the exam day before it
struct ExamDay: Identifiable {
    let date: Day?
    let papers: [Paper]
    let free: Int
    var id: String { date?.description ?? "tbd" }
}

/// the flat paper list turned into what the exams view draws, so the ui holds no date math
struct ExamPlan {
    let now: Date
    let next: Paper?
    let days: [ExamDay]
    let done: [Paper]
    /// paper key to the paper it overlaps
    let clashes: [String: Paper]
    /// every exam day of the events still running, for the strip
    let run: [Day]

    var today: Day { Day(now) }

    static func of(_ papers: [Paper], now: Date) -> ExamPlan {
        let done = papers.filter { $0.status(now) == .done }
        let ahead = papers.filter { $0.status(now) != .done }
        let upcoming = ahead.sorted { a, b in
            switch (a.when, b.when) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            default: return false
            }
        }
        var prev: Day?
        var order: [Day?] = []
        var byDay: [Day?: [Paper]] = [:]
        for p in upcoming {
            if byDay[p.day] == nil { order.append(p.day) }
            byDay[p.day, default: []].append(p)
        }
        let days = order.map { date -> ExamDay in
            var free = 0
            if let prev, let date { free = max(0, prev.days(until: date) - 1) }
            if let date { prev = date }
            return ExamDay(date: date, papers: byDay[date]!, free: free)
        }
        var clashes: [String: Paper] = [:]
        for (day, list) in Dictionary(grouping: papers, by: \.day) where day != nil {
            for a in list { for b in list where a != b && overlaps(a, b) && clashes[a.key] == nil { clashes[a.key] = b } }
        }
        // the strip spans the events still running, done days included so you see how far in you are
        let running = Set(upcoming.map(\.event.id))
        let run = Array(Set(papers.filter { running.contains($0.event.id) }.compactMap(\.day))).sorted()
        return ExamPlan(
            now: now,
            next: upcoming.first,
            days: days,
            done: done.sorted { ($0.when ?? .distantFuture) > ($1.when ?? .distantFuture) },
            clashes: clashes,
            run: run
        )
    }

    func status(_ p: Paper) -> Paper.Status { p.status(now) }

    /// both windows known: they overlap. otherwise only the same start counts, a guessed end would cry wolf
    private static func overlaps(_ a: Paper, _ b: Paper) -> Bool {
        guard let s1 = a.start, let s2 = b.start else { return false }
        if let e1 = a.end, let e2 = b.end { return s1 < e2 && s2 < e1 }
        return s1 == s2
    }
}

func minutesLabel(_ m: Int) -> String {
    if m < 60 { return "\(m)m" }
    if m % 60 == 0 { return "\(m / 60)h" }
    return "\(m / 60)h \(m % 60)m"
}

private let testRx = try! NSRegularExpression(pattern: "\\b(?:TEST|T)[-\\s]?(\\d+)")
private let marksRx = try! NSRegularExpression(pattern: "(\\d+)\\s*-?\\s*MARKS")

extension ExamEvent {
    /// TEST-2-26ODD-20MARKS -> T2
    var short: String {
        let c = (code.isBlank ? description : code).uppercased()
        if let m = testRx.firstMatch(in: c, range: NSRange(c.startIndex..., in: c)), let r = Range(m.range(at: 1), in: c) {
            return "T\(c[r])"
        }
        if c.contains("END") { return "End sem" }
        if c.contains("MID") { return "Mid sem" }
        return (code.isBlank ? description : code).titleCase
    }

    var startDay: Day? { from.map { Day(Date(timeIntervalSince1970: TimeInterval($0) / 1000)) } }
}
