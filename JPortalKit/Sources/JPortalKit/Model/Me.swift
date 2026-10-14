import Foundation

public struct GeneralInfo: Codable, Sendable, Hashable {
    public var name = ""
    public var enrollmentNo = ""
    public var program = ""
    public var branch = ""
    public var batch = ""
    public var section = ""
    public var semester = 0
    public var academicYear = ""
    public var admissionYear = ""
    public var dateOfBirth = ""
    public var gender = ""
    public var bloodGroup = ""
    public var nationality = ""
    public var category = ""
    public var apaarId = ""
    public var phone = ""
    public var collegeEmail = ""
    public var personalEmail = ""
    public var fatherName = ""
    public var motherName = ""
    public var parentPhone = ""
    public var parentEmail = ""
    public var permanentAddress1 = ""
    public var permanentAddress2 = ""
    public var permanentAddress3 = ""
    public var permanentCity = ""
    public var permanentDistrict = ""
    public var permanentState = ""
    public var permanentPin = ""
    public var currentAddress1 = ""
    public var currentAddress3 = ""
    public var currentCity = ""
    public var currentDistrict = ""
    public var currentState = ""
    public var currentPin = ""
    public var institute = ""

    public init() {}

    init(json j: JSON) {
        name = j.str("studentname")
        enrollmentNo = j.str("registrationno")
        program = j.str("programcode")
        branch = j.str("branch")
        batch = j.str("batch")
        section = j.str("sectioncode")
        semester = j.int("semester")
        academicYear = j.str("academicyear")
        admissionYear = j.str("admissionyear")
        dateOfBirth = j.str("dateofbirth")
        gender = j.str("gender")
        bloodGroup = j.str("bloodgroup")
        nationality = j.str("nationality")
        category = j.str("category")
        apaarId = j.str("apaarid")
        phone = j.str("studentcellno")
        collegeEmail = j.str("studentemailid")
        personalEmail = j.str("studentpersonalemailid")
        fatherName = j.str("fathersname")
        motherName = j.str("mothername")
        parentPhone = j.str("parentcellno")
        parentEmail = j.str("parentemailid")
        permanentAddress1 = j.str("paddress1")
        permanentAddress2 = j.str("paddress2")
        permanentAddress3 = j.str("paddress3")
        permanentCity = j.str("pcityname")
        permanentDistrict = j.str("pdistrict")
        permanentState = j.str("pstatename")
        permanentPin = j.str("ppostalcode")
        currentAddress1 = j.str("caddress1")
        currentAddress3 = j.str("caddress3")
        currentCity = j.str("ccityname")
        currentDistrict = j.str("cdistrict")
        currentState = j.str("cstatename")
        currentPin = j.str("cpostalcode")
        institute = j.str("institutecode")
    }
}

public struct Qualification: Codable, Sendable, Hashable {
    public var code = ""
    public var board = ""
    public var year = ""
    public var obtained: Double = 0
    public var full: Double = 0
    public var percent: Double = 0
    public var grade = ""
    public var cgpa: Double = 0

    public init(code: String = "", board: String = "", year: String = "", percent: Double = 0, cgpa: Double = 0) {
        self.code = code
        self.board = board
        self.year = year
        self.percent = percent
        self.cgpa = cgpa
    }

    init(json j: JSON) {
        code = j.str("qualificationcode")
        board = j.str("boardname")
        year = j.str("yearofpassing")
        obtained = j.dbl("obtainedmarks")
        full = j.dbl("fullmarks")
        percent = j.dbl("percentagemarks")
        grade = j.str("grade")
        cgpa = j.dbl("cgpa")
    }
}

public struct PersonalInfo: Codable, Sendable, Hashable {
    public var general = GeneralInfo()
    public var qualifications: [Qualification] = []
    /// base64 jpeg
    public var photo: String? = nil

    public init(general: GeneralInfo = GeneralInfo(), qualifications: [Qualification] = [], photo: String? = nil) {
        self.general = general
        self.qualifications = qualifications
        self.photo = photo
    }

    init(json j: JSON) {
        general = GeneralInfo(json: j["generalinformation"])
        qualifications = j["qualification"].array.map(Qualification.init(json:))
        photo = j["photo&signature"].optStr("photo")
    }
}

public struct BankInfo: Codable, Sendable, Hashable {
    public var bank = ""
    public var account = ""
    public var ifsc = ""
    public var holder = ""
    public var address = ""
    public var city = ""
    public var state = ""
    public var pin = ""
    public var holderType = ""
    /// Y once the office locks it
    public var frozen = ""

