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
            if frame.size != window.frame.size {
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
