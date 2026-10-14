import SwiftUI
import UIKit

extension Color {
    /// one color per appearance, resolved by the trait collection
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/**
 * jportal's palette: charcoal slate surfaces, white type, colour only where it
 * means something. sgpa green, cgpa blue, grade letters and attendance verdicts.
 */
enum JP {
    static let background = Color.dynamic(0xF8F9FD, 0x111317)
    static let card = Color.dynamic(0xF0F2F7, 0x1D2126)
    static let cardHigh = Color.dynamic(0xE5E8F0, 0x2A3039)
    static let hero = Color.dynamic(0xDCE4FC, 0x232E45)
    static let onHero = Color.dynamic(0x1E3170, 0xE3EAFF)
    static let primary = Color.dynamic(0x2563EB, 0xA3C9FE)
    static let ring = Color.dynamic(0x4A5F96, 0xA9C3F5)
    static let chip = Color.dynamic(0xDDE3F3, 0x2E3746)
    static let onChip = Color.dynamic(0x1F2937, 0xE6E7E9)
    static let tertiary = Color.dynamic(0x8A4F7D, 0xE7B6DA)
    static let tertiaryContainer = Color.dynamic(0xF6DCEF, 0x5A3D58)
    static let onTertiaryContainer = Color.dynamic(0x3A0A33, 0xFAD8F0)
    static let good = Color.dynamic(0x15803D, 0x4ADE80)
    static let warn = Color.dynamic(0xA16207, 0xEAB308)
    static let bad = Color.dynamic(0xDC2626, 0xF87171)
    static let sgpa = Color.dynamic(0x16A34A, 0x4ADE80)
    static let cgpa = Color.dynamic(0x2563EB, 0x60A5FA)
    static let credits = cgpa
    static let outline = Color.dynamic(0xD1D5DB, 0x2F3540)

    // tailwind 400/500/600 on dark like jportal, two steps darker on light so letters hold contrast on white
    private static let gradeColors: [String: Color] = [
        "A+": .dynamic(0x16A34A, 0x4ADE80), "A": .dynamic(0x15803D, 0x22C55E), "B+": .dynamic(0xCA8A04, 0xFACC15),
        "B": .dynamic(0xA16207, 0xEAB308), "C+": .dynamic(0x854D0E, 0xCA8A04), "C": .dynamic(0xC2410C, 0xF97316),
        "D": .dynamic(0x9A3412, 0xEA580C), "F": .dynamic(0xDC2626, 0xEF4444), "I": .dynamic(0xDC2626, 0xEF4444),
        "X": .dynamic(0xDC2626, 0xEF4444),
    ]

    static func grade(_ letter: String) -> Color { gradeColors[letter.trimmed.uppercased()] ?? .secondary }

    // jportal's marks bands: green from 80%, yellow from 60%, orange from 40%, red below
    private static let marksBars: [Color] = [.dynamic(0x16A249, 0x00C950), .dynamic(0xF5C73D, 0xF0B000), .dynamic(0xF58A3D, 0xFF6A00), .dynamic(0xEF4444, 0xEF4444)]
    private static let marksInks: [Color] = [.dynamic(0x15803D, 0x00C950), .dynamic(0xA16207, 0xF0B000), .dynamic(0xC2410C, 0xFF6A00), .dynamic(0xDC2626, 0xEF4444)]

    private static func band(_ f: Double) -> Int { f >= 0.8 ? 0 : f >= 0.6 ? 1 : f >= 0.4 ? 2 : 3 }
    static func marks(_ fraction: Double) -> Color { marksBars[band(fraction)] }
    /// marks for text, darker on light where the bar's yellow can't be read
    static func marksInk(_ fraction: Double) -> Color { marksInks[band(fraction)] }
}

extension Font {
    /// the big numbers: percentages, gpas, countdowns
    static let number = Font.system(size: 44, weight: .bold, design: .rounded)
}

extension View {
    func card(_ color: Color = JP.card, radius: CGFloat = 22) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
