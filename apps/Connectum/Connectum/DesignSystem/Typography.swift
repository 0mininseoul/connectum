import SwiftUI

// macOS system font (San Francisco) at native-feeling sizes.
enum Typography {
    static let title     = Font.system(size: 26, weight: .semibold)
    static let cardTitle = Font.system(size: 20, weight: .semibold)
    static let body      = Font.system(size: 16)
    static let caption   = Font.system(size: 14)
}
