import Foundation

/// one line of the choice print. electives list every pick, core baskets just their subjects
public struct SubjectChoice: Codable, Sendable, Hashable {
    public var code = ""
    public var name = ""
    public var basket = ""
    public var basketName = ""
    /// "Core", "Departmental Electives"
    public var type = ""
    public var credits: Double = 0
    /// 1 is the first pick. 0 is a subject you got without picking it
    public var preference = 0
    public var running = "N"
    public var audit = "N"
    public var elective = "N"
    /// how many a basket hands out
    public var maxSubjects = 0
    /// "24-07-2026 12:29 PM"
    public var frozenAt = ""

    public init(
        code: String = "", name: String = "", basket: String = "", basketName: String = "", type: String = "",
        credits: Double = 0, preference: Int = 0, running: String = "N", audit: String = "N", elective: String = "N",
        maxSubjects: Int = 0, frozenAt: String = ""
    ) {
        self.code = code
        self.name = name
        self.basket = basket
        self.basketName = basketName
        self.type = type
        self.credits = credits
        self.preference = preference
        self.running = running
        self.audit = audit
        self.elective = elective
        self.maxSubjects = maxSubjects
        self.frozenAt = frozenAt
    }

    init(json j: JSON) {
        code = j.str("subjectcode")
        name = j.str("subjectdesc")
        basket = j.str("basketcode")
        basketName = j.str("basketdesc")
        type = j.str("subjecttypedesc")
        credits = j.dbl("credits")
        preference = j.int("preference")
        running = j.str("running", "N")
        audit = j.str("auditsubject", "N")
        elective = j.str("electivetype", "N")
        maxSubjects = j.int("maxsubject")
        frozenAt = j.str("freezeddatetime")
    }

    public var isAllotted: Bool { running == "Y" }
    public var isAudit: Bool { audit == "Y" }
    public var isElective: Bool { elective == "Y" }
}

/// one step of a mooc request's approval
public struct MoocStage: Sendable, Hashable {
    public let title: String
    public let at: Date?
    public let by: String?
    public let done: Bool
}

public struct MoocRequest: Codable, Sendable, Hashable {
    public var code = ""
    public var name = ""
    /// "CURRENT Againts(16B1NPH533-LASER TECHNOLOGY AND APPLICATIONS)", typo and all
    public var choiceType = ""
    public var status = ""
    public var rawStages: [String] = []

    public init(code: String = "", name: String = "", choiceType: String = "", status: String = "", rawStages: [String] = []) {
        self.code = code
        self.name = name
        self.choiceType = choiceType
        self.status = status
        self.rawStages = rawStages
    }

    init(json j: JSON) {
        code = j.str("subjectcode")
        name = j.str("subjectdesc")
        choiceType = j.str("choicetype")
        status = j.str("approvalstatus")
        rawStages = j["totalStages"].array.map { $0.string ?? "" }
    }

    private static let replacesRx = Rx(#"\(([^-()]+)-(.+)\)"#)

    /// code and name of the subject this mooc stands in for
    public var replaces: (code: String, name: String)? {
        guard let m = MoocRequest.replacesRx.first(in: choiceType) else { return nil }
        return (m.groups[1].trimmed, m.groups[2].trimmed)
    }

    /// skipped stages come back as empty strings, they're left out
    public var stages: [MoocStage] { rawStages.compactMap(parseStage) }

    public var isApproved: Bool { stages.contains { $0.done && $0.title.caseInsensitiveCompare("Approved") == .orderedSame } }
}

public struct MoocStatus: Codable, Sendable, Hashable {
    public var requests: [MoocRequest] = []
    public var rejected: [MoocRequest] = []
    public var dues: Double = 0

    public init(requests: [MoocRequest] = [], rejected: [MoocRequest] = [], dues: Double = 0) {
        self.requests = requests
        self.rejected = rejected
        self.dues = dues
    }

    init(json j: JSON) {
        requests = j["totalsubjectDetailList"].array.map(MoocRequest.init(json:))
        rejected = j["totalRejsubjectDetailList"].array.map(MoocRequest.init(json:))
        dues = j.dbl("duesAmount")
    }
}

private let stageTime: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "dd-MMM-yyyy hh:mm a"
    return f
}()

private let stageRx = Rx(#"^(.+?)\s+(?:on|Date:-)\s+(\d{1,2}-[A-Za-z]{3}-\d{4} \d{1,2}:\d{2} [AP]M)(?:\s+by\s+([^(]+))?"#)
private let leadingNumber = Rx(#"^\d+\.\s*"#)

/**
 * "Submitted on 24-Jul-2026 12:29 PM@D" or
 * "1. Review  Date:- 30-Jul-2026 02:31 PM  by SOME  NAME (REVIEW BY MOOCD )@D".
 * the letter after @ is the stage's state, D once it's done.
 */
func parseStage(_ raw: String) -> MoocStage? {
    let beforeAt = raw.range(of: "@", options: .backwards).map { String(raw[..<$0.lowerBound]) } ?? raw
    let text = leadingNumber.replacing(in: beforeAt.squashed, with: "")
    if text.isEmpty { return nil }
    let state = raw.range(of: "@", options: .backwards).map { String(raw[$0.upperBound...]).trimmed } ?? ""
    guard let m = stageRx.first(in: text) else {
        return MoocStage(title: text, at: nil, by: nil, done: state == "D")
    }
    let by = m.groups[3].trimmed
    return MoocStage(title: m.groups[1].trimmed, at: stageTime.date(from: m.groups[2]), by: by.isEmpty ? nil : by, done: state == "D")
}
