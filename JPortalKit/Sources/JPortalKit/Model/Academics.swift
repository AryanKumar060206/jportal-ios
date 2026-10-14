import Foundation

// subjects

/// one (subject, component, teacher) row, a subject with L+T+P shows up three times
public struct SubjectFaculty: Codable, Sendable, Hashable {
    public var subjectId: String = ""
    public var code: String = ""
    public var name: String = ""
    public var component: String = ""
    public var faculty: String = ""
    public var facultyCode: String = ""
    public var credits: Double = 0
    public var audit: String = "N"
    public var minor: String = "N"
    public var remarks: String = ""
    public var type: String = ""

    public init(
        subjectId: String = "", code: String = "", name: String = "", component: String = "", faculty: String = "",
        facultyCode: String = "", credits: Double = 0, audit: String = "N", minor: String = "N", remarks: String = "", type: String = ""
    ) {
        self.subjectId = subjectId
        self.code = code
        self.name = name
        self.component = component
        self.faculty = faculty
        self.facultyCode = facultyCode
        self.credits = credits
        self.audit = audit
        self.minor = minor
        self.remarks = remarks
        self.type = type
    }

    init(json j: JSON) {
        subjectId = j.str("subjectid")
        code = j.str("subjectcode")
        name = j.str("subjectdesc")
        component = j.str("subjectcomponentcode")
        faculty = j.str("employeename")
        facultyCode = j.str("employeecode")
        credits = j.dbl("credits")
        audit = j.str("audtsubject", "N")
        minor = j.str("minorsubject", "N")
        remarks = j.str("remarks")
        type = j.str("stytype")
    }

    public var isAudit: Bool { audit == "Y" }
    /// portal pads names with runs of spaces
    public var facultyName: String { faculty.squashed }
}

public struct RegisteredSubjects: Codable, Sendable, Hashable {
    public var rows: [SubjectFaculty] = []
    public var totalCredits: Double = 0

    public init(rows: [SubjectFaculty] = [], totalCredits: Double = 0) {
        self.rows = rows
        self.totalCredits = totalCredits
    }

    init(json j: JSON) {
        rows = j["registrations"].array.map(SubjectFaculty.init(json:))
        totalCredits = j.dbl("totalcreditpoints")
    }
}

public struct Credits: Codable, Sendable, Hashable {
    public var registeredCredits: Int = 0
    public var required: Int = 0
    public var earned: Int = 0
    public var semester: String = ""

    public init(registeredCredits: Int = 0, required: Int = 0, earned: Int = 0, semester: String = "") {
        self.registeredCredits = registeredCredits
        self.required = required
        self.earned = earned
        self.semester = semester
    }

    init(json j: JSON) {
        registeredCredits = j.int("registeredCredits")
        required = j.int("totalreqcredit")
        earned = j.int("earnedcredit")
        semester = j.str("semester")
    }
}

// exams

public struct ExamEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var code: String = ""
    public var description: String = ""
    /// epoch millis
    public var from: Int64? = nil
    public var semesterId: String = ""

    public init(id: String, code: String = "", description: String = "", from: Int64? = nil, semesterId: String = "") {
        self.id = id
        self.code = code
        self.description = description
        self.from = from
        self.semesterId = semesterId
    }

    init(json j: JSON) {
        id = j.str("exameventid")
        code = j.str("exameventcode")
        description = j.str("exameventdesc")
        from = j.optInt64("eventfrom")
        semesterId = j.str("registrationid")
    }
}

/// one paper. date is dd/MM/yyyy, from is "03:30 pm", until is the whole "03:30 pm to 04:30 pm" window
public struct ExamSlot: Codable, Sendable, Hashable {
    public var date: String = ""
    public var from: String = ""
    public var until: String = ""
    public var subject: String = ""
    public var code: String = ""
    public var room: String = ""
    public var seat: String = ""

    public init(date: String = "", from: String = "", until: String = "", subject: String = "", code: String = "", room: String = "", seat: String = "") {
        self.date = date
        self.from = from
        self.until = until
        self.subject = subject
        self.code = code
        self.room = room
        self.seat = seat
    }

    init(json j: JSON) {
        date = j.str("datetime")
        from = j.str("datetimefrom")
        until = j.str("datetimeupto")
        subject = j.str("subjectdesc")
        code = j.str("subjectcode")
        room = j.str("roomcode")
        seat = j.str("seatno")
    }

