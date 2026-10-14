import Foundation

/// a registration is the portal's word for a semester, e.g. 2026ODDSEM
public struct Semester: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var code: String
    public var description: String = ""
    /// epoch millis, only the marks list carries these
    public var from: Int64? = nil
    public var to: Int64? = nil

    public init(id: String, code: String, description: String = "", from: Int64? = nil, to: Int64? = nil) {
        self.id = id
        self.code = code
        self.description = description
        self.from = from
        self.to = to
    }

    public init(json j: JSON) {
        id = j.str("registrationid")
        code = j.str("registrationcode")
        description = j.str("registrationdesc")
        from = j.optInt64("registrationdatefrom")
        to = j.optInt64("registrationdateto")
    }

    static func list(_ j: JSON) -> [Semester] { j.array.map(Semester.init(json:)) }
}

public struct AttendanceHeader: Codable, Sendable, Hashable {
    public var branch: String = ""
    public var program: String = ""
    public var name: String = ""
    public var semesterNumber: String = ""

    public init(branch: String = "", program: String = "", name: String = "", semesterNumber: String = "") {
        self.branch = branch
        self.program = program
        self.name = name
        self.semesterNumber = semesterNumber
    }

    init(json j: JSON) {
        branch = j.str("branchdesc")
        program = j.str("programdesc")
        name = j.str("name")
        semesterNumber = j.str("stynumber")
    }
}

public struct AttendanceMeta: Codable, Sendable, Hashable {
    public var headers: [AttendanceHeader] = []
    public var semesters: [Semester] = []

    public init(headers: [AttendanceHeader] = [], semesters: [Semester] = []) {
        self.headers = headers
        self.semesters = semesters
    }

    init(json j: JSON) {
        headers = j["headerlist"].array.map(AttendanceHeader.init(json:))
        semesters = Semester.list(j["semlist"])
    }

    public var header: AttendanceHeader? { headers.first }
}

/**
 * one row of the attendance table. the portal gives only percentages here,
 * counts come from the daily list. component ids are what the daily call wants.
 */
public struct SubjectAttendance: Codable, Sendable, Hashable, Identifiable {
    public var subjectId: String
    public var code: String = ""
    /// "NAME(CODE)"
    public var title: String = ""
    public var combinedPercent: Double? = nil
    public var lecturePercent: Double? = nil
    public var tutorialPercent: Double? = nil
    public var practicalPercent: Double? = nil
    public var lectureComponent: String? = nil
    public var tutorialComponent: String? = nil
    public var practicalComponent: String? = nil

    public var id: String { subjectId }

    public init(
        subjectId: String, code: String = "", title: String = "", combinedPercent: Double? = nil, lecturePercent: Double? = nil,
        tutorialPercent: Double? = nil, practicalPercent: Double? = nil, lectureComponent: String? = nil,
        tutorialComponent: String? = nil, practicalComponent: String? = nil
    ) {
        self.subjectId = subjectId
        self.code = code
        self.title = title
        self.combinedPercent = combinedPercent
        self.lecturePercent = lecturePercent
        self.tutorialPercent = tutorialPercent
        self.practicalPercent = practicalPercent
        self.lectureComponent = lectureComponent
        self.tutorialComponent = tutorialComponent
        self.practicalComponent = practicalComponent
    }

    init(json j: JSON) {
        subjectId = j.str("subjectid")
        code = j.str("individualsubjectcode")
        title = j.str("subjectcode")
        combinedPercent = j.optDbl("LTpercantage")
        lecturePercent = j.optDbl("Lpercentage")
        tutorialPercent = j.optDbl("Tpercentage")
        practicalPercent = j.optDbl("Ppercentage")
        lectureComponent = j.optStr("Lsubjectcomponentid")
        tutorialComponent = j.optStr("Tsubjectcomponentid")
        practicalComponent = j.optStr("Psubjectcomponentid")
    }

