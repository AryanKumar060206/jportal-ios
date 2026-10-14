import Foundation
import JPortalKit

/**
 * a made up student, behind the sign-in screen's demo button. written
 * straight into the cache under the keys the repository reads, with dates
 * counted from today so the demo always looks current.
 */
enum Demo {
    nonisolated static let session = Session(token: "demo", username: "demo", instituteId: "demo", enrollmentNo: "99103042", name: "YASH MALIK")

    nonisolated static func owns(_ s: Session) -> Bool { s.token == session.token }

    private struct Subj {
        let id: String
        let code: String
        let name: String
        let parts: String
        /// chance of being present, per mille
        let odds: Int
        /// monday is 0
        let days: [Int]
        let teachers: [Character: String]
        let credits: Double
        var audit = false
    }

    private static let current: [Subj] = [
        Subj(id: "S1", code: "15B11CI712", name: "COMPILER DESIGN", parts: "LT", odds: 930, days: [0, 2, 4], teachers: ["L": "DR. NEHA KAPOOR", "T": "RAHUL VERMA"], credits: 4),
        Subj(id: "S2", code: "15B11CI713", name: "MACHINE LEARNING AND DATA MINING", parts: "LT", odds: 840, days: [0, 1, 3], teachers: ["L": "DR. ANKIT SAXENA", "T": "PRIYA NAIR"], credits: 4),
        Subj(id: "S3", code: "15B1NCI731", name: "CLOUD COMPUTING", parts: "LT", odds: 640, days: [1, 3, 4], teachers: ["L": "DR. KAVITA RAO", "T": "KAVITA RAO"], credits: 4),
        Subj(id: "S4", code: "15B17CI771", name: "MACHINE LEARNING LAB", parts: "P", odds: 1000, days: [2], teachers: ["P": "SUMIT BHATIA"], credits: 1),
        Subj(id: "S5", code: "15B17CI772", name: "CLOUD COMPUTING LAB", parts: "P", odds: 760, days: [4], teachers: ["P": "PRIYA NAIR"], credits: 1),
        Subj(id: "S6", code: "16B1NHS732", name: "MARKETING MANAGEMENT", parts: "L", odds: 880, days: [0, 3], teachers: ["L": "DR. ISHA MALHOTRA"], credits: 3),
        Subj(id: "S7", code: "15B11HS711", name: "ENVIRONMENTAL STUDIES", parts: "L", odds: 0, days: [], teachers: ["L": "DR. VIVEK SINGH"], credits: 0, audit: true),
    ]

    // newest first, like the portal
    private static let past: [[(String, String)]] = [
        [("15B11CI611", "SOFTWARE ENGINEERING"), ("15B11CI612", "DISTRIBUTED SYSTEMS"), ("15B11CI613", "INFORMATION SECURITY"),
         ("15B17CI671", "SOFTWARE ENGINEERING LAB"), ("15B1NCI632", "NATURAL LANGUAGE PROCESSING"), ("16B1NHS631", "PRINCIPLES OF MANAGEMENT")],
        [("15B11CI412", "OPERATING SYSTEMS AND SYSTEMS PROGRAMMING"), ("15B11CI515", "COMPUTER NETWORKS AND INTERNET OF THINGS"), ("15B11CI514", "ARTIFICIAL INTELLIGENCE"),
         ("15B17CI574", "INFORMATION SECURITY LAB"), ("15B17CI575", "COMPUTER NETWORKS LAB"), ("16B1NHS434", "ECONOMICS OF DIGITAL PLATFORMS")],
        [("15B11CI411", "ALGORITHMS AND PROBLEM SOLVING"), ("15B11CI413", "THEORY OF COMPUTATION"), ("15B11MA411", "DISCRETE MATHEMATICS"),
         ("15B17CI471", "ALGORITHMS LAB"), ("15B11CI414", "COMPUTER ORGANISATION AND ARCHITECTURE"), ("15B11HS311", "LIFE SKILLS")],
        [("15B11CI311", "DATA STRUCTURES"), ("15B11CI312", "DATABASE SYSTEMS AND WEB"), ("15B11MA301", "PROBABILITY AND RANDOM PROCESSES"),
         ("15B17CI371", "DATA STRUCTURES LAB"), ("15B11EC311", "DIGITAL SYSTEMS"), ("15B11HS211", "ECONOMICS")],
        [("15B11PH211", "PHYSICS II"), ("15B11MA211", "MATHEMATICS II"), ("15B11EC211", "ELECTRICAL SCIENCE II"),
         ("15B17PH271", "PHYSICS LAB II"), ("15B11CI211", "SOFTWARE DEVELOPMENT FUNDAMENTALS II"), ("15B11GE211", "ENGINEERING DRAWING")],
        [("15B11PH111", "PHYSICS I"), ("15B11MA111", "MATHEMATICS I"), ("15B11EC111", "ELECTRICAL SCIENCE I"),
         ("15B17PH171", "PHYSICS LAB I"), ("15B11CI111", "SOFTWARE DEVELOPMENT FUNDAMENTALS I"), ("15B11HS111", "ENGLISH")],
    ]

