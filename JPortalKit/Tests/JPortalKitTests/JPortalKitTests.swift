import Foundation
import Testing
@testable import JPortalKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Suite struct CryptoTests {
    // vectors from ktjiit, themselves from an independent python implementation
    @Test(arguments: [
        ("2026-09-23T20:44:33+05:30", "2023396", "0OE33AqLdJLsiqun/b7P0ebzcZlU9Zex+WARnofRJmk="),
        ("2026-09-20T23:59:59+05:30", "2020096", "6OcujOtkGhS78wcGcPqDz/SQLWnIHprl1x2aIuWVdq8="),
        ("2026-09-20T18:30:00+00:00", "2021196", "NFduuMZDQ4pnjC6rENqxPC3BIz9Ss0uI1lxVmttCoNg="),
        ("2027-01-01T00:00:00+05:30", "0025117", "QaE6RaKmOSXveL+WS5Yjun1r6o39jDJ10IwjB69Hk2Q="),
    ])
    func vectors(at: String, seq: String, cipher: String) throws {
        let t = iso(at)
        #expect(dateSeq(t) == seq)
        #expect(PortalCipher.encrypt(#"{"instituteid":"TEST"}"#, at: t) == cipher)
        #expect(try PortalCipher.decrypt(cipher, at: t) == #"{"instituteid":"TEST"}"#)
    }

    @Test func utcEveningIsAlreadyTomorrowInIST() {
        #expect(dateSeq(iso("2026-09-20T18:30:00Z")) == "2021196")
        #expect(dateSeq(iso("2026-09-20T18:29:59Z")) == "2020096")
    }

    @Test func localNameCarriesDateSeqBetweenNoise() throws {
        let t = iso("2026-09-23T15:14:33Z")
        let plain = try PortalCipher.decrypt(PortalCipher.localName(t), at: t)
        #expect(plain.count == 16)
        #expect(String(Array(plain)[4..<11]) == dateSeq(t))
    }

    @Test func clockFollowsTheServerDateHeader() {
        let local = iso("2026-09-23T15:44:00Z")
        let clock = PortalClock { local }
        clock.observe("Wed, 23 Sep 2026 15:35:32 GMT")
        #expect(clock.skew == -508)
        #expect(clock.now() == iso("2026-09-23T15:35:32Z"))
        clock.observe("garbage")
        #expect(clock.skew == -508)
    }

    @Test func payloadKeepsKeyOrder() {
        let p = Payload(["b": "1", "a": .array([["x": "y"]])])
        #expect(p.serialized == #"{"b":"1","a":[{"x":"y"}]}"#)
    }
}

@Suite struct TransportTests {
    let t = Transport()

    private func raw(_ code: Int, _ body: String) -> Transport.Raw {
        Transport.Raw(code: code, body: Data(body.utf8), contentType: "application/json")
    }

