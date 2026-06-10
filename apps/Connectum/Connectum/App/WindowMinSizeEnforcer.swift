import SwiftUI
import AppKit

struct WindowMinSizeEnforcer: NSViewRepresentable {
    let minSize: CGSize

    func makeNSView(context: Context) -> WindowMinSizeView {
        WindowMinSizeView()
    }

    func updateNSView(_ nsView: WindowMinSizeView, context: Context) {
        nsView.apply(minSize: minSize)
    }
}

final class WindowMinSizeView: NSView {
    private var requestedMinSize: CGSize = .zero

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func apply(minSize: CGSize) {
        requestedMinSize = minSize
        enforce()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResize(_:)),
                name: NSWindow.didResizeNotification,
                object: window
            )
        }
        enforce()
    }

    @objc private func windowDidResize(_ notification: Notification) {
        enforce()
    }

    private func enforce() {
        let minSize = requestedMinSize
        guard minSize.width > 0, minSize.height > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            let contentTarget = NSSize(width: minSize.width, height: minSize.height)
            let frameTarget = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentTarget)).size
            window.minSize = frameTarget
            window.contentMinSize = contentTarget

            var frame = window.frame
            let oldHeight = frame.height
            frame.size.width = max(frame.width, frameTarget.width)
            frame.size.height = max(frame.height, frameTarget.height)
            if frame.height != oldHeight {
                frame.origin.y -= frame.height - oldHeight
            }

            // Safety net: keep the window within the visible screen. The AI chat
            // is now a trailing overlay (it can't grow the window), but capping
            // maxSize and clamping the frame guards against any other content
            // driving the window past the screen edges. Fall back to the main
            // screen because a window already off-screen reports `screen == nil`.
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
            if let visible = screen?.visibleFrame {
                window.maxSize = NSSize(width: visible.width, height: visible.height)
                frame.size.width = min(frame.size.width, visible.width)
                frame.size.height = min(frame.size.height, visible.height)
                if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
                if frame.minX < visible.minX { frame.origin.x = visible.minX }
                if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
                if frame.minY < visible.minY { frame.origin.y = visible.minY }
            }

            if frame != window.frame {
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
