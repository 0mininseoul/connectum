import SwiftUI

// The official Claude logomark (Assets/ClaudeLogo, a vector template image) in the
// brand terracotta. Use wherever the workspace's Claude connection is represented,
// instead of a generic ✨ symbol.
struct ClaudeMark: View {
    var size: CGFloat = 16
    var color: Color = Palette.claude

    var body: some View {
        Image("ClaudeLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityLabel("Claude")
    }
}

// A rounded, softly-tinted square that holds a small brand icon or symbol — the
// Raycast-style "icon chip" used across connection rows and cards for visual depth.
struct IconChip<Content: View>: View {
    var tint: Color
    var size: CGFloat = 34
    var corner: CGFloat = Radius.row
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: size, height: size)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).stroke(tint.opacity(0.22)))
    }
}

// A compact status capsule: a colored dot + label on a faint tint of the same hue.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.xxs + 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}
