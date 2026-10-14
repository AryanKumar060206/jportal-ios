import Compression
import Foundation

indirect enum PdfObj {
    case num(Double)
    case name(String)
    case str([UInt8])
    case array([PdfObj])
    case dict([String: PdfObj])
    case ref(Int, Int)
    case bool(Bool)
    case null
    case keyword(String)
    case stream([String: PdfObj], [UInt8])

    var keyword: String? { if case .keyword(let k) = self { return k } else { return nil } }
    var number: Double? { if case .num(let v) = self { return v } else { return nil } }
    var nameValue: String? { if case .name(let v) = self { return v } else { return nil } }
    var dictValue: [String: PdfObj]? { if case .dict(let d) = self { return d } else { return nil } }
}

/**
 * just enough pdf to pull page content streams out of iText output: classic
 * xref-less object scan, no object streams, no encryption, flate only.
 */
final class PdfReader {
    private let data: [UInt8]
    private var offsets: [Int: Int] = [:]
    private var cache: [Int: PdfObj] = [:]

    private static let objRx = Rx(#"(\d+)\s+\d+\s+obj\b"#)
    private static let endstream = Array("endstream".utf8)

    init(_ bytes: [UInt8]) {
        data = bytes
        // latin-1 maps every byte to one utf-16 unit, so string offsets are byte offsets
        let text = String(bytes.map { Character(Unicode.Scalar($0)) })
        let ns = text as NSString
        for m in PdfReader.objRx.re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let start = m.range.location
            let before: UInt8 = start == 0 ? 0x0A : bytes[start - 1]
            if PdfReader.isWhitespaceLike(before) || before == UInt8(ascii: ">") || before == UInt8(ascii: ")") || before == UInt8(ascii: "]") {
                let num = Int(ns.substring(with: m.range(at: 1))) ?? -1
                // last definition wins, same as incremental updates
                offsets[num] = m.range.location + m.range.length
            }
        }
    }

    private static func isWhitespaceLike(_ c: UInt8) -> Bool {
        c == 0x20 || (0x09...0x0D).contains(c) || (0x1C...0x1F).contains(c) || c == 0xA0
    }

    func resolve(_ o: PdfObj?) -> PdfObj? {
        if case .ref(let n, _) = o { return obj(n) }
        return o
    }

    func obj(_ num: Int) -> PdfObj? {
        if let c = cache[num] { return c }
        guard let at = offsets[num] else { return nil }
        let lx = PdfLexer(data, at)
        guard let value = lx.readObject() else { return nil }
        var result = value
        if case .dict(let dict) = value, lx.peekKeyword() == "stream" {
            _ = lx.readKeyword()
            var start = lx.pos
            if start < data.count && data[start] == 0x0D { start += 1 }
            if start < data.count && data[start] == 0x0A { start += 1 }
            let declared = resolve(dict["Length"])?.number.map { Int($0) }
            let end: Int
            if let n = declared, n >= 0, start + n <= data.count, looksLikeEnd(start + n) {
                end = start + n
            } else {
                let i = indexOf(PdfReader.endstream, from: start)
                end = i < 0 ? data.count : trimEol(start, i)
            }
            result = .stream(dict, Array(data[start..<max(start, end)]))
        }
        cache[num] = result
        return result
    }

    private func looksLikeEnd(_ at: Int) -> Bool {
        var i = at
        while i < data.count && (data[i] == 0x0D || data[i] == 0x0A || data[i] == 0x20) { i += 1 }
        return startsWith(PdfReader.endstream, at: i)
    }

    private func trimEol(_ start: Int, _ end: Int) -> Int {
        var e = end
        if e > start && data[e - 1] == 0x0A { e -= 1 }
        if e > start && data[e - 1] == 0x0D { e -= 1 }
        return e
    }

    private func startsWith(_ needle: [UInt8], at: Int) -> Bool {
        if at + needle.count > data.count { return false }
        for k in needle.indices where data[at + k] != needle[k] { return false }
        return true
    }

    private func indexOf(_ needle: [UInt8], from: Int) -> Int {
        var i = from
        while i <= data.count - needle.count {
            if startsWith(needle, at: i) { return i }
            i += 1
        }
        return -1
    }

    func decode(_ dict: [String: PdfObj], _ raw: [UInt8]) throws -> [UInt8] {
        let filters: [String]
        switch resolve(dict["Filter"]) {
        case .name(let f): filters = [f]
        case .array(let items): filters = items.compactMap { resolve($0)?.nameValue }
        default: filters = []
        }
        var bytes = raw
        for f in filters {
            switch f {
            case "FlateDecode", "Fl": bytes = try PdfReader.inflate(bytes)
            default: throw MarksParseError(message: "unsupported filter \(f)")
            }
        }
        return bytes
    }

