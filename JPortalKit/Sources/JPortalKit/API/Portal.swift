import Foundation

/**
 * typed calls for one signed in student. payload keys (typos included) and the
 * plain vs encrypted choice come straight from the portal bundle, don't "fix" them.
 */
public struct Portal: Sendable {
    public let session: Session
    let transport: Transport

    public init(session: Session, transport: Transport) {
        self.session = session
        self.transport = transport
    }

    private var iid: String { session.instituteId }

    private func call(_ path: String, encrypt: Bool, _ pairs: KeyValuePairs<String, JSON>) async throws -> JSON {
        try await transport.post(path, token: session.token, payload: Payload(pairs), encrypt: encrypt)
    }

    /// "NO ... FOUND" answers become [empty]
    private func listOrEmpty<T>(_ empty: T, _ block: () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch let e as PortalError where e.isNoData {
            return empty
        }
    }

    // attendance

    public func attendanceMeta() async throws -> AttendanceMeta {
        AttendanceMeta(json: try await call("/StudentClassAttendance/getstudentInforegistrationforattendence", encrypt: false, ["instituteid": .string(iid)]))
    }

    public func attendance(_ semester: Semester, semesterNumber: String) async throws -> AttendanceDetail {
        try await listOrEmpty(AttendanceDetail()) {
            AttendanceDetail(json: try await call("/StudentClassAttendance/getstudentattendancedetail", encrypt: true, [
                "instituteid": .string(iid),
                "registrationcode": .string(semester.code),
                "registrationid": .string(semester.id),
                "stynumber": .string(semesterNumber),
            ]))
        }
    }

    /// class by class list, pass a subset of components to split L/T/P
    public func dailyAttendance(_ semester: Semester, subject: SubjectAttendance, components: [String]? = nil) async throws -> DailyAttendance {
        let comps = components ?? subject.components
        return try await listOrEmpty(DailyAttendance()) {
            DailyAttendance(json: try await call("/StudentClassAttendance/getstudentsubjectpersentage", encrypt: true, [
                "instituteid": .string(iid),
                "subjectid": .string(subject.subjectId),
                "registrationid": .string(semester.id),
                "cmpidkey": .array(comps.map { ["subjectcomponentid": .string($0)] }),
                "subjectcode": .string(subject.code),
                "registrationcode": .string(semester.code),
            ]))
        }
    }

    // subjects

    public func subjectSemesters() async throws -> [Semester] {
        Semester.list(try await call("/reqsubfaculty/getregistrationList", encrypt: true, ["instituteid": .string(iid)])["registrations"])
    }

    public func registeredSubjects(_ semester: Semester) async throws -> RegisteredSubjects {
        try await listOrEmpty(RegisteredSubjects()) {
            RegisteredSubjects(json: try await call("/reqsubfaculty/getfaculties", encrypt: true, [
                "studentid": .string(session.memberId),
                "instituteid": .string(iid),
                "registrationid": .string(semester.id),
            ]))
        }
    }

    public func credits() async throws -> Credits {
        Credits(json: try await call("/feedbackformcontroller/getCreadits", encrypt: false, ["enrollmentNo": .string(session.enrollmentNo)]))
    }

    // exams

    public func examSemesters() async throws -> [Semester] {
        try await listOrEmpty([]) {
            Semester.list(try await call("/studentcommonsontroller/getsemestercode-withstudentexamevents", encrypt: true, [
                "clientid": .string(session.clientId),
                "instituteid": .string(iid),
            ])["semesterCodeinfo"]["semestercode"])
        }
    }

    public func examEvents(_ semester: Semester) async throws -> [ExamEvent] {
        try await listOrEmpty([]) {
            try await call("/studentcommonsontroller/getstudentexamevents", encrypt: true, [
                "instituteid": .string(iid),
                "registationid": .string(semester.id),
            ])["eventcode"]["examevent"].array.map(ExamEvent.init(json:))
        }
    }

    public func examSchedule(_ event: ExamEvent) async throws -> [ExamSlot] {
        try await listOrEmpty([]) {
            try await call("/studentsttattview/getstudent-examschedule", encrypt: true, [
                "instituteid": .string(iid),
                "exameventid": .string(event.id),
                "registrationid": .string(event.semesterId),
            ])["subjectinfo"].array.map(ExamSlot.init(json:))
        }
    }

    // marks

    public func marksSemesters() async throws -> [Semester] {
        try await listOrEmpty([]) {
            Semester.list(try await call("/studentcommonsontroller/getsemestercode-exammarks", encrypt: true, ["instituteid": .string(iid)])["semestercode"])
        }
    }

