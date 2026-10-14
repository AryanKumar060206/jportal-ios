import Foundation

/// a run of text drawn from one text position, in page space
struct TextRun {
    var x: Double
    var y: Double
    var text: String
    var size: Double
}

/// a stroked or filled rectangle, normalized so w and h are positive
struct PdfRect: Hashable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var right: Double { x + w }
    var top: Double { y + h }
    var area: Double { w * h }

    func contains(_ px: Double, _ py: Double, slack: Double = 0.5) -> Bool {
        px >= x - slack && px <= right + slack && py >= y - slack && py <= top + slack
    }
}

struct PageContent {
    let runs: [TextRun]
    let rects: [PdfRect]
}

/**
 * walks a content stream keeping just the ctm, text matrices and rectangles.
 * fonts are all standard 14 with WinAnsi here so glyph widths never matter:
 * runs are placed by their start point and cells come from the drawn rects.
 */
enum ContentScanner {
    struct Matrix {
        let a, b, c, d, e, f: Double

        func times(_ m: Matrix) -> Matrix {
            Matrix(
                a: a * m.a + b * m.c, b: a * m.b + b * m.d,
                c: c * m.a + d * m.c, d: c * m.b + d * m.d,
                e: e * m.a + f * m.c + m.e, f: e * m.b + f * m.d + m.f
            )
        }

        func apply(_ x: Double, _ y: Double) -> (Double, Double) { (a * x + c * y + e, b * x + d * y + f) }

        static let identity = Matrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)
        static func translate(_ x: Double, _ y: Double) -> Matrix { Matrix(a: 1, b: 0, c: 0, d: 1, e: x, f: y) }
    }

    static func scan(_ content: [UInt8]) -> PageContent {
        var runs: [TextRun] = []
        var rects: [PdfRect] = []
        let lx = PdfLexer(content)
        var operands: [PdfObj] = []
        var stack: [Matrix] = []
        var ctm = Matrix.identity
        var tm = Matrix.identity
        var tlm = Matrix.identity
        var leading = 0.0
        var fontSize = 0.0
        // set when a positioning op ran, so back to back Tj calls glue together
        var fresh = true

        func num(_ i: Int) -> Double { i < operands.count ? operands[i].number ?? 0 : 0 }

        func moveLine(_ tx: Double, _ ty: Double) {
            tlm = Matrix.translate(tx, ty).times(tlm)
            tm = tlm
            fresh = true
        }

        func show(_ bytes: [UInt8]) {
            let s = WinAnsi.decode(bytes)
            if !fresh, !runs.isEmpty {
                runs[runs.count - 1].text += s
            } else {
                let (x, y) = tm.times(ctm).apply(0, 0)
                runs.append(TextRun(x: x, y: y, text: s, size: fontSize * abs(tm.d)))
            }
            fresh = false
        }

        func lastString() -> [UInt8]? {
            if case .str(let b) = operands.last { return b }
            return nil
        }

        while let t = lx.next() {
            guard case .keyword(let op) = t else {
                operands.append(t)
                continue
            }
            switch op {
            case "[":
                var items: [PdfObj] = []
                while let x = lx.next() {
                    if x.keyword == "]" { break }
                    items.append(x)
                }
                operands.append(.array(items))
                continue
            case "<<": // inline dict operand (BDC props), not needed
                var depth = 1
                while depth > 0, let x = lx.next() {
                    if x.keyword == "<<" { depth += 1 }
                    if x.keyword == ">>" { depth -= 1 }
                }
                operands.append(.null)
                continue
            case "q": stack.append(ctm)
            case "Q": ctm = stack.popLast() ?? .identity
            case "cm": ctm = Matrix(a: num(0), b: num(1), c: num(2), d: num(3), e: num(4), f: num(5)).times(ctm)
            case "re":
                let (x0, y0) = ctm.apply(num(0), num(1))
                let (x1, y1) = ctm.apply(num(0) + num(2), num(1) + num(3))
                rects.append(PdfRect(x: min(x0, x1), y: min(y0, y1), w: abs(x1 - x0), h: abs(y1 - y0)))
            case "BT":
                tm = .identity
                tlm = .identity
                fresh = true
            case "ET": fresh = true
            case "Tf": fontSize = num(1)
            case "TL": leading = num(0)
            case "Tm":
                tlm = Matrix(a: num(0), b: num(1), c: num(2), d: num(3), e: num(4), f: num(5))
                tm = tlm
                fresh = true
            case "Td": moveLine(num(0), num(1))
            case "TD":
                leading = -num(1)
                moveLine(num(0), num(1))
            case "T*": moveLine(0, -leading)
            case "Tj": if let b = lastString() { show(b) }
            case "'", "\"":
                moveLine(0, -leading)
                if let b = lastString() { show(b) }
            case "TJ":
                if case .array(let items) = operands.last {
                    var out: [UInt8] = []
                    for item in items {
                        switch item {
                        case .str(let b): out += b
                        // a big negative kern is how some writers fake a space
                        case .num(let v): if v < -200 { out.append(0x20) }
                        default: break
                        }
                    }
                    show(out)
                }
            case "BI": skipInlineImage(lx)
            default: break
            }
            operands.removeAll(keepingCapacity: true)
        }
        return PageContent(runs: runs, rects: rects)
    }

    private static func skipInlineImage(_ lx: PdfLexer) {
        while let t = lx.next() { if t.keyword == "ID" { break } }
        while let t = lx.next() { if t.keyword == "EI" { return } }
    }
}

enum WinAnsi {
    // 0x80..0x9f, the only range that differs from latin-1
    private static let high: [Character] = [
        "€", "\u{FFFD}", "‚", "ƒ", "„", "…", "†", "‡",
        "ˆ", "‰", "Š", "‹", "Œ", "\u{FFFD}", "Ž", "\u{FFFD}",
        "\u{FFFD}", "‘", "’", "“", "”", "•", "–", "—",
        "˜", "™", "š", "›", "œ", "\u{FFFD}", "ž", "Ÿ",
    ]

    static func decode(_ bytes: [UInt8]) -> String {
        var s = ""
        s.reserveCapacity(bytes.count)
        for b in bytes {
            switch b {
            case 0x80...0x9F: s.append(high[Int(b) - 0x80])
            case 0xA0: s.append(" ")
            default: s.unicodeScalars.append(Unicode.Scalar(b))
            }
        }
        return s
    }
}