    /// page dicts in reading order
    func pages() throws -> [[String: PdfObj]] {
        var catalog: [String: PdfObj]?
        for n in offsets.keys.sorted() {
            if let d = obj(n)?.dictValue, d["Type"]?.nameValue == "Catalog" {
                catalog = d
                break
            }
        }
        guard let catalog else { throw MarksParseError(message: "no catalog") }
        var out: [[String: PdfObj]] = []
        func walk(_ node: [String: PdfObj], _ depth: Int) {
            if depth > 32 { return }
            if node["Type"]?.nameValue == "Pages" {
                if case .array(let kids) = resolve(node["Kids"]) {
                    for k in kids { if let d = resolve(k)?.dictValue { walk(d, depth + 1) } }
                }
            } else {
                out.append(node)
            }
        }
        if let root = resolve(catalog["Pages"])?.dictValue { walk(root, 0) }
        return out
    }

    func contents(_ page: [String: PdfObj]) throws -> [UInt8] {
        var parts: [([String: PdfObj], [UInt8])] = []
        switch resolve(page["Contents"]) {
        case .stream(let d, let raw): parts = [(d, raw)]
        case .array(let items):
            for i in items { if case .stream(let d, let raw) = resolve(i) { parts.append((d, raw)) } }
        default: break
        }
        var out: [UInt8] = []
        for (d, raw) in parts {
            out += try decode(d, raw)
            out.append(0x0A)
        }
        return out
    }

    /// zlib stream to bytes. truncated streams still carry usable text, keep what we got
    static func inflate(_ input: [UInt8]) throws -> [UInt8] {
        // apple's zlib codec is raw deflate, so step over the two byte header (and a preset dictionary id)
        var skip = 0
        if input.count >= 2, input[0] & 0x0F == 8, (UInt16(input[0]) << 8 | UInt16(input[1])) % 31 == 0 {
            skip = input[1] & 0x20 != 0 ? 6 : 2
        }
        guard input.count > skip else { throw MarksParseError(message: "bad flate stream") }
        let body = Array(input[skip...])

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw MarksParseError(message: "bad flate stream")
        }
        defer { compression_stream_destroy(stream) }

        var out: [UInt8] = []
        let bufSize = 8192
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        var failed = false
        body.withUnsafeBufferPointer { src in
            stream.pointee.src_ptr = src.baseAddress!
            stream.pointee.src_size = src.count
            while true {
                stream.pointee.dst_ptr = buf
                stream.pointee.dst_size = bufSize
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufSize - stream.pointee.dst_size
                if produced > 0 { out.append(contentsOf: UnsafeBufferPointer(start: buf, count: produced)) }
                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { failed = true; break }
                if produced == 0 && stream.pointee.src_size == 0 { break }
            }
        }
        if failed && out.isEmpty { throw MarksParseError(message: "bad flate stream") }
        return out
    }
}

/// tokenizer shared by object syntax and content streams
final class PdfLexer {
    private let d: [UInt8]
    var pos: Int

    init(_ d: [UInt8], _ pos: Int = 0) {
        self.d = d
        self.pos = pos
    }

    private func ch(_ i: Int? = nil) -> Int {
        let i = i ?? pos
        return i < d.count ? Int(d[i]) : -1
    }

    private func isWhite(_ c: Int) -> Bool { c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32 }

    private func isDelim(_ c: Int) -> Bool {
        c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25
    }

    private func skipSpace() {
        while pos < d.count {
            let c = ch()
            if isWhite(c) {
                pos += 1
            } else if c == 0x25 {
                while pos < d.count && ch() != 10 && ch() != 13 { pos += 1 }
            } else {
                break
            }
        }
    }

    func peekKeyword() -> String? {
        let save = pos
        let t = next()
        pos = save
        return t?.keyword
    }

    func readKeyword() -> String? { next()?.keyword }

    /// one full object, refs folded in
    func readObject() -> PdfObj? {
        guard let t = next() else { return nil }
        switch t {
        case .keyword("<<"): return readDict()
        case .keyword("["): return readArray()
        case .num(let v):
            let save = pos
            let g = next()
            let r = next()
            if let gv = g?.number, r?.keyword == "R" { return .ref(Int(v), Int(gv)) }
            pos = save
            return t
        default: return t
        }
    }

