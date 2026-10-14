import Foundation

/// a calendar day with no time zone attached, the portal's dd/MM/yyyy
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// "18/09/2026", with or without anything after it
    public static func parse(ddMMyyyy s: String) -> Day? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.prefix(10).split(separator: "/")
        guard parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]),
              parts[0].count == 2, parts[1].count == 2, parts[2].count == 4 else { return nil }
        let day = Day(year: y, month: m, day: d)
        return day.isValid ? day : nil
    }

    /// "2026-09-18"
    public static func parse(iso s: String) -> Day? {
        let parts = s.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let day = Day(year: y, month: m, day: d)
        return day.isValid ? day : nil
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func today(calendar: Calendar = .current) -> Day { Day(Date(), calendar: calendar) }

    var isValid: Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        return day <= Day.daysIn(month: month, year: year)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public var daysInMonth: Int { Day.daysIn(month: month, year: year) }

    /// days since 1970-01-01, a plain count that never trips over daylight saving
    public var epochDay: Int {
        // howard hinnant's days_from_civil
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public init(epochDay z0: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    public func adding(days n: Int) -> Day { Day(epochDay: epochDay + n) }

    public func days(until other: Day) -> Int { other.epochDay - epochDay }

    /// js style, sunday is 0
    public var weekdayFromSunday: Int { ((epochDay % 7) + 7 + 4) % 7 }

    /// monday is 0
    public var weekdayFromMonday: Int { (weekdayFromSunday + 6) % 7 }

    public var firstOfMonth: Day { Day(year: year, month: month, day: 1) }

    public func addingMonths(_ n: Int) -> Day {
        let total = year * 12 + (month - 1) + n
        let y = total / 12
        let m = total % 12 + 1
        return Day(year: y, month: m, day: min(day, Day.daysIn(month: m, year: y)))
    }

    /// this day at [time], or its start, in [calendar]'s zone
    public func date(at time: ClockTime? = nil, calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = time?.hour ?? 0
        c.minute = time?.minute ?? 0
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: TimeInterval(epochDay) * 86400)
    }
}

/// a wall clock time, no day and no zone
public struct ClockTime: Hashable, Comparable, Codable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (a: ClockTime, b: ClockTime) -> Bool { (a.hour, a.minute) < (b.hour, b.minute) }

    public var minutes: Int { hour * 60 + minute }

    public var isMorning: Bool { hour < 12 }
}

// regex helpers, NSRegularExpression with swift strings

struct Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    struct Match {
        let groups: [String]
        /// whole match, in the searched string
        let range: Range<String.Index>
    }

    func first(in s: String) -> Match? {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)).map { Self.match($0, s) }
    }

    func all(in s: String) -> [Match] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { Self.match($0, s) }
    }

    func matchesWhole(_ s: String) -> Match? {
        guard let m = first(in: s), m.range == s.startIndex..<s.endIndex else { return nil }
        return m
    }

    func replacing(in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static func match(_ r: NSTextCheckingResult, _ s: String) -> Match {
        var groups: [String] = []
        for i in 0..<r.numberOfRanges {
            let nr = r.range(at: i)
            groups.append(nr.location == NSNotFound ? "" : Range(nr, in: s).map { String(s[$0]) } ?? "")
        }
        return Match(groups: groups, range: Range(r.range, in: s)!)
    }
}

extension String {
    /// runs of whitespace down to one space, then trimmed
    var squashed: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var ifBlank: String? { trimmed.isEmpty ? nil : self }
}
