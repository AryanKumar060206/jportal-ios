import Foundation

/**
 * reads the "Subject Marks(Event Wise)" pdf. every cell is a drawn rectangle
 * and every value is one text run inside it, so the table is rebuilt from
 * geometry instead of from text order (which is what breaks pdftotext-style
 * parsers on wrapped headers and 3 line subject names).
 */
public enum MarksParser {
    private struct Cell {
        let rect: PdfRect
        let lines: [String]
        let text: String
    }

    private struct Column {
        let event: Int
        let weighted: Bool
        let left: Double
        let right: Double
    }

    /// dataTop: bottom edge of the header block, rows start below it
    private struct Layout {
        let anchor: PdfRect
        let events: [String]
        let columns: [Column]
        let dataTop: Double
    }

    private static let eps = 1.0
    private static let codeRx = Rx(#"\(\s*([A-Za-z0-9./\- ]+?)\s*\)\s*$"#)
    private static let generatedRx = Rx(#"^[A-Z][a-z]{2} [A-Z][a-z]{2} \d{1,2} \d{2}:\d{2}:\d{2} \w+ \d{4}$"#)

    public static func parse(_ pdf: Data) throws -> MarksReport {
        let reader = PdfReader(Array(pdf))
        let pages = try reader.pages().map { ContentScanner.scan(try reader.contents($0)) }
        if pages.isEmpty { throw MarksParseError(message: "no pages") }

        var layout: Layout?
        var order: [String] = []
        var subjects: [String: SubjectMarks] = [:]
        var student = MarksStudent()
        var generated = ""

        for page in pages {
            let cells = cells(page)
            student = mergeStudent(student, cells)
            if generated.isEmpty {
                generated = page.runs.map { $0.text.trimmed }.first { generatedRx.matchesWhole($0) != nil } ?? ""
            }
            let found = findLayout(cells)
            guard let active = found ?? layout else { continue }
            layout = active
            let below = found?.dataTop ?? .greatestFiniteMagnitude
            for s in rows(cells, active, below) {
                if let a = subjects[s.code] {
                    // a subject split across pages keeps its first half
                    let extra = s.scores.filter { x in !a.scores.contains { $0.event == x.event } }
                    subjects[s.code] = SubjectMarks(code: a.code, name: a.name, scores: a.scores + extra)
                } else {
                    order.append(s.code)
                    subjects[s.code] = s
                }
            }
        }
        guard let l = layout else { return MarksReport(student: student, events: [], subjects: [], generated: generated) }
        return MarksReport(student: student, events: l.events, subjects: order.map { subjects[$0]! }, generated: generated)
    }

    private static func round2(_ y: Double) -> Int64 { Int64((y * 2 + 0.5).rounded(.down)) }

    private static func cells(_ page: PageContent) -> [Cell] {
        var seen = Set<PdfRect>()
        let rects = page.rects.filter { $0.w > 2 && $0.h > 2 }.filter { seen.insert($0).inserted }
        var order: [PdfRect] = []
        var byRect: [PdfRect: [(Int, TextRun)]] = [:]
        for (i, run) in page.runs.enumerated() {
            if run.text.trimmed.isEmpty { continue }
            let px = run.x + 0.5
            let py = run.y + 0.5
            guard let home = rects.filter({ $0.contains(px, py) }).min(by: { $0.area < $1.area }) else { continue }
            if byRect[home] == nil { order.append(home) }
            byRect[home, default: []].append((i, run))
        }
        return order.map { rect in
            // top to bottom, then left to right, runs on one baseline glued
            let runs = byRect[rect]!.sorted { a, b in
                let ka = round2(a.1.y), kb = round2(b.1.y)
                if ka != kb { return ka > kb }
                if a.1.x != b.1.x { return a.1.x < b.1.x }
                return a.0 < b.0
            }
            var keys: [Int64] = []
            var groups: [Int64: [String]] = [:]
            for (_, r) in runs {
                let k = round2(r.y)
                if groups[k] == nil { keys.append(k) }
                groups[k, default: []].append(r.text.trimmed)
            }
            let lines = keys.map { groups[$0]!.joined(separator: " ").trimmed }.filter { !$0.isEmpty }
            return Cell(rect: rect, lines: lines, text: joinLines(lines))
        }
    }

    private static func joinLines(_ lines: [String]) -> String {
        var out = ""
        for l in lines {
            let t = l.trimmed
            if t.isEmpty { continue }
            if !out.isEmpty && !out.hasSuffix("-") { out += " " }
            out += t
        }
        return out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func findLayout(_ cells: [Cell]) -> Layout? {
        guard let anchor = cells.first(where: { $0.text.caseInsensitiveCompare("Subject Code") == .orderedSame })?.rect else { return nil }
        let headers = cells.enumerated()
            .filter { abs($0.1.rect.y - anchor.y) < eps && abs($0.1.rect.h - anchor.h) < eps && $0.1.rect.x > anchor.x + eps }
            .sorted { $0.1.rect.x != $1.1.rect.x ? $0.1.rect.x < $1.1.rect.x : $0.0 < $1.0 }
            .map(\.1)
        if headers.isEmpty { return nil }
        let subs = cells.filter { abs($0.rect.top - anchor.y) < eps && $0.rect.x >= anchor.right - eps }
        var columns: [Column] = []
        for s in subs {
            let cx = s.rect.x + s.rect.w / 2
            guard let ev = headers.firstIndex(where: { cx >= $0.rect.x - eps && cx <= $0.rect.right + eps }) else { continue }
            let label = s.text.replacingOccurrences(of: " ", with: "").uppercased()
            let weighted: Bool
            if label.hasPrefix("OW") || label.contains("WT") {
                weighted = true
            } else if label.hasPrefix("OM") || label.contains("FM") {
                weighted = false
            } else {
                continue
            }
            columns.append(Column(event: ev, weighted: weighted, left: s.rect.x, right: s.rect.right))
        }
        // no sub header row at all: one value per event, treat it as raw marks
        if columns.isEmpty {
            for (i, h) in headers.enumerated() { columns.append(Column(event: i, weighted: false, left: h.rect.x, right: h.rect.right)) }
        }
        let dataTop = subs.map(\.rect.y).min() ?? anchor.y
        return Layout(anchor: anchor, events: headers.map(\.text), columns: columns, dataTop: dataTop)
    }

    private static func rows(_ cells: [Cell], _ layout: Layout, _ below: Double) -> [SubjectMarks] {
        let a = layout.anchor
        let subjectCells = cells.enumerated()
            .filter { abs($0.1.rect.x - a.x) < eps && abs($0.1.rect.w - a.w) < eps && $0.1.rect.top <= below + eps }
            .sorted { $0.1.rect.y != $1.1.rect.y ? $0.1.rect.y > $1.1.rect.y : $0.0 < $1.0 }
            .map(\.1)

        return subjectCells.compactMap { sc in
            guard let m = codeRx.first(in: sc.text) else { return nil }
            let code = m.groups[1].replacingOccurrences(of: " ", with: "")
            let before = String(sc.text[..<m.range.lowerBound]).trimmed
            let name = before.isEmpty ? code : before
            let rowCells = cells.filter { abs($0.rect.y - sc.rect.y) < eps && $0.rect.x >= sc.rect.right - eps }
            var marks: [Int: Score?] = [:]
            var weighted: [Int: Score?] = [:]
            for c in rowCells {
                let cx = c.rect.x + c.rect.w / 2
                guard let col = layout.columns.first(where: { cx >= $0.left - eps && cx <= $0.right + eps }) else { continue }
                let score = Score.parse(c.text)
                if col.weighted { weighted[col.event] = .some(score) } else { marks[col.event] = .some(score) }
            }
            let scores: [EventScore] = layout.events.indices.compactMap { i in
                let om = marks[i] ?? nil
                let ow = weighted[i] ?? nil
                return om == nil && ow == nil ? nil : EventScore(event: layout.events[i], marks: om, weighted: ow)
            }
            return SubjectMarks(code: code, name: name, scores: scores)
        }
    }

    private static func mergeStudent(_ s: MarksStudent, _ cells: [Cell]) -> MarksStudent {
        func field(_ key: String) -> String {
            for c in cells {
                let t = c.text
                let prefix = "\(key):"
                if t.count >= prefix.count, t.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame {
                    return String(t.dropFirst(prefix.count)).trimmed
                }
            }
            return ""
        }
        return MarksStudent(
            name: s.name.isEmpty ? field("Name") : s.name,
            enrollmentNo: s.enrollmentNo.isEmpty ? field("Enrollment No") : s.enrollmentNo,
            program: s.program.isEmpty ? field("Program") : s.program,
            branch: s.branch.isEmpty ? field("Branch") : s.branch,
            semester: s.semester.isEmpty ? field("Semester") : s.semester,
            registrationCode: s.registrationCode.isEmpty ? field("Registration Code") : s.registrationCode
        )
    }
}