    public func marksPdf(_ semester: Semester) async throws -> Data {
        try await transport.bytes("/studentsexamview/printstudent-exammarks/\(iid)/\(semester.id)/\(semester.code)", token: session.token)
    }

    public func marks(_ semester: Semester) async throws -> MarksReport {
        try MarksParser.parse(try await marksPdf(semester))
    }

    // grades

    public func gradeCardSemesters() async throws -> [Semester] {
        try await listOrEmpty([]) {
            Semester.list(try await call("/studentgradecard/getregistrationList", encrypt: true, ["instituteid": .string(iid)])["registrations"])
        }
    }

    public func program() async throws -> StudentProgram {
        StudentProgram(json: try await call("/studentgradecard/getstudentinfo", encrypt: true, ["instituteid": .string(iid)])["studentinfo"])
    }

    public func gradeCard(_ semester: Semester, program: StudentProgram) async throws -> GradeCard {
        try await listOrEmpty(GradeCard()) {
            GradeCard(json: try await call("/studentgradecard/showstudentgradecard", encrypt: true, [
                "instituteid": .string(iid),
                "registrationid": .string(semester.id),
                "branchid": .string(program.branchId),
                "programid": .string(program.programId),
            ]))
        }
    }

    /// sgpa/cgpa for every finished semester
    public func semesterResults(currentSemester: String) async throws -> [SemesterResult] {
        try await listOrEmpty([]) {
            try await call("/studentsgpacgpa/getallsemesterdata", encrypt: true, [
                "instituteid": .string(iid),
                "studentid": .string(session.memberId),
                "stynumber": .string(currentSemester),
            ])["semesterList"].array.map(SemesterResult.init(json:))
        }
    }

    // me

    public func personalInfo() async throws -> PersonalInfo {
        PersonalInfo(json: try await call("/studentpersinfo/getstudent-personalinformation", encrypt: false, ["instituteid": .string(iid)]))
    }

    public func bankInfo() async throws -> BankInfo {
        BankInfo(json: try await call("/studentbankdetails/getstudentbankinfo", encrypt: true, ["instituteid": .string(iid)])["bankinfo"])
    }

    public func hostel() async throws -> HostelAllotment {
        try await listOrEmpty(HostelAllotment(nil)) {
            let h = try await call("/myhostelallocationdetail/gethostelallocationdetail", encrypt: false, ["instituteid": .string(iid)])["presenthosteldetail"]
            return HostelAllotment(h.isNull ? nil : HostelInfo(json: h))
        }
    }

    public func fees() async throws -> FeeSummary {
        try await listOrEmpty(FeeSummary()) {
            FeeSummary(json: try await call("/studentfeeledger/loadfeesummary", encrypt: false, ["instituteid": .string(iid)]))
        }
    }

    public func feedbackEvents() async throws -> [FeedbackEvent] {
        try await listOrEmpty([]) {
            try await call("/feedbackformcontroller/getFeedbackEvent", encrypt: false, [
                "instituteid": .string(iid),
                "studentid": .string(session.memberId),
            ])["eventList"].array.map(FeedbackEvent.init(json:))
        }
    }

    // registration, read only

    public func choiceSemesters() async throws -> [Semester] {
        try await listOrEmpty([]) {
            Semester.list(try await call("/studentchoiceprint/getsemestercodelist", encrypt: true, [:])["registrationcodelist"])
        }
    }

    public func subjectChoices(_ semester: Semester) async throws -> [SubjectChoice] {
        try await listOrEmpty([]) {
            try await call("/studentchoiceprint/getsubjectpreference", encrypt: true, [
                "instituteid": .string(iid),
                "clientid": .string(session.clientId),
                "registrationid": .string(semester.id),
            ])["subjectpreferencegrid"].array.map(SubjectChoice.init(json:))
        }
    }

    public func moocSemesters() async throws -> [Semester] {
        try await listOrEmpty([]) {
            Semester.list(try await call("/moocsubjectstatus/getsemestercodelist", encrypt: false, ["instituteid": .string(iid)]))
        }
    }

    public func moocStatus(_ semester: Semester) async throws -> MoocStatus {
        try await listOrEmpty(MoocStatus()) {
            MoocStatus(json: try await call("/moocsubjectstatus/getsubjectstatus", encrypt: false, [
                "instituteid": .string(iid),
                "registrationid": .string(semester.id),
            ]))
        }
    }
}