    private func readDict() -> PdfObj {
        var m: [String: PdfObj] = [:]
        while true {
            guard let k = readObject() else { break }
            if k.keyword == ">>" { break }
            guard let key = k.nameValue else { continue }
            guard let v = readObject() else { break }
            if v.keyword == ">>" { break }
            m[key] = v
        }
        return .dict(m)
    }

    private func readArray() -> PdfObj {
        var items: [PdfObj] = []
        while true {
            guard let o = readObject() else { break }
            if o.keyword == "]" { break }
            items.append(o)
        }
        return .array(items)
    }

    /// raw token, dict/array brackets come back as keywords
    func next() -> PdfObj? {
        skipSpace()
        if pos >= d.count { return nil }
        let c = ch()
        if c == 0x2F { // /
            pos += 1
            var s = ""
            while pos < d.count && !isWhite(ch()) && !isDelim(ch()) {
                if ch() == 0x23 && pos + 2 < d.count, let v = UInt8(String(bytes: [d[pos + 1], d[pos + 2]], encoding: .isoLatin1) ?? "", radix: 16) {
                    s.unicodeScalars.append(Unicode.Scalar(v))
                    pos += 3
                    continue
                }
                s.unicodeScalars.append(Unicode.Scalar(UInt8(ch())))
                pos += 1
            }
            return .name(s)
        }
        if c == 0x28 { return .str(literal()) }
        if c == 0x3C && ch(pos + 1) == 0x3C { pos += 2; return .keyword("<<") }
        if c == 0x3E && ch(pos + 1) == 0x3E { pos += 2; return .keyword(">>") }
        if c == 0x3C { return .str(hex()) }
        if c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D {
            pos += 1
            return .keyword(String(UnicodeScalar(UInt8(c))))
        }
        if c == 0x2B || c == 0x2D || c == 0x2E || (0x30...0x39).contains(c) { return number() }
        let start = pos
        while pos < d.count && !isWhite(ch()) && !isDelim(ch()) { pos += 1 }
        if pos == start { pos += 1 }
        let word = String(decoding: d[start..<pos], as: Unicode.ASCII.self)
        switch word {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: return .keyword(String(d[start..<pos].map { Character(Unicode.Scalar($0)) }))
        }
    }

    private func number() -> PdfObj {
        let start = pos
        pos += 1
        while pos < d.count && ((0x30...0x39).contains(ch()) || ch() == 0x2E) { pos += 1 }
        let s = String(decoding: d[start..<pos], as: Unicode.ASCII.self)
        // java's parseDouble takes "+5" and "5.", match it
        guard s.contains(where: \.isNumber) else { return .keyword(s) }
        var t = s
        if t.hasSuffix(".") { t += "0" }
        if t.hasPrefix("+") { t.removeFirst() }
        if t.hasPrefix(".") || t.hasPrefix("-.") { t = t.replacingOccurrences(of: ".", with: "0.") }
        if let v = Double(t), t.filter({ $0 == "." }).count <= 1 { return .num(v) }
        return .keyword(s)
    }

    private func literal() -> [UInt8] {
        pos += 1
        var out: [UInt8] = []
        var depth = 1
        while pos < d.count {
            let c = ch()
            pos += 1
            switch c {
            case 0x28:
                depth += 1
                out.append(UInt8(c))
            case 0x29:
                depth -= 1
                if depth == 0 { return out }
                out.append(UInt8(c))
            case 0x5C:
                let e = ch()
                pos += 1
                switch e {
                case 0x6E: out.append(10)
                case 0x72: out.append(13)
                case 0x74: out.append(9)
                case 0x62: out.append(8)
                case 0x66: out.append(12)
                case 13: if ch() == 10 { pos += 1 }
                case 10: break
                case 0x30...0x37:
                    var v = e - 0x30
                    for _ in 0..<2 where (0x30...0x37).contains(ch()) {
                        v = v * 8 + (ch() - 0x30)
                        pos += 1
                    }
                    out.append(UInt8(v & 0xFF))
                case -1: break
                default: out.append(UInt8(e))
                }
            default:
                out.append(UInt8(c))
            }
        }
        return out
    }

    private func hex() -> [UInt8] {
        pos += 1
        var digits: [UInt8] = []
        while pos < d.count && ch() != 0x3E {
            let c = UInt8(ch())
            if (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c) { digits.append(c) }
            pos += 1
        }
        pos += 1
        if digits.count % 2 == 1 { digits.append(0x30) }
        var out: [UInt8] = []
        var i = 0
        while i < digits.count {
            out.append(UInt8(String(bytes: digits[i..<i + 2], encoding: .ascii) ?? "", radix: 16) ?? 0)
            i += 2
        }
        return out
    }
}