    public var subjectName: String {
        String(subject.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").trimmed
    }

    public var day: Day? { Day.parse(ddMMyyyy: date) }

    public var start: ClockTime? { window.0 }
    public var end: ClockTime? { window.1 }

    /// room and seat land about a day before the paper, blank until then
    public var seated: Bool { !room.trimmed.isEmpty || !seat.trimmed.isEmpty }

    private var window: (ClockTime?, ClockTime?) {
        let start = parseClocks(from).first ?? parseClocks(until).first
        let last = parseClocks(until).last
        let end = last.flatMap { e in start == nil || e > start! ? e : nil }
        return (start, end)
    }
}

// 03:30 pm, 3:30PM, 09:00:AM, 14:00, 14:00:00
private let clockRx = Rx(#"(\d{1,2})[:.](\d{2})(?::\d{2})?(?:\s*:?\s*([ap])\.?m\b\.?)?"#, caseInsensitive: true)

/// every clock time in a portal string, in order
public func parseClocks(_ s: String) -> [ClockTime] {
    clockRx.all(in: s).compactMap { m in
        guard let h = Int(m.groups[1]), let min = Int(m.groups[2]) else { return nil }
        let ap = m.groups[3].lowercased()
        let hour: Int
        switch ap {
        case "": hour = h
        case "a": hour = h == 12 ? 0 : h
        default: hour = h == 12 ? 12 : h + 12
        }
        let twelve = ap.isEmpty || (1...12).contains(h)
        return twelve && (0...23).contains(hour) && (0...59).contains(min) ? ClockTime(hour: hour, minute: min) : nil
    }
}

// grades

public struct SemesterResult: Codable, Sendable, Hashable {
    public var semester: Int
    public var sgpa: Double = 0
    public var cgpa: Double = 0
    public var courseCredits: Double = 0
    public var gradePoints: Double = 0
    // the portal's names lie: singular "credit" is this semester, plural "credits" is the running total
    public var earnedCredits: Double = 0
    public var cumulativeCredits: Double = 0
    /// running total too, despite the name
    public var cumulativeRegistered: Double = 0
    public var cumulativePoints: Double = 0

    public init(
        semester: Int, sgpa: Double = 0, cgpa: Double = 0, courseCredits: Double = 0, gradePoints: Double = 0,
        earnedCredits: Double = 0, cumulativeCredits: Double = 0, cumulativeRegistered: Double = 0, cumulativePoints: Double = 0
    ) {
        self.semester = semester
        self.sgpa = sgpa
        self.cgpa = cgpa
        self.courseCredits = courseCredits
        self.gradePoints = gradePoints
        self.earnedCredits = earnedCredits
        self.cumulativeCredits = cumulativeCredits
        self.cumulativeRegistered = cumulativeRegistered
        self.cumulativePoints = cumulativePoints
    }

    init(json j: JSON) {
        semester = j.int("stynumber")
        sgpa = j.dbl("sgpa")
        cgpa = j.dbl("cgpa")
        courseCredits = j.dbl("totalcoursecredit")
        gradePoints = j.dbl("earnedgradepoints")
        earnedCredits = j.dbl("totalearnedcredit")
        cumulativeCredits = j.dbl("totalearnedcredits")
        cumulativeRegistered = j.dbl("totalregisteredcredit")
        cumulativePoints = j.dbl("totalpointsecuredcgpa")
    }
}

public struct StudentProgram: Codable, Sendable, Hashable {
    public var branchId: String = ""
    public var programId: String = ""
    public var branchCode: String = ""
    public var programCode: String = ""
    public var branch: String = ""
    public var program: String = ""
    public var maxSemesters: Int = 0

    public init(
        branchId: String = "", programId: String = "", branchCode: String = "", programCode: String = "",
        branch: String = "", program: String = "", maxSemesters: Int = 0
    ) {
        self.branchId = branchId
        self.programId = programId
        self.branchCode = branchCode
        self.programCode = programCode
        self.branch = branch
        self.program = program
        self.maxSemesters = maxSemesters
    }

    init(json j: JSON) {
        branchId = j.str("branchid")
        programId = j.str("programid")
        branchCode = j.str("branchcode")
        programCode = j.str("programcode")
        branch = j.str("branchdesc")
        program = j.str("programdesc")
        maxSemesters = j.int("stymax")
    }
}

public struct GradeEntry: Codable, Sendable, Hashable {
    public var subjectId: String = ""
    public var code: String = ""
    public var name: String = ""
    public var grade: String = ""
    public var gradePoint: Double = 0
    public var credits: Double = 0
    public var earned: Double = 0
    public var points: Double = 0
    public var semester: Int = 0
    public var minor: String = "N"

    public init(
        subjectId: String = "", code: String = "", name: String = "", grade: String = "", gradePoint: Double = 0,
        credits: Double = 0, earned: Double = 0, points: Double = 0, semester: Int = 0, minor: String = "N"
    ) {
        self.subjectId = subjectId
        self.code = code
        self.name = name
        self.grade = grade
        self.gradePoint = gradePoint
        self.credits = credits
        self.earned = earned
        self.points = points
        self.semester = semester
        self.minor = minor
    }

    init(json j: JSON) {
        subjectId = j.str("subjectid")
        code = j.str("subjectcode")
        name = j.str("subjectdesc")
        grade = j.str("grade")
        gradePoint = j.dbl("gradepoint")
        credits = j.dbl("coursecreditpoint")
        earned = j.dbl("earnedcredit")
        points = j.dbl("pointsecured")
        semester = j.int("stynumber")
        minor = j.str("minorsubject", "N")
    }
}

public struct GradeCard: Codable, Sendable, Hashable {
    public var entries: [GradeEntry] = []

    public init(entries: [GradeEntry] = []) {
        self.entries = entries
    }

    init(json j: JSON) {
        entries = j["gradecard"].array.map(GradeEntry.init(json:))
    }
}