    private static let grades: [[String]] = [
        ["A+", "A", "A", "A+", "B+", "A"],
        ["A", "B+", "A", "A+", "A", "A+"],
        ["A", "A+", "B+", "A", "B", "A+"],
        ["A+", "B+", "A", "A+", "B", "A"],
        ["B+", "A", "B", "A", "A+", "B+"],
        ["A", "B+", "C+", "A+", "A", "B"],
    ]
    private static let points: [String: Double] = ["A+": 10, "A": 9, "B+": 8, "B": 7, "C+": 6]

    // current first, the portal's order
    private static let sems = [
        Semester(id: "D26O", code: "2026ODDSEM"), Semester(id: "D26E", code: "2026EVESEM"), Semester(id: "D25O", code: "2025ODDSEM"),
        Semester(id: "D25E", code: "2025EVESEM"), Semester(id: "D24O", code: "2024ODDSEM"), Semester(id: "D24E", code: "2024EVESEM"),
        Semester(id: "D23O", code: "2023ODDSEM"),
    ]

    private static let people = ["DR. MEERA IYER", "ARJUN KHANNA", "DR. SNEHA GUPTA", "VIKRAM SETHI", "DR. POOJA DAS", "NIKHIL JAIN"]
    private static let hss: Set<String> = ["ECONOMICS", "ENGLISH", "LIFE SKILLS", "ECONOMICS OF DIGITAL PLATFORMS", "PRINCIPLES OF MANAGEMENT"]

    private static func credits(_ name: String) -> Double { name.contains("LAB") ? 1 : hss.contains(name) ? 3 : 4 }
    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    private static func title(_ s: Subj) -> String { "\(s.name)(\(s.code))" }

