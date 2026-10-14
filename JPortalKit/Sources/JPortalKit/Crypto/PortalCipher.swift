import CommonCrypto
import Foundation
import Security

let IST = TimeZone(secondsFromGMT: 5 * 3600 + 30 * 60)!

/**
 * the 7 char date fingerprint baked into every key and LocalName header:
 * d0 m0 y0 weekday d1 m1 y1, weekday js style (sunday = 0), always in IST.
 */
public func dateSeq(_ at: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = IST
    let c = cal.dateComponents([.year, .month, .day, .weekday], from: at)
    let dd = Array(String(format: "%02d", c.day!))
    let mm = Array(String(format: "%02d", c.month!))
    let yy = Array(String(format: "%02d", c.year! % 100))
    let weekday = c.weekday! - 1
    return "\(dd[0])\(mm[0])\(yy[0])\(weekday)\(dd[1])\(mm[1])\(yy[1])"
}

/// aes-128-cbc with a key that rotates daily. the iv never changes, yes really.
public enum PortalCipher {
    private static let iv = Array("dcek9wb8frty1pnm".utf8)

    static func key(_ at: Date) -> [UInt8] { Array("qa8y\(dateSeq(at))ty1pn".utf8) }

    enum Failure: Error { case crypt(Int32), base64 }

    private static func crypt(_ op: CCOperation, _ input: [UInt8], _ at: Date) throws -> [UInt8] {
        let key = key(at)
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(
            op, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
            key, key.count, iv, input, input.count, &out, out.count, &moved
        )
        guard status == kCCSuccess else { throw Failure.crypt(status) }
        return Array(out.prefix(moved))
    }

    public static func encrypt(_ plain: String, at: Date) -> String {
        // aes-cbc over a fixed size key never fails for valid input
        let bytes = (try? crypt(CCOperation(kCCEncrypt), Array(plain.utf8), at)) ?? []
        return Data(bytes).base64EncodedString()
    }

    public static func decrypt(_ encoded: String, at: Date) throws -> String {
        guard let data = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw Failure.base64 }
        let bytes = try crypt(CCOperation(kCCDecrypt), Array(data), at)
        return String(decoding: bytes, as: UTF8.self)
    }

    private static let alnum = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

    private static func noise(_ n: Int) -> String {
        var g = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in alnum[Int.random(in: 0..<alnum.count, using: &g)] })
    }

    /// without it the server answers 200 with an empty body
    public static func localName(_ at: Date) -> String {
        encrypt(noise(4) + dateSeq(at) + noise(5), at: at)
    }
}
