import AppKit
import SwiftUI

struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(_ hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }

    private init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Negative amounts move toward black, positive ones toward white.
    func mixed(_ amount: CGFloat) -> RGB {
        let target: CGFloat = amount < 0 ? 0 : 1
        let share = abs(amount)
        return RGB(red: red + (target - red) * share,
                   green: green + (target - green) * share,
                   blue: blue + (target - blue) * share)
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func color(opacity: Double = 1) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// The felt, wood and brass of the Node version's stylesheet.
enum Casino {
    static let felt = RGB(0x0F4434)
    static let feltHi = RGB(0x1A5C47)
    static let feltDeep = RGB(0x072A20)
    static let ink = RGB(0x0B1A12)
    static let ivory = RGB(0xF1E8D2)
    static let chalk = RGB(0xA6C0B2)
    static let brass = RGB(0xD8AD55)
    static let brassDim = RGB(0x8A6B2E)
    static let rojo = RGB(0xC41A32)
    static let rojoDeep = RGB(0x7D0F20)
    static let negro = RGB(0x161616)
    static let verde = RGB(0x1D7A4E)
    static let wood = RGB(0x5A3119)
    static let woodHi = RGB(0x8A5329)
    static let woodDeep = RGB(0x2A160A)
    static let track = RGB(0x0B1712)
    static let trackHi = RGB(0x23362C)
    static let ok = RGB(0x5FD39A)
    static let warn = RGB(0xE6A53A)
    static let err = RGB(0xFF7A7A)

    static let line = ivory.color(opacity: 0.14)
    static let lineStrong = ivory.color(opacity: 0.28)
    static let panel = Color(.sRGB, red: 3 / 255, green: 22 / 255, blue: 16 / 255, opacity: 0.55)

    /// Bodoni 72 Book Italic ships with macOS; the Node version reached for Bodoni Moda from Google Fonts.
    private static let displayFontName = "BodoniSvtyTwoITCTT-BookIta"

    static func display(_ size: CGFloat) -> Font {
        .custom(displayFontName, size: size)
    }

    static func displayFont(_ size: CGFloat) -> NSFont {
        NSFont(name: displayFontName, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func monoFont(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