    static func seed(_ cache: Cache) async {
        let at = Date().addingTimeInterval(-5 * 60)
        func put<T: Codable & Sendable>(_ key: String, _ v: T) async { await cache.put(key, v, at: at) }
        let today = Day.today()
        let now = sems[0]

        await put("att_meta", AttendanceMeta(headers: [AttendanceHeader(branch: "Computer Science and Engineering", program: "B.Tech", name: session.name, semesterNumber: "7")], semesters: sems))
        await put("att:\(now.id)", AttendanceDetail(subjects: current.map(attendanceRow)))
        for (i, s) in current.enumerated() {
            await put("daily:\(now.id):\(s.id)", DailyAttendance(classes: classes(s, today, i)))
        }

        await put("subj_sems", sems)
        await put("subj:\(now.id)", RegisteredSubjects(rows: current.flatMap(registration)))
        for (i, list) in past.enumerated() {
            let rows = list.enumerated().map { j, pair in
                SubjectFaculty(
                    subjectId: "P\(i)\(j)", code: pair.0, name: pair.1, component: pair.1.contains("LAB") ? "P" : "L",
                    faculty: people[(i + j) % people.count], credits: credits(pair.1)
                )
            }
            await put("subj:\(sems[i + 1].id)", RegisteredSubjects(rows: rows))
        }
        await put("program", StudentProgram(branch: "Computer Science and Engineering", program: "B.Tech", maxSemesters: 8))

        // results for semesters 1 to 6, the past ones oldest first
        let graded = past.indices.reversed().map { i in (sems[i + 1], Array(zip(past[i], grades[i]))) }
        await put("gc_sems", graded.map(\.0).reversed() as [Semester])
        var gp = 0.0
        var cr = 0.0
        var results: [SemesterResult] = []
        for (n, (sem, subjects)) in graded.enumerated() {
            let entries = subjects.map { s, g in
                GradeEntry(code: s.0, name: s.1, grade: g, gradePoint: points[g]!, credits: credits(s.1), earned: credits(s.1), semester: n + 1)
            }
            await put("gc:\(sem.id)", GradeCard(entries: entries))
            let c = entries.reduce(0) { $0 + $1.credits }
            let p = entries.reduce(0) { $0 + $1.gradePoint * $1.credits }
            gp += p
            cr += c
            results.append(SemesterResult(semester: n + 1, sgpa: round1(p / c), cgpa: round2(gp / cr), courseCredits: c, earnedCredits: c, cumulativeCredits: cr))
        }
        await put("results", results)
        await put("credits", Credits(registeredCredits: Int(current.reduce(0) { $0 + $1.credits }), required: 160, earned: Int(cr)))

        // exams: t1 is done, t2 starts in two days
        let t1 = ExamEvent(id: "E1", code: "T1", description: "T1 examination", semesterId: now.id)
        let t2 = ExamEvent(id: "E2", code: "T2", description: "T2 examination", semesterId: now.id)
        await put("exam_sems", Array(sems.prefix(2)))
        await put("exam_ev:\(now.id)", [t2, t1])
        let theory = current.filter { $0.parts.contains("L") && !$0.audit }
        await put("exam_sch:\(t1.id)", theory.enumerated().map { i, s in
            slot(s, today.adding(days: -40 + i), i % 2 == 0 ? ("09:00 am", "10:00 am") : ("02:00 pm", "03:00 pm"), i, seated: true)
        })
        // the portal's own shapes: "03:30 pm" and a whole "x to y" window, rooms only from a day or two out
        let t2Days = [2, 2, 3, 6, 7, 9]
        await put("exam_sch:\(t2.id)", theory.enumerated().map { i, s in
            let d = t2Days[i % t2Days.count]
            return slot(s, today.adding(days: d), i % 2 == 0 ? ("09:30 am", "11:00 am") : ("02:30 pm", "04:00 pm"), i, seated: d <= 3)
        })

        await put("marks_sems", Array(sems.prefix(2)))
        await put("marks:\(now.id)", marks(theory))

        var g = GeneralInfo()
        g.name = session.name
        g.enrollmentNo = session.enrollmentNo
        g.program = "B.Tech"
        g.branch = "CSE"
        g.batch = "F7"
        g.section = "F"
        g.semester = 7
        g.admissionYear = "2023"
        g.dateOfBirth = "14-02-2005"
        g.gender = "Male"
        g.bloodGroup = "B+"
        g.nationality = "Indian"
        g.category = "General"
        g.collegeEmail = "99103042@mail.jiit.ac.in"
        g.personalEmail = "yash.malik@example.com"
        g.phone = "90000 12345"
        g.fatherName = "RAJESH MALIK"
        g.motherName = "SUNITA MALIK"
        g.currentCity = "Noida"
        g.currentState = "Uttar Pradesh"
        await put("personal", PersonalInfo(general: g, qualifications: [
            Qualification(code: "XII", board: "CBSE", year: "2023", percent: 92.4),
            Qualification(code: "X", board: "CBSE", year: "2021", percent: 95.2),
        ]))
        await put("bank", BankInfo(bank: "STATE BANK OF INDIA", account: "30211456789", ifsc: "SBIN0001234", holder: "YASH MALIK",
                                   address: "SECTOR 62", city: "NOIDA", state: "UTTAR PRADESH", pin: "201309", frozen: "Y"))
        await put("hostel", HostelAllotment(HostelInfo(hostel: "GIRIRAJ BHAWAN", hostelCode: "H3", room: "B-214", floor: "2", bed: "Bed 1",
                                                        roomType: "TWO SEATER", hostelType: "BOYS HOSTEL", from: "15-07-2026", until: "31-12-2026")))
        await put("fees", FeeSummary(heads: [
            FeeHead(semester: 7, type: "Regular", fee: 198000, paid: 148000, due: 50000),
            FeeHead(semester: 6, type: "Regular", fee: 190000, paid: 190000),
            FeeHead(semester: 5, type: "Regular", fee: 190000, paid: 180000, waived: 10000),
        ]))
        await put("feedback", [FeedbackEvent(id: "FB1", description: "Odd semester 2026 feedback", code: "FB2026ODD")])

        // registration: this semester's choice print and its moocs, frozen before classes began
        let frozen = today.adding(days: -70).date(at: ClockTime(hour: 12, minute: 29))
        await put("choice_sems", [now])
        await put("choices:\(now.id)", choices(stamp(frozen, "dd-MM-yyyy hh:mm a")))
        await put("mooc_sems", [now])
        await put("mooc:\(now.id)", mooc(frozen))
    }