    public var name: String {
        let suffix = "(\(code))"
        let n = title.hasSuffix(suffix) ? String(title.dropLast(suffix.count)).trimmed : title.trimmed
        return n.isEmpty ? title : n
    }

    public var components: [String] {
        [lectureComponent, tutorialComponent, practicalComponent].compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// the portal's headline number: LT if it has lectures, else P
    public var percent: Double? {
        lectureComponent != nil || tutorialComponent != nil ? combinedPercent ?? lecturePercent : practicalPercent
    }
}

public struct AttendanceDetail: Codable, Sendable, Hashable {
    public var subjects: [SubjectAttendance] = []
    public var currentSem: String = ""

    public init(subjects: [SubjectAttendance] = [], currentSem: String = "") {
        self.subjects = subjects
        self.currentSem = currentSem
    }

    init(json j: JSON) {
        subjects = j["studentattendancelist"].array.map(SubjectAttendance.init(json:))
        currentSem = j.str("currentSem")
    }
}

public struct ClassRecord: Codable, Sendable, Hashable {
    /// "18/09/2026 (10:00:AM - 10:50 AM)", yes with that colon
    public var datetime: String = ""
    /// Present / Absent
    public var present: String = ""
    public var takenBy: String = ""
    public var classType: String = ""
    public var status: String = ""

    public init(datetime: String = "", present: String = "", takenBy: String = "", classType: String = "", status: String = "") {
        self.datetime = datetime
        self.present = present
        self.takenBy = takenBy
        self.classType = classType
        self.status = status
    }

    init(json j: JSON) {
        datetime = j.str("datetime")
        present = j.str("present")
        takenBy = j.str("attendanceby")
        classType = j.str("classtype")
        status = j.str("attendancestatus")
    }

    public var isPresent: Bool { present.caseInsensitiveCompare("Present") == .orderedSame }

    /// the portal leaves these out of the class count, so only a present one moves the percentage
    public var isExtra: Bool { classType.caseInsensitiveCompare("Extra") == .orderedSame }

    public var date: Day? { ClassRecord.parse(datetime)?.0 }
    public var start: ClockTime? { ClassRecord.parse(datetime)?.1 }
    public var end: ClockTime? { ClassRecord.parse(datetime)?.2 }

    private static let shape = Rx(#"(\d{2}/\d{2}/\d{4})\s*\((\d{1,2}):(\d{2}):?\s*([AP]M)\s*-\s*(\d{1,2}):(\d{2}):?\s*([AP]M)\)"#)

    static func parse(_ s: String) -> (Day, ClockTime?, ClockTime?)? {
        guard let m = shape.first(in: s) else {
            guard let d = Day.parse(ddMMyyyy: String(s.prefix(10))) else { return nil }
            return (d, nil, nil)
        }
        let g = m.groups
        func t(_ h: String, _ min: String, _ ap: String) -> ClockTime? {
            guard let hh = Int(h), let mm = Int(min), (1...12).contains(hh), (0...59).contains(mm) else { return nil }
            let hour = ap == "AM" ? (hh == 12 ? 0 : hh) : (hh == 12 ? 12 : hh + 12)
            return ClockTime(hour: hour, minute: mm)
        }
        guard let d = Day.parse(ddMMyyyy: g[1]) else { return nil }
        return (d, t(g[2], g[3], g[4]), t(g[5], g[6], g[7]))
    }
}

public struct DailyAttendance: Codable, Sendable, Hashable {
    public var classes: [ClassRecord] = []

    public init(classes: [ClassRecord] = []) {
        self.classes = classes
    }

    init(json j: JSON) {
        classes = j["studentAttdsummarylist"].array.map(ClassRecord.init(json:))
    }

    /// every present class, extras included, same as the portal's percentage
    public var attended: Int { classes.count { $0.isPresent } }

    /// regular classes only, an extra never adds to the bottom of the fraction
    public var total: Int { classes.count { !$0.isExtra } }
}
