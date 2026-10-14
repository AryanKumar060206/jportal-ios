import Foundation
import JPortalKit

/// attended / total with the target-driven verdicts jportal users know
struct Tally: Equatable {
    let attended: Int
    let total: Int

    static let zero = Tally(attended: 0, total: 0)

    var percent: Double { total == 0 ? 0 : Double(attended) * 100 / Double(total) }

    /// classes you can skip and still sit at or above [target]%
    func canMiss(_ target: Int) -> Int {
        if target <= 0 || total == 0 { return 0 }
        return max(0, Int(((100.0 * Double(attended) - Double(target * total)) / Double(target)).rounded(.down)))
    }

    /// classes in a row you need to climb back to [target]%. Int.max when it can't be done
    func mustAttend(_ target: Int) -> Int {
        if target >= 100 { return attended < total ? Int.max : 0 }
        return max(0, Int(((Double(target * total) - 100.0 * Double(attended)) / Double(100 - target)).rounded(.up)))
    }
}

enum DayMark { case present, absent, mixed }

enum AttendanceMath {
    /// the portal's rule: every present class over the regular ones, an extra can only help
    static func tally(_ classes: [ClassRecord]) -> Tally {
        Tally(attended: classes.count { $0.isPresent }, total: classes.count { !$0.isExtra })
    }

    /// per day: all present, all absent, or a split day
    static func calendar(_ classes: [ClassRecord]) -> [Day: DayMark] {
        Dictionary(grouping: classes.filter { $0.date != nil }, by: { $0.date! }).mapValues { day in
            let p = day.count { $0.isPresent }
            return p == day.count ? .present : p == 0 ? .absent : .mixed
        }
    }

    static func chronological(_ classes: [ClassRecord]) -> [ClassRecord] {
        classes.filter { $0.date != nil }.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.date != y.date { return x.date! < y.date! }
            let (sx, sy) = (x.start?.minutes ?? -1, y.start?.minutes ?? -1)
            return sx != sy ? sx < sy : a.offset < b.offset
        }.map(\.element)
    }

    /// running percentage after each class, oldest first, for the trend line
    static func trend(_ classes: [ClassRecord]) -> [(Day, Double)] {
        var present = 0
        var regular = 0
        return chronological(classes).compactMap { c in
            if c.isPresent { present += 1 }
            if !c.isExtra { regular += 1 }
            // an extra before any regular class has no bottom to divide by yet
            return regular == 0 ? nil : (c.date!, Double(present) * 100 / Double(regular))
        }
    }

    /// the last few classes, oldest first, true for present
    static func recent(_ classes: [ClassRecord], _ n: Int = 7) -> [Bool] {
        chronological(classes).suffix(n).map(\.isPresent)
    }
}