    private static func stamp(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: d)
    }

    /// core comes without picking, each elective basket hands out one and the hss one missed the first pick
    private static func choices(_ frozen: String) -> [SubjectChoice] {
        let de = ("DE7", "DEPARTMENTAL ELECTIVE")
        let hs = ("HS7", "HSS ELECTIVE")
        func pick(_ code: String, _ name: String, _ basket: (String, String), _ credits: Double, _ preference: Int, _ got: Bool) -> SubjectChoice {
            SubjectChoice(code: code, name: name, basket: basket.0, basketName: basket.1, type: "Elective", credits: credits,
                          preference: preference, running: got ? "Y" : "N", elective: "Y", maxSubjects: 1, frozenAt: frozen)
        }
        let core = current.filter { $0.id != "S3" && $0.id != "S6" }.map { s in
            SubjectChoice(code: s.code, name: s.name, basket: "C7", basketName: "CORE", type: "Core", credits: s.credits,
                          running: "Y", audit: s.audit ? "Y" : "N", frozenAt: frozen)
        }
        return core + [
            pick("15B1NCI731", "CLOUD COMPUTING", de, 4, 1, true),
            pick("15B1NCI734", "BLOCKCHAIN TECHNOLOGY", de, 4, 2, false),
            pick("15B1NCI735", "COMPUTER VISION", de, 4, 3, false),
            pick("16B1NHS733", "CONSUMER BEHAVIOUR", hs, 3, 1, false),
            pick("16B1NHS732", "MARKETING MANAGEMENT", hs, 3, 2, true),
            pick("16B1NHS734", "INTERNATIONAL TRADE", hs, 3, 3, false),
        ]
    }

    /// one waiting on approval, one approved, one turned down, and the exam fee still due
    private static func mooc(_ from: Date) -> MoocStatus {
        func on(_ days: Int) -> String { stamp(from.addingTimeInterval(TimeInterval(days) * 86400), "dd-MMM-yyyy hh:mm a") }
        let submitted = "Submitted on \(on(0))@D"
        let reviewed = "1. Review  Date:- \(on(3))  by DR. MEERA IYER (REVIEW BY MOOCD )@D"
        return MoocStatus(
            requests: [
                MoocRequest(code: "NOC26-CS45", name: "PRIVACY AND SECURITY IN ONLINE SOCIAL MEDIA",
                            choiceType: "CURRENT Againts(15B1NCI731-CLOUD COMPUTING)", status: "Pending",
                            rawStages: [submitted, reviewed, "2. Approved@P"]),
                MoocRequest(code: "NOC26-HS21", name: "ENTREPRENEURSHIP ESSENTIALS", choiceType: "ADDITIONAL", status: "Approved",
                            rawStages: [submitted, reviewed, "2. Approved  Date:- \(on(6))  by DR. POOJA DAS (APPROVED BY HOD )@D"]),
            ],
            rejected: [
                MoocRequest(code: "NOC26-CS10", name: "BLOCKCHAIN AND ITS APPLICATIONS",
                            choiceType: "CURRENT Againts(16B1NHS732-MARKETING MANAGEMENT)", status: "Rejected",
                            rawStages: [submitted, "1. Rejected  Date:- \(on(2))  by DR. MEERA IYER (REVIEW BY MOOCD )@D"]),
            ],
            dues: 1000
        )
    }

    private static func attendanceRow(_ s: Subj) -> SubjectAttendance {
        // the portal's own percentages lag a day behind and round, close enough to the class list
        let pct = Double(s.odds) / 10
        let l = s.parts.contains("L"), t = s.parts.contains("T"), p = s.parts.contains("P")
        return SubjectAttendance(
            subjectId: s.id, code: s.code, title: title(s),
            combinedPercent: l ? pct : nil, lecturePercent: l ? pct : nil,
            tutorialPercent: t ? min(100, pct + 4) : nil, practicalPercent: p ? pct : nil,
            lectureComponent: l ? "\(s.id)L" : nil, tutorialComponent: t ? "\(s.id)T" : nil, practicalComponent: p ? "\(s.id)P" : nil
        )
    }

    /// splitmix64, so the demo's attendance is the same on every launch
    private struct Rng {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Int((z ^ (z >> 31)) % UInt64(bound))
        }
    }

    /// nine weeks of classes up to yesterday, on the subject's weekdays
    private static func classes(_ s: Subj, _ today: Day, _ seed: Int) -> [ClassRecord] {
        if s.days.isEmpty { return [] }
        var rnd = Rng(state: UInt64(seed * 31 + 7))
        let slots = ["09:00:AM - 09:50 AM", "10:00:AM - 10:50 AM", "11:00:AM - 11:50 AM", "02:00:PM - 02:50 PM", "03:00:PM - 04:50 PM"]
        let start = today.adding(days: -63)
        var out: [ClassRecord] = []
        var i = 0
        var d = start
        while d < today {
            if s.days.contains(d.weekdayFromMonday) {
                let lab = s.parts == "P"
                let kind: Character = !lab && i % 4 == 3 && s.parts.contains("T") ? "T" : s.parts.first!
                out.append(ClassRecord(
                    datetime: String(format: "%02d/%02d/%04d", d.day, d.month, d.year) + " (\(slots[lab ? 4 : (seed + i) % 4]))",
                    present: rnd.next(1000) < s.odds ? "Present" : "Absent",
                    takenBy: s.teachers[kind] ?? s.teachers.values.first!,
                    classType: i % 11 == 10 ? "Extra" : "Regular"
                ))
                i += 1
            }
            d = d.adding(days: 1)
        }
        return out
    }

    private static func registration(_ s: Subj) -> [SubjectFaculty] {
        s.parts.map { c in
            SubjectFaculty(subjectId: s.id, code: s.code, name: s.name, component: String(c), faculty: s.teachers[c] ?? "",
                           credits: s.credits, audit: s.audit ? "Y" : "N")
        }
    }

    private static func slot(_ s: Subj, _ day: Day, _ time: (String, String), _ i: Int, seated: Bool) -> ExamSlot {
        ExamSlot(
            date: String(format: "%02d/%02d/%04d", day.day, day.month, day.year), from: time.0, until: "\(time.0) to \(time.1)",
            subject: title(s), code: s.code,
            room: seated ? ["CR-4", "LT-2", "G-7", "CR-11"][i % 4] : "", seat: seated ? "B\(12 + i * 3)" : ""
        )
    }

    private static func marks(_ theory: [Subj]) -> MarksReport {
        let t1: [(Double, Double)] = [(17.5, 20), (13, 20), (9, 20), (15, 20), (18, 20)]
        return MarksReport(
            student: MarksStudent(name: session.name, enrollmentNo: session.enrollmentNo, program: "B.Tech", branch: "CSE", semester: "7", registrationCode: "2026ODDSEM"),
            events: ["T1", "T2", "T3"],
            subjects: theory.enumerated().map { i, s in
                let (got, max) = t1[i % t1.count]
                return SubjectMarks(code: s.code, name: s.name, scores: [
                    EventScore(event: "T1", marks: .value(obtained: got, max: max), weighted: .value(obtained: got * 0.75, max: 15)),
                    EventScore(event: "T2", marks: .notApplicable, weighted: .notApplicable),
                    EventScore(event: "T3", marks: .notApplicable, weighted: .notApplicable),
                ])
            }
        )
    }
}
