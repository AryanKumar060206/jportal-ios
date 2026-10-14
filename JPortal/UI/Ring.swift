import SwiftUI

/**
 * jportal's attendance ring. the arc is wavy while you're safely above target
 * and flattens out once you're below it, so the shape says it before the
 * number does. with [shortfall], a dot on the track marks the target you're short of.
 */
struct AttendanceRing<Content: View>: View {
    let percent: Double
    let target: Int
    var size: CGFloat = 56
    var stroke: CGFloat = 6
    var shortfall = false
    @ViewBuilder var content: () -> Content

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var safe: Bool { percent >= Double(target) }

    private var color: Color {
        if safe { return JP.ring }
        return percent >= Double(target - 10) ? JP.warn : JP.bad
    }

    var body: some View {
        ZStack {
            RingShape(fraction: shown / 100, target: Double(target) / 100, amplitude: safe ? 1 : 0, stroke: stroke, part: .track)
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            RingShape(fraction: shown / 100, target: Double(target) / 100, amplitude: safe ? 1 : 0, stroke: stroke, part: .arc)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            if shortfall && !safe && shown > 0.1 {
                RingShape(fraction: shown / 100, target: Double(target) / 100, amplitude: 0, stroke: stroke, part: .dot)
                    .fill(JP.bad)
            }
            content()
                .minimumScaleFactor(0.5)
                .padding(stroke + 4)
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { shown = percent } else { withAnimation(.spring(duration: 0.9, bounce: 0.15)) { shown = percent } }
        }
        .onChange(of: percent) { _, v in withAnimation(.easeInOut(duration: 0.6)) { shown = v } }
    }
}

extension AttendanceRing where Content == EmptyView {
    init(percent: Double, target: Int, size: CGFloat = 56, stroke: CGFloat = 6, shortfall: Bool = false) {
        self.init(percent: percent, target: target, size: size, stroke: stroke, shortfall: shortfall) { EmptyView() }
    }
}

private nonisolated struct RingShape: Shape {
    enum Part { case track, arc, dot }

    var fraction: Double
    let target: Double
    var amplitude: Double
    let stroke: CGFloat
    let part: Part

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(fraction, amplitude) }
        set { fraction = newValue.first; amplitude = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let waveAmp = stroke * 0.24 * amplitude
        let r = min(rect.width, rect.height) / 2 - stroke / 2 - waveAmp
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let f = min(max(fraction, 0), 1)
        // gap between arc ends and the track, scaled to stroke so it reads at every size
        let gap = min(stroke * 1.6 / r, 0.5)
        let start = -Double.pi / 2
        let sweep = f * 2 * .pi
        var p = Path()
        switch part {
        case .track:
            guard f < 0.999 else { return p }
            let s = start + sweep + (f > 0.001 ? gap : 0)
            let e = start + 2 * .pi - (f > 0.001 ? gap : 0)
            if e > s { p.addArc(center: c, radius: r, startAngle: .radians(s), endAngle: .radians(e), clockwise: false) }
        case .arc:
            guard f > 0.001 else { return p }
            // sampled wavy arc; wave count grows with the ring so bumps keep a constant size
            let waves = max(8, (2 * .pi * r) / (stroke * 4.6))
            let steps = max(24, Int(sweep * r / 2))
            for i in 0...steps {
                let a = start + sweep * Double(i) / Double(steps)
                let rr = r + waveAmp * sin(waves * (a - start))
                let pt = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        case .dot:
            let t = start + target * 2 * .pi
            guard t > start + sweep else { return p }
            let d = stroke * 0.3
            p.addEllipse(in: CGRect(x: c.x + r * cos(t) - d, y: c.y + r * sin(t) - d, width: d * 2, height: d * 2))
        }
        return p
    }
}

/// the jportal frog blepping a j, drawn from the android launcher vector (108 unit viewport)
struct FrogMark: View {
    var size: CGFloat = 120

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 108
            ctx.scaleBy(x: k, y: k)
            let green = Color(hex: 0x72CC6A), ink = Color(hex: 0x0E2214)
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 108, height: 108)), with: .color(Color(hex: 0x12301B)))
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)) }
            var head = Path(ellipseIn: CGRect(x: 25, y: 40.5, width: 58, height: 35))
            head.addPath(circle(40, 38, 12.5))
            head.addPath(circle(68, 38, 12.5))
            ctx.fill(head, with: .color(green))
            for x in [40.0, 68.0] {
                ctx.fill(circle(x, 38, 8.6), with: .color(.white))
                ctx.fill(circle(x + 0.8, 39.4, 4.9), with: .color(ink))
                ctx.fill(circle(x + 2.6, 37.4, 1.6), with: .color(.white))
            }
            // the tongue only exists below the lip, so it grows out of the mouth
            var clip = Path()
            clip.move(to: CGPoint(x: 0, y: 37))
            clip.addLine(to: CGPoint(x: 33.5, y: 58.5))
            clip.addQuadCurve(to: CGPoint(x: 74.5, y: 58.5), control: CGPoint(x: 54, y: 69.5))
            clip.addLine(to: CGPoint(x: 108, y: 37))
            clip.addLine(to: CGPoint(x: 108, y: 108))
            clip.addLine(to: CGPoint(x: 0, y: 108))
            clip.closeSubpath()
            ctx.drawLayer { tongue in
                tongue.clip(to: clip)
                var mouth = Path()
                mouth.move(to: CGPoint(x: 49, y: 62.6))
                mouth.addQuadCurve(to: CGPoint(x: 67.5, y: 61.2), control: CGPoint(x: 59, y: 66.4))
                mouth.addQuadCurve(to: CGPoint(x: 49, y: 62.6), control: CGPoint(x: 61, y: 71))
                tongue.fill(mouth, with: .color(ink))
                var j = Path()
                j.move(to: CGPoint(x: 60, y: 61))
                j.addLine(to: CGPoint(x: 60, y: 75))
                j.addArc(center: CGPoint(x: 53.2, y: 75), radius: 6.8, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                tongue.stroke(j, with: .color(ink), style: StrokeStyle(lineWidth: 10.4, lineCap: .round, lineJoin: .round))
                tongue.stroke(j, with: .color(Color(hex: 0xFF7C93)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                var shine = Path()
                shine.move(to: CGPoint(x: 62.3, y: 68.5))
                shine.addLine(to: CGPoint(x: 62.3, y: 72.8))
                tongue.stroke(shine, with: .color(Color(hex: 0xFFB8C5).opacity(0.8)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
            var lip = Path()
            lip.move(to: CGPoint(x: 33.5, y: 58.5))
            lip.addQuadCurve(to: CGPoint(x: 74.5, y: 58.5), control: CGPoint(x: 54, y: 69.5))
            ctx.stroke(lip, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