    public init(
        bank: String = "", account: String = "", ifsc: String = "", holder: String = "", address: String = "",
        city: String = "", state: String = "", pin: String = "", holderType: String = "", frozen: String = ""
    ) {
        self.bank = bank
        self.account = account
        self.ifsc = ifsc
        self.holder = holder
        self.address = address
        self.city = city
        self.state = state
        self.pin = pin
        self.holderType = holderType
        self.frozen = frozen
    }

    init(json j: JSON) {
        bank = j.str("bankname")
        account = j.str("bankaccountnumber")
        ifsc = j.str("ifsccode")
        holder = j.str("accountholdername")
        address = j.str("bankaddress")
        city = j.str("bankcity")
        state = j.str("bankstate")
        pin = j.str("bankcitypin")
        holderType = j.str("acholdertypeflag")
        frozen = j.str("freezed")
    }
}

public struct HostelInfo: Codable, Sendable, Hashable {
    public var hostel = ""
    public var hostelCode = ""
    public var room = ""
    public var floor = ""
    public var bed = ""
    public var roomType = ""
    public var hostelType = ""
    public var from = ""
    public var until = ""
    public var leftOn: String? = nil

    public init(
        hostel: String = "", hostelCode: String = "", room: String = "", floor: String = "", bed: String = "",
        roomType: String = "", hostelType: String = "", from: String = "", until: String = "", leftOn: String? = nil
    ) {
        self.hostel = hostel
        self.hostelCode = hostelCode
        self.room = room
        self.floor = floor
        self.bed = bed
        self.roomType = roomType
        self.hostelType = hostelType
        self.from = from
        self.until = until
        self.leftOn = leftOn
    }

    init(json j: JSON) {
        hostel = j.str("hosteldescription")
        hostelCode = j.str("hostelcode")
        room = j.str("allotedroomno")
        floor = j.str("floor")
        bed = j.str("beddesc")
        roomType = j.str("roomtype")
        hostelType = j.str("hosteltypedesc")
        from = j.str("allotedfromdate")
        until = j.str("allotedtilldate")
        leftOn = j.optStr("hostellefton")
    }
}

/// hostel answers with no allotment, wrapped so the cache can tell "none" from "not fetched"
public struct HostelAllotment: Codable, Sendable, Hashable {
    public var hostel: HostelInfo?

    public init(_ hostel: HostelInfo?) {
        self.hostel = hostel
    }
}

public struct FeeHead: Codable, Sendable, Hashable {
    public var semester = 0
    public var academicYear = ""
    public var type = ""
    public var fee: Double = 0
    public var paid: Double = 0
    public var due: Double = 0
    public var waived: Double = 0
    public var refunded: Double = 0
    public var currency = "INR"

    public init(semester: Int = 0, type: String = "", fee: Double = 0, paid: Double = 0, due: Double = 0, waived: Double = 0, refunded: Double = 0) {
        self.semester = semester
        self.type = type
        self.fee = fee
        self.paid = paid
        self.due = due
        self.waived = waived
        self.refunded = refunded
    }

    init(json j: JSON) {
        semester = j.int("stynumber")
        academicYear = j.str("academicyear")
        type = j.str("stytypedesc")
        fee = j.dbl("feeamount")
        paid = j.dbl("receiveamount")
        due = j.dbl("dueamount")
        waived = j.dbl("waiveramount")
        refunded = j.dbl("refundamount")
        currency = j.str("currencycode", "INR")
    }
}

public struct FeeSummary: Codable, Sendable, Hashable {
    public var heads: [FeeHead] = []
    public var advance: Double = 0

    public init(heads: [FeeHead] = [], advance: Double = 0) {
        self.heads = heads
        self.advance = advance
    }

    init(json j: JSON) {
        heads = j["feeHeads"].array.map(FeeHead.init(json:))
        advance = j["advanceamount"].array.first?.dbl("amount") ?? 0
    }

    public var totalDue: Double { heads.reduce(0) { $0 + $1.due } }
}

public struct FeedbackEvent: Codable, Sendable, Hashable, Identifiable {
    public var id = ""
    public var description = ""
    public var code = ""

    public init(id: String = "", description: String = "", code: String = "") {
        self.id = id
        self.description = description
        self.code = code
    }

    init(json j: JSON) {
        id = j.str("eventid")
        description = j.str("eventdescription")
        code = j.str("feedbackcode")
    }
}
