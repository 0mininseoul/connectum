import SwiftUI
import AppKit

enum Palette {
    // Surface ladder (dark-only). Depth comes from these steps, never shadows.
    static let canvas          = Color(hex: "07080A")
    static let surface         = Color(hex: "0D0D0D")
    static let surfaceElevated = Color(hex: "101111")
    static let surfaceCard     = Color(hex: "121212")
    // Text
    static let ink      = Color(hex: "F4F4F6")
    static let body     = Color(hex: "CDCDCD")
    static let muted    = Color(hex: "9C9C9D")
    static let ash      = Color(hex: "6A6B6C") // disabled
    // Border
    static let hairline = Color(hex: "242728")
    // CTA
    static let ctaFill        = Color.white
    static let ctaFillPressed = Color(hex: "E8E8E8")
    static let ctaText        = Color.black
    // Semantic accents (status only — never chrome/CTA)
    static let accentBlue   = Color(hex: "57C1FF")
    static let accentRed    = Color(hex: "FF6161")
    static let accentGreen  = Color(hex: "59D499")
    static let accentYellow = Color(hex: "FFC533")
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    // Test helper: round-trip the resolved sRGB components to an uppercase hex string.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
