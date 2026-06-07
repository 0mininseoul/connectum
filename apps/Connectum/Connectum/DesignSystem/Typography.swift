import SwiftUI

// Paperlogy type scale (weights 400/500/600). Falls back to system if the
// bundled font is unavailable so the app still renders during early setup.
enum Typography {
    static func paperlogy(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:   name = "Paperlogy-Medium"
        case .semibold: name = "Paperlogy-SemiBold"
        default:        name = "Paperlogy-Regular"
        }
        return Font.custom(name, size: size)
    }
    static let cardTitle = paperlogy(24, .medium)
    static let body      = paperlogy(16, .regular)
    static let caption   = paperlogy(12, .regular)
}
