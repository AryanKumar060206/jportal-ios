import Charts
import JPortalKit
import SwiftUI

/**
 * sgpa and cgpa per semester. future semesters take a drag: tap or slide on
 * one to set its sgpa, and the cgpa line follows. dashed segments are what-ifs.
 */
struct GpaChart: View {
    let points: [GpaPoint]
    let future: [Int]
    let maxSemester: Int
    let onProject: (Int, Double) -> Void

    private var low: Double {
        let m = points.flatMap { [$0.sgpa, $0.cgpa] }.filter { $0 > 0 }.min() ?? 5
        return max(0, min(5, (m - 1).rounded(.down)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ForEach(series, id: \.name) { s in
                    Label { Text(s.name) } icon: { Circle().fill(s.color).frame(width: 8, height: 8) }
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series, id: \.name) { s in
                // a line style holds for a whole series, so the what-if part is its own dashed series off the last real point
                ForEach(s.real) { p in
                    LineMark(x: .value("Semester", p.semester), y: .value(s.name, s.value(p)), series: .value("Series", s.name))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)
                }
                ForEach(s.whatIf) { p in
                    LineMark(x: .value("Semester", p.semester), y: .value(s.name, s.value(p)), series: .value("Series", "\(s.name) what-if"))
                        .foregroundStyle(s.color.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                        .interpolationMethod(.monotone)
                }
                ForEach(s.points) { p in
                    PointMark(x: .value("Semester", p.semester), y: .value(s.name, s.value(p)))
                        .foregroundStyle(s.color)
                        .symbolSize(p.projected ? 110 : 40)
                        .opacity(p.projected ? 0.55 : 1)
                }
            }
        }
        .chartYScale(domain: low...10)
        .chartXScale(domain: 0.6...(Double(maxSemester) + 0.4))
        .chartXAxis {
            AxisMarks(values: Array(1...max(1, maxSemester))) { v in
                AxisValueLabel { Text("S\(v.as(Int.self) ?? 0)") }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        guard let plot = proxy.plotFrame else { return }
                        let origin = geo[plot].origin
                        let x = g.location.x - origin.x
                        let y = g.location.y - origin.y
                        guard let sem: Double = proxy.value(atX: x), let v: Double = proxy.value(atY: y) else { return }
                        let s = Int(sem.rounded())
                        guard future.contains(s) else { return }
                        onProject(s, (min(10, max(0, v)) * 10).rounded() / 10)
                    })
            }
        }
        .frame(height: 240)
        .accessibilityLabel("SGPA and CGPA by semester")
    }

    private struct Series {
        let name: String
        let color: Color
        let points: [GpaPoint]
        let value: (GpaPoint) -> Double

        var real: [GpaPoint] { points.filter { !$0.projected } }

        /// the last real point and everything projected after it, empty when nothing is projected
        var whatIf: [GpaPoint] {
            let projected = points.filter(\.projected)
            guard !projected.isEmpty else { return [] }
            return (real.last.map { [$0] } ?? []) + projected
        }
    }

    private var series: [Series] {
        [
            Series(name: "SGPA", color: JP.sgpa, points: points, value: \.sgpa),
            Series(name: "CGPA", color: JP.cgpa, points: points.filter { $0.cgpa > 0 }, value: \.cgpa),
        ]
    }
}

/// running attendance percentage, class by class, against the target line
struct TrendChart: View {
    let values: [Double]
    let target: Int

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("Class", i), yStart: .value("Floor", lowest), yEnd: .value("Percent", v))
                    .foregroundStyle(LinearGradient(colors: [JP.ring.opacity(0.25), JP.ring.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Class", i), y: .value("Percent", v))
                    .foregroundStyle(JP.ring)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Target", target))
                .foregroundStyle(JP.bad.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("\(target)%").font(.caption2).foregroundStyle(JP.bad)
                }
        }
        .chartYScale(domain: lowest...100)
        .chartXAxis(.hidden)
        .frame(height: 160)
        .accessibilityLabel("Attendance over the semester, now \(Int(values.last ?? 0)) percent")
    }

    private var lowest: Double { max(0, min(Double(target) - 10, (values.min() ?? 0) - 5).rounded(.down)) }
}

/// a month grid: green for a day you were there, red for one you weren't, amber for a split day
struct AttendanceCalendar: View {
    let marks: [Day: DayMark]
    @Binding var selected: Day?
    @State private var month: Day

    init(marks: [Day: DayMark], selected: Binding<Day?>) {
        self.marks = marks
        _selected = selected
        _month = State(initialValue: (marks.keys.max() ?? Day.today()).firstOfMonth)
    }

    private var first: Day { (marks.keys.min() ?? month).firstOfMonth }
    private var last: Day { (marks.keys.max() ?? month).firstOfMonth }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted("MMMMyyyy")).font(.headline)
                Spacer()
                Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(month <= first)
                    .accessibilityLabel("Previous month")
                Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(month >= last)
                    .padding(.leading, 20)
                    .accessibilityLabel("Next month")
            }
            .padding(.horizontal, 8)
            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<month.weekdayFromMonday, id: \.self) { _ in Color.clear.frame(height: 38) }
                ForEach(1...month.daysInMonth, id: \.self) { n in
                    let d = Day(year: month.year, month: month.month, day: n)
                    cell(d)
                }
            }
        }
        .padding(16)
        .card()
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func cell(_ d: Day) -> some View {
        let mark = marks[d]
        let fill: Color = switch mark {
        case .present: JP.good.opacity(0.2)
        case .absent: JP.bad.opacity(0.2)
        case .mixed: JP.warn.opacity(0.22)
        case nil: .clear
        }
        let isSelected = selected == d
        Button {
            selected = isSelected ? nil : d
        } label: {
            Text("\(d.day)")
                .font(.subheadline.weight(mark == nil ? .regular : .semibold))
                .foregroundStyle(mark == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(isSelected ? JP.primary : (d == Day.today() ? JP.outline : .clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(d.formatted("EEEEdMMMM") + (mark.map { m in m == .present ? ", present" : m == .absent ? ", absent" : ", partly present" } ?? ""))
    }
}
