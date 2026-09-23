import AppKit
import SwiftUI

/// A short message that appears near the cursor and fades away, like "No Japanese text found".
@MainActor
enum NoticePanel {
    static func show(_ message: String, duration: TimeInterval = 1.6) {
        let hosting = NSHostingView(rootView:
            Text(message)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: .capsule)
                .fixedSize()
        )
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let panel = NSPanel(
            contentRect: CGRect(x: mouse.x + 12, y: mouse.y - size.height - 12, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        panel.orderFrontRegardless()

        Task {
            try? await Task.sleep(for: .seconds(duration))
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
        }
    }
}
