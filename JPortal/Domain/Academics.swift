import Foundation
import JPortalKit

/// one point on the gpa chart, real or projected
struct GpaPoint: Equatable, Identifiable {
    let semester: Int
    var sgpa: Double
    let credits: Double
    var cgpa: Double
    var projected: Bool
    var id: Int { semester }
}

/**
 * port of jportal's gpaCalculations: cgpa is credit weighted sgpa over every
 * semester so far. projections are extra semesters the user drags around.
 */
enum Gpa {
    static func points(_ results: [SemesterResult], projections: [Int: Double], projectedCredits: Double, maxSemesters: Int) -> [GpaPoint] {
        let real = results.sorted { $0.semester < $1.semester }.map {
            GpaPoint(semester: $0.semester, sgpa: $0.sgpa, credits: $0.courseCredits > 0 ? $0.courseCredits : $0.earnedCredits, cgpa: $0.cgpa, projected: false)
        }
        let next = (real.map(\.semester).max() ?? 0) + 1
        let future = next <= maxSemesters ? (next...maxSemesters).compactMap { s in
            projections[s].map { GpaPoint(semester: s, sgpa: $0, credits: projectedCredits, cgpa: 0, projected: true) }
        } : []
        let adjusted = real.map { p in
            projections[p.semester].map { var q = p; q.sgpa = $0; q.projected = true; return q } ?? p
        }
        return recompute(adjusted + future)
    }

    /// recomputes cgpa down the line; real untouched semesters keep the portal's own figure
    static func recompute(_ points: [GpaPoint]) -> [GpaPoint] {
        var gp = 0.0
        var cr = 0.0
        var anyProjected = false
        return points.map { p in
            gp += p.sgpa * p.credits
            cr += p.credits
            anyProjected = anyProjected || p.projected
            if !anyProjected { return p }
            var q = p
            q.cgpa = cr > 0 ? gp / cr : 0
            return q
        }
    }
}

/// a registered subject, its L/T/P rows folded into one
struct SubjectInfo: Identifiable, Hashable {
    let semesterCode: String
    let code: String
    let name: String
    let credits: Double
    /// component letter to teacher, in L, T, P order
    let teachers: [Teacher]
    let audit: Bool
    let grade: String?

    struct Teacher: Hashable {
        let component: String
        let name: String
    }

    var id: String { "\(semesterCode)/\(code)" }
    var lab: Bool { !teachers.isEmpty && teachers.allSatisfy { $0.component == "P" } }
}

/// one semester as the academics tab sees it, stitched from results, grade cards and registrations
struct SemesterInfo: Identifiable {
    let code: String
    let number: Int?
    let result: SemesterResult?
    let grades: [GradeEntry]
    let subjects: [SubjectInfo]
    let current: Bool
    var id: String { code }

    var title: String { number.map { "Semester \($0)" } ?? prettySemester(code) }
}

/// everything the academics, subjects and grade card screens need, read off the stores
struct Academics {
    let semesters: [SemesterInfo]
    let results: Store<[SemesterResult]>?
    let currentCode: String?
    let loading: Bool

    func semester(_ code: String) -> SemesterInfo? { semesters.first { $0.code == code } }

    /// reads stores only, kick them with [refreshAll]
    static func read(_ repo: Repository) -> Academics {
        let meta = repo.attendanceMeta
        let currentNumber = meta.data?.header?.semesterNumber ?? ""
        let currentCode = meta.data?.semesters.first?.code
        let results = currentNumber.isEmpty ? nil : repo.results(currentNumber)
        let gradeSems = repo.gradeSemesters.data ?? []
        let subjSems = repo.subjectSemesters.data ?? []
        let cards = Dictionary(gradeSems.map { ($0.code, repo.gradeCard($0)) }, uniquingKeysWith: { a, _ in a })
        let regs = Dictionary(subjSems.map { ($0.code, repo.subjects($0)) }, uniquingKeysWith: { a, _ in a })

        let grades = cards.mapValues { $0.data?.entries ?? [] }
        let rows = regs.mapValues { $0.data?.rows ?? [] }
        let byNumber = Dictionary((results?.data ?? []).map { ($0.semester, $0) }, uniquingKeysWith: { a, _ in a })
        // the grade card's stynumber is just today's semester on every card, so count terms back from the current one instead
        let anchor = currentCode.flatMap(term)
        let anchorNumber = Int(currentNumber)
        func numberOf(_ code: String) -> Int? {
            guard let t = term(code), let anchor, let anchorNumber else { return nil }
            let n = anchorNumber - (anchor - t)
            return n > 0 ? n : nil
        }
        var codes: [String] = []
        for c in [currentCode].compactMap({ $0 }) + subjSems.map(\.code) + gradeSems.map(\.code) where !codes.contains(c) { codes.append(c) }
        let semesters = codes.map { code -> SemesterInfo in
            let g = grades[code] ?? []
            let number = numberOf(code)
            return SemesterInfo(
                code: code, number: number, result: number.flatMap { byNumber[$0] }, grades: g,
                subjects: fold(code, rows[code] ?? [], g), current: code == currentCode
            )
        }.sorted { a, b in
            if a.current != b.current { return a.current }
            return (term(a.code) ?? 0) > (term(b.code) ?? 0)
        }

        let pending = { (s: Store<RegisteredSubjects>) in s.data == nil && s.error == nil }
        let loading = (meta.data == nil && meta.error == nil)
            || (repo.gradeSemesters.data == nil && repo.gradeSemesters.error == nil)
            || (repo.subjectSemesters.data == nil && repo.subjectSemesters.error == nil)
            || regs.values.contains(where: pending)
            || cards.values.contains { $0.data == nil && $0.error == nil }
        return Academics(semesters: semesters, results: results, currentCode: currentCode, loading: loading)
    }

    static func refreshAll(_ repo: Repository, force: Bool = false) {
        repo.attendanceMeta.refresh(force: force)
        repo.gradeSemesters.refresh(force: force)
        repo.subjectSemesters.refresh(force: force)
        if let n = repo.attendanceMeta.data?.header?.semesterNumber, !n.isEmpty { repo.results(n).refresh(force: force) }
        for s in repo.gradeSemesters.data ?? [] { repo.gradeCard(s).refresh(force: force) }
        for s in repo.subjectSemesters.data ?? [] { repo.subjects(s).refresh(force: force) }
    }

    private static func fold(_ semesterCode: String, _ rows: [SubjectFaculty], _ grades: [GradeEntry]) -> [SubjectInfo] {
        let order = ["L", "T", "P"]
        var codes: [String] = []
        var groups: [String: [SubjectFaculty]] = [:]
        for r in rows {
            if groups[r.code] == nil { codes.append(r.code) }
            groups[r.code, default: []].append(r)
        }
        return codes.map { code in
            let parts = groups[code]!
            var teachers: [SubjectInfo.Teacher] = []
            for p in parts.filter({ !$0.facultyName.isBlank }).sorted(by: { (order.firstIndex(of: $0.component) ?? 9) < (order.firstIndex(of: $1.component) ?? 9) }) {
                let t = SubjectInfo.Teacher(component: p.component, name: p.facultyName)
                if !teachers.contains(t) { teachers.append(t) }
            }
            return SubjectInfo(
                semesterCode: semesterCode, code: code, name: parts[0].name,
                credits: parts.map(\.credits).max() ?? 0, teachers: teachers,
                audit: parts.contains { $0.isAudit },
                grade: grades.first { $0.code == code }?.grade.nonBlank
            )
        }
    }
}
