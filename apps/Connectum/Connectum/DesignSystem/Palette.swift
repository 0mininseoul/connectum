import SwiftUI
import AppKit

enum Palette {
    // Dynamic surface ladder. Both themes stay translucent so window vibrancy
    // fills resized edges instead of exposing an opaque system background.
    static let canvas          = Color.adaptive(light: "F5F6F8", dark: "07080A", lightOpacity: 0.70, darkOpacity: 0.62)
    static let surface         = Color.adaptive(light: "FFFFFF", dark: "0D0D0D", lightOpacity: 0.58, darkOpacity: 0.58)
    static let surfaceElevated = Color.adaptive(light: "FFFFFF", dark: "101111", lightOpacity: 0.78, darkOpacity: 0.72)
    static let surfaceCard     = Color.adaptive(light: "FFFFFF", dark: "121212", lightOpacity: 0.72, darkOpacity: 0.66)
    static let inspectorSurface = Color.adaptive(light: "F6F7F9", dark: "0A0B0D")
    static let sidebarOverlay  = Color.adaptive(light: "FFFFFF", dark: "000000", lightOpacity: 0.58, darkOpacity: 0.54)
    // Text
    static let ink      = Color.adaptive(light: "17191C", dark: "F4F4F6")
    static let body     = Color.adaptive(light: "3B3F45", dark: "CDCDCD")
    static let muted    = Color.adaptive(light: "6B7280", dark: "9C9C9D")
    static let ash      = Color.adaptive(light: "A1A8B3", dark: "6A6B6C") // disabled
    // Border
    static let hairline = Color.adaptive(light: "D7DCE2", dark: "242728", lightOpacity: 0.88, darkOpacity: 0.84)
    // CTA
    static let ctaFill        = Color.adaptive(light: "111315", dark: "FFFFFF")
    static let ctaFillPressed = Color.adaptive(light: "2A2E33", dark: "E8E8E8")
    static let ctaText        = Color.adaptive(light: "FFFFFF", dark: "000000")
    // Semantic accents (status only — never chrome/CTA)
    static let accentBlue   = Color.adaptive(light: "0A84FF", dark: "57C1FF")
    static let accentRed    = Color.adaptive(light: "D92D20", dark: "FF6161")
    static let accentGreen  = Color.adaptive(light: "168A53", dark: "59D499")
    static let accentYellow = Color.adaptive(light: "B7791F", dark: "FFC533")
    // Third-party brand marks (used only for that provider's identity, not chrome).
    static let claude       = Color(hex: "D97757")  // Claude terracotta
}

extension Color {
    init(hex: String) {
        let rgb = RGBColor(hex: hex)
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    static func adaptive(light: String, dark: String, lightOpacity: Double = 1, darkOpacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = RGBColor(hex: isDark ? dark : light)
            return NSColor(
                srgbRed: CGFloat(rgb.r),
                green: CGFloat(rgb.g),
                blue: CGFloat(rgb.b),
                alpha: CGFloat(isDark ? darkOpacity : lightOpacity)
            )
        })
    }

    // Test helper: round-trip the resolved sRGB components to an uppercase hex string.
    var hexString: String {
        hexString(resolving: nil)
    }

    func hexString(appearance: NSAppearance.Name) -> String {
        hexString(resolving: appearance)
    }

    private func hexString(resolving appearanceName: NSAppearance.Name?) -> String {
        let ns = NSColor(self)
        let color: NSColor
        if let appearanceName, let appearance = NSAppearance(named: appearanceName) {
            var resolved = NSColor.black
            appearance.performAsCurrentDrawingAppearance {
                resolved = ns.usingColorSpace(.sRGB) ?? .black
            }
            color = resolved
        } else {
            color = ns.usingColorSpace(.sRGB) ?? .black
        }
        let r = Int(round(color.redComponent * 255))
        let g = Int(round(color.greenComponent * 255))
        let b = Int(round(color.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

private struct RGBColor {
    let r: Double
    let g: Double
    let b: Double

    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        r = Double((v >> 16) & 0xFF) / 255.0
        g = Double((v >> 8) & 0xFF) / 255.0
        b = Double(v & 0xFF) / 255.0
    }
}