    @Test func successUnwrapsResponse() throws {
        let r = try t.unwrap(raw(200, #"{"status":{"responseStatus":"Success","errors":null},"response":{"a":1}}"#))
        #expect(r["a"].int == 1)
    }

    @Test func errorsMapToTheRightCase() {
        #expect(throws: PortalError.sessionExpired) { try t.unwrap(raw(401, "")) }
        #expect(throws: PortalError.forbidden) { try t.unwrap(raw(403, "")) }
        #expect(throws: PortalError.emptyResponse) { try t.unwrap(raw(200, "")) }
        #expect(throws: PortalError.serverUnavailable(code: 502, shape: "application/json, 4 bytes")) { try t.unwrap(raw(502, "oops")) }
        do {
            _ = try t.unwrap(raw(200, #"{"status":{"responseStatus":"Failure","errors":["NO ATTENDANCE FOUND"]}}"#))
            Issue.record("should throw")
        } catch let e as PortalError {
            #expect(e.isNoData)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func sessionExpiryComesFromTheJwt() {
        // {"exp":1790000000}
        let s = Session(token: "x.eyJleHAiOjE3OTAwMDAwMDB9.y", username: "u", instituteId: "i")
        #expect(s.expiresAt == Date(timeIntervalSince1970: 1_790_000_000))
    }
}

@Suite struct ModelTests {
    private func response(_ name: String) throws -> JSON {
        try JSON.parse(try fixture(name))["response"]
    }

    @Test func attendanceDetailAndDaily() throws {
        let d = AttendanceDetail(json: try response("att_detail_2026ODDSEM.json"))
        #expect(!d.subjects.isEmpty)
        let first = try #require(d.subjects.first)
        #expect(first.code == "20B13HS311")
        #expect(first.name == "INDIAN CONSTITUTION & TRADITIONAL KNOWLEDGE")
        #expect(first.percent == 63.2)

        let daily = DailyAttendance(json: try response("daily_26B16CS315.json"))
        #expect(!daily.classes.isEmpty)
        let c = try #require(daily.classes.first)
        #expect(c.date == Day(year: 2026, month: 9, day: 21))
        #expect(c.start == ClockTime(hour: 8, minute: 0))
        #expect(c.end == ClockTime(hour: 9, minute: 50))
    }

    @Test func everyFixtureDecodes() throws {
        let meta = AttendanceMeta(json: try response("att_meta.json"))
        #expect(!meta.semesters.isEmpty && meta.header != nil)
        #expect(!SemesterResult.list(try response("sgpa_all.json")).isEmpty)
        #expect(!GradeCard(json: try response("gradecard_2026EVESEM.json")).entries.isEmpty)
        #expect(!RegisteredSubjects(json: try response("faculties.json")).rows.isEmpty)
        #expect(!(try response("exam_schedule.json"))["subjectinfo"].array.map(ExamSlot.init(json:)).isEmpty)
        #expect(!(try response("exam_events.json"))["eventcode"]["examevent"].array.map(ExamEvent.init(json:)).isEmpty)
        #expect(!PersonalInfo(json: try response("personal.json")).general.name.isEmpty)
        #expect(!FeeSummary(json: try response("fees.json")).heads.isEmpty)
        #expect(!BankInfo(json: try response("bank.json")["bankinfo"]).ifsc.isEmpty)
        #expect(!(try response("choices.json"))["subjectpreferencegrid"].array.map(SubjectChoice.init(json:)).isEmpty)
        let mooc = MoocStatus(json: try response("mooc_status.json"))
        #expect(!(mooc.requests + mooc.rejected).isEmpty)
        #expect(Credits(json: try response("credits.json")).required > 0)
    }

    @Test func moocStages() {
        let done = parseStage("1. Review  Date:- 30-Jul-2026 02:31 PM  by SOME  NAME (REVIEW BY MOOCD )@D")
        #expect(done?.title == "Review")
        #expect(done?.by == "SOME NAME")
        #expect(done?.done == true)
        #expect(done?.at != nil)
        #expect(parseStage("2. Approved@P")?.done == false)
        #expect(parseStage("") == nil)
    }

    @Test func clockShapes() {
        func t(_ h: Int, _ m: Int = 0) -> ClockTime { ClockTime(hour: h, minute: m) }
        #expect(parseClocks("03:30 pm") == [t(15, 30)])
        #expect(parseClocks("3:30PM") == [t(15, 30)])
        #expect(parseClocks("09:00:AM") == [t(9)])
        #expect(parseClocks("14:00") == [t(14)])
        #expect(parseClocks("14:00:00") == [t(14)])
        #expect(parseClocks("12:15 am to 12:45 PM") == [t(0, 15), t(12, 45)])
        #expect(parseClocks("TBA") == [])
        #expect(parseClocks("14:00 pm") == [])

        let s = ExamSlot(date: "12/10/2026", from: "03:30 pm", until: "03:30 pm to 04:30 pm")
        #expect(s.start == t(15, 30) && s.end == t(16, 30))
        #expect(ExamSlot(until: "09:00 am to 10:00 am").start == t(9))
        #expect(ExamSlot(from: "04:30 pm", until: "04:30 pm").end == nil)
    }

    @Test func presentOverRegularMatchesThePortal() {
        func rows(_ regular: Int, _ rp: Int, _ extra: Int, _ ep: Int) -> DailyAttendance {
            DailyAttendance(classes:
                (0..<regular).map { ClassRecord(datetime: "01/09/2026 (09:00:AM - 09:50 AM)", present: $0 < rp ? "Present" : "Absent", classType: "Regular") } +
                (0..<extra).map { ClassRecord(datetime: "02/09/2026 (09:00:AM - 09:50 AM)", present: $0 < ep ? "Present" : "Absent", classType: "Extra") })
        }
        for c in [(39, 34, 3, 3, 94.9), (49, 39, 2, 1, 81.6), (22, 18, 1, 1, 86.4), (51, 41, 2, 0, 80.4), (38, 34, 1, 1, 92.1)] {
            let d = rows(c.0, c.1, c.2, c.3)
            #expect((Double(d.attended) * 1000 / Double(d.total)).rounded() / 10 == c.4)
        }
    }

    @Test func civilDays() {
        let d = Day(year: 2026, month: 9, day: 20)
        #expect(d.weekdayFromSunday == 0)
        #expect(Day(epochDay: d.epochDay) == d)
        #expect(d.adding(days: 12) == Day(year: 2026, month: 10, day: 2))
        #expect(Day(year: 2026, month: 1, day: 31).addingMonths(1) == Day(year: 2026, month: 2, day: 28))
        #expect(Day.parse(ddMMyyyy: "31/02/2026") == nil)
    }
}

extension SemesterResult {
    static func list(_ j: JSON) -> [SemesterResult] { j["semesterList"].array.map(SemesterResult.init(json:)) }
}

@Suite struct MarksParserTests {
    private func score(_ j: JSON) -> Score? {
        switch j["type"].string {
        case "value": return .value(obtained: j.dbl("obtained"), max: j.dbl("max"))
        case "absent": return .absent
        case "na": return .notApplicable
        case "other": return .other(j.str("raw"))
        default: return nil
        }
    }

    /// the kotlin goldens, read into the swift model
    private func golden(_ name: String) throws -> MarksReport {
        let j = try JSON.parse(try fixture("\(name).json"))
        let s = j["student"]
        return MarksReport(
            student: MarksStudent(
                name: s.str("name"), enrollmentNo: s.str("enrollmentNo"), program: s.str("program"),
                branch: s.str("branch"), semester: s.str("semester"), registrationCode: s.str("registrationCode")
            ),
            events: j["events"].array.compactMap(\.string),
            subjects: j["subjects"].array.map { sub in
                SubjectMarks(code: sub.str("code"), name: sub.str("name"), scores: sub["scores"].array.map { e in
                    EventScore(event: e.str("event"), marks: score(e["marks"]), weighted: score(e["weighted"]))
                })
            },
            generated: j.str("generated")
        )
    }

    // goldens were cross-checked value by value against pdftotext -layout in ktjiit
    @Test(arguments: [
        "ece8-absent", "empty", "cse5-single-event", "cse5-seven-events", "cse3-nine-events-wrapped",
        "cse2-seven-events", "cse1-seven-events", "wa1", "wa2", "wa3", "wa4", "wa5", "wa6", "wa7",
    ])
    func golden(name: String) throws {
        let expected = try golden(name)
        let actual = try MarksParser.parse(try fixture("\(name).pdf"))
        #expect(actual.student == expected.student)
        #expect(actual.events == expected.events)
        #expect(actual.generated == expected.generated)
        #expect(actual.subjects.map(\.code) == expected.subjects.map(\.code))
        for (a, e) in zip(actual.subjects, expected.subjects) {
            #expect(a == e, "\(name) \(e.code)")
        }
    }

    @Test func absentKeepsTheZeroWeightage() throws {
        let r = try MarksParser.parse(try fixture("ece8-absent.pdf"))
        let s = try #require(r.subjects.first { $0.code == "15B1NHS832" }?.scores.first { $0.event == "T2-2026EVEN-20MARKS" })
        #expect(s.marks == .absent)
        #expect(s.weighted == .value(obtained: 0, max: 20))
    }

    @Test func wrappedHeaderAndFirstRowSurvive() throws {
        let r = try MarksParser.parse(try fixture("cse3-nine-events-wrapped.pdf"))
        #expect(r.events.count == 9)
        #expect(r.events.contains("MIDTR-25ODD-30 MARKS"))
        #expect(r.subjects.first?.code == "15B11CI311")
    }

    @Test func garbageIsRejected() {
        #expect(throws: MarksParseError.self) { try MarksParser.parse(Data("not a pdf at all".utf8)) }
    }

    @Test func scoreFormats() {
        #expect(Score.parse("15/ 40") == .value(obtained: 15, max: 40))
        #expect(Score.parse(" 15.5/20.0 ") == .value(obtained: 15.5, max: 20))
        #expect(Score.parse("-") == .notApplicable)
        #expect(Score.parse("A") == .absent)
        #expect(Score.parse("  ") == nil)
        #expect(Score.parse("W") == .other("W"))
    }
}
