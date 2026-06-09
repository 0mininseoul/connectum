import SwiftUI
import AppKit

private func windowBackdropColor(for colorScheme: ColorScheme) -> NSColor {
    switch colorScheme {
    case .dark:
        return NSColor.black.withAlphaComponent(0.62)
    case .light:
        return NSColor.white.withAlphaComponent(0.70)
    @unknown default:
        return NSColor.black.withAlphaComponent(0.62)
    }
}

private func windowBackdropOverlay(for colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.black.opacity(0.62)
    case .light:
        return Color.white.opacity(0.70)
    @unknown default:
        return Color.black.opacity(0.62)
    }
}

// Apple-style vibrancy. Backed by NSVisualEffectView so the desktop blurs through
// the (non-opaque) window instead of the UI being a flat black slab.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.state = .active
    }
}

// Makes the hosting NSWindow non-opaque so behind-window vibrancy shows through.
struct TranslucentWindow: NSViewRepresentable {
    var colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { applyBackdrop(to: v.window, colorScheme: colorScheme) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { applyBackdrop(to: nsView.window, colorScheme: colorScheme) }
    }

    private func applyBackdrop(to window: NSWindow?, colorScheme: ColorScheme) {
        guard let window else { return }
        let backdrop = windowBackdropColor(for: colorScheme)
        window.isOpaque = false
        window.backgroundColor = backdrop
        window.titlebarAppearsTransparent = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = backdrop.cgColor
    }
}

extension View {
    // Bottom-most translucent backdrop for a window's root.
    func vibrantBackground(_ material: NSVisualEffectView.Material = .underWindowBackground) -> some View {
        modifier(VibrantBackgroundModifier(material: material))
    }
}

private struct VibrantBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let material: NSVisualEffectView.Material

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VisualEffectView(material: material)
                    windowBackdropOverlay(for: colorScheme)
                }
                .ignoresSafeArea()
            }
            .background(TranslucentWindow(colorScheme: colorScheme))
    }
}
