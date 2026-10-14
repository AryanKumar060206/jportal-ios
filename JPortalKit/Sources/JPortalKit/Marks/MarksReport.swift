import Foundation

public struct MarksReport: Codable, Sendable, Hashable {
    public var student: MarksStudent
    /// exam events in the order the pdf lists them, that order is not chronological
    public var events: [String]
    public var subjects: [SubjectMarks]
    /// "Mon Apr 20 01:46:33 IST 2026" as printed
    public var generated: String = ""

    public init(student: MarksStudent, events: [String], subjects: [SubjectMarks], generated: String = "") {
        self.student = student
        self.events = events
        self.subjects = subjects
        self.generated = generated
    }

    public static let empty = MarksReport(student: MarksStudent(), events: [], subjects: [])
}

public struct MarksStudent: Codable, Sendable, Hashable {
    public var name = ""
    public var enrollmentNo = ""
    public var program = ""
    public var branch = ""
    public var semester = ""
    public var registrationCode = ""

    public init(name: String = "", enrollmentNo: String = "", program: String = "", branch: String = "", semester: String = "", registrationCode: String = "") {
        self.name = name
        self.enrollmentNo = enrollmentNo
        self.program = program
        self.branch = branch
        self.semester = semester
        self.registrationCode = registrationCode
    }
}

public struct SubjectMarks: Codable, Sendable, Hashable, Identifiable {
    public var code: String
    public var name: String
    public var scores: [EventScore]

    public var id: String { code }

    public init(code: String, name: String, scores: [EventScore]) {
        self.code = code
        self.name = name
        self.scores = scores
    }
}

public struct EventScore: Codable, Sendable, Hashable {
    public var event: String
    /// OM/FM
    public var marks: Score? = nil
    /// OW/WT, what actually counts toward the total
    public var weighted: Score? = nil

    public init(event: String, marks: Score? = nil, weighted: Score? = nil) {
        self.event = event
        self.marks = marks
        self.weighted = weighted
    }
}

public enum Score: Codable, Sendable, Hashable {
    case value(obtained: Double, max: Double)
    case absent
    /// printed as "-": this event doesn't apply to the subject
    case notApplicable
    case other(String)

    private static let fraction = Rx(#"^(-?\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$"#)

    public static func parse(_ text: String) -> Score? {
        let t = text.trimmed
        if t.isEmpty { return nil }
        if t == "-" { return .notApplicable }
        let up = t.uppercased()
        if up == "A" || up == "AB" || up == "ABS" { return .absent }
        if let m = fraction.matchesWhole(t), let o = Double(m.groups[1]), let x = Double(m.groups[2]) {
            return .value(obtained: o, max: x)
        }
        return .other(t)
    }

    public var value: (obtained: Double, max: Double)? {
        if case .value(let o, let m) = self { return (o, m) }
        return nil
    }
}

public struct MarksParseError: Error, Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}
