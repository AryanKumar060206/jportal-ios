import Foundation
import JPortalKit

private nonisolated(unsafe) var titled: [String: String] = [:]
private nonisolated(unsafe) var named: [String: String] = [:]

private let roman = try! NSRegularExpression(pattern: "^(i{1,3}|iv|v|vi{0,3}|ix|x)(-\\w+)?$", options: .caseInsensitive)
// no vowel means an acronym (DSP, DBMS). ones with vowels have to be listed
private let consonants = try! NSRegularExpression(pattern: "^[B-DF-HJ-NP-TV-XZ]{3,}$")
private let acronyms: Set<String> = ["IOT"]
private let small: Set<String> = ["And", "Of", "The", "For", "In", "To", "Using", "A", "An", "Or", "Nor", "But", "Yet", "So"]

private func whole(_ re: NSRegularExpression, _ s: String) -> Bool {
    re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)).map { $0.range.length == (s as NSString).length } ?? false
}

extension String {
    /// "DATA STRUCTURES LAB" -> "Data Structures Lab", keeps roman numerals and acronyms
    var titleCase: String {
        if let hit = titled[self] { return hit }
        let out = split(separator: " ", omittingEmptySubsequences: false).map { sub -> String in
            let w = String(sub)
            let core = w.trimmingCharacters(in: CharacterSet.letters.inverted)
            if w.isEmpty { return w }
            if whole(roman, w) { return w.uppercased() }
            if w.contains(where: \.isLowercase) { return w }
            if acronyms.contains(core) || whole(consonants, core) { return w }
            let cap = w.lowercased().prefix(1).uppercased() + w.lowercased().dropFirst()
            return small.contains(cap) ? cap.lowercased() : cap
        }.joined(separator: " ")
        let result = out.prefix(1).uppercased() + out.dropFirst()
        titled[self] = result
        return result
    }

    /// "DR. A.K.  RAO" -> "Dr. A.K. Rao". names have no acronyms, so short surnames stay words
    var nameCase: String {
        if let hit = named[self] { return hit }
        let s = trimmed
        var out = ""
        var prev: Character? = nil
        for c in s {
            if c.isWhitespace {
                if let p = prev, !p.isWhitespace { out.append(" ") }
            } else {
                out += prev.map { $0.isLetter } == true ? c.lowercased() : c.uppercased()
            }
            prev = c
        }
        named[self] = out
        return out
    }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
    var nonBlank: String? { isBlank ? nil : self }
}

private let semesterRx = try! NSRegularExpression(pattern: "(\\d{4})(ODD|EVE|EVEN|SUM|SUMMER)SEM", options: .caseInsensitive)

/// "2026ODDSEM" -> "Odd 2026"
func prettySemester(_ code: String) -> String {
    guard let m = semesterRx.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
          let y = Range(m.range(at: 1), in: code), let k = Range(m.range(at: 2), in: code) else { return code }
    let kind = switch code[k].uppercased() {
    case "ODD": "Odd"
    case "EVE", "EVEN": "Even"
    default: "Summer"
    }
    return "\(kind) \(code[y])"
}

private let termRx = try! NSRegularExpression(pattern: "(\\d{4})(ODD|EVE|EVEN)SEM")

/// where a regular term sits in time: 2025EVESEM (january) comes right before 2025ODDSEM (july). summer terms get no number
func term(_ code: String) -> Int? {
    let up = code.uppercased()
    guard let m = termRx.firstMatch(in: up, range: NSRange(up.startIndex..., in: up)),
          let y = Range(m.range(at: 1), in: up), let k = Range(m.range(at: 2), in: up), let year = Int(up[y]) else { return nil }
    return year * 2 + (up[k] == "ODD" ? 1 : 0)
}

/// 4 -> "4", 13.125 -> "13.1"
func fmt(_ d: Double) -> String {
    d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : String(format: "%.1f", d)
}

func rupees(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    f.maximumFractionDigits = 0
    return "₹" + (f.string(from: NSNumber(value: v)) ?? String(Int(v)))
}

func ago(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "never" }
    let m = Int(now.timeIntervalSince(date) / 60)
    switch m {
    case ..<1: return "just now"
    case ..<60: return "\(m)m ago"
    case ..<(24 * 60): return "\(m / 60)h ago"
    default: return "\(m / (24 * 60))d ago"
    }
}

func describe(_ e: Error?) -> String {
    switch e {
    case nil: return ""
    case is SignInRequired: return "Sign in again to refresh"
    case is DemoOnly: return "The demo has no portal behind it"
    case let p as PortalError:
        switch p {
        case .untrusted: return "The portal is having trouble on its end"
        case .network: return "You're offline"
        case .serverUnavailable: return "The portal is down right now"
        case .portal(let errors, _):
            guard let first = errors.first else { return "The portal said no" }
            let lower = first.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        case .sessionExpired: return "Session expired"
        case .emptyResponse, .malformed, .forbidden: return "The portal sent something odd"
        }
    case is MarksParseError: return "Couldn't read the marks sheet"
    default: return "Something went wrong"
    }
}

let componentNames = ["L": "Lecture", "T": "Tutorial", "P": "Practical"]

extension Array where Element == Semester {
    func byCode(_ code: String?) -> Semester? { first { $0.code == code } }
}

extension Day {
    private static let formatter = DateFormatter()

    func formatted(_ pattern: String) -> String {
        let f = Day.formatter
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f.string(from: date())
    }
}

extension ClockTime {
    /// "3:30 PM"
    var label: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h, minute, hour < 12 ? "AM" : "PM")
    }

    /// "3:30"
    var short: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", h, minute)
    }

    var meridiem: String { hour < 12 ? "AM" : "PM" }
}
