import AppKit

/// 无边框、nonactivating、不抢焦点的悬浮面板。
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // 透明背景，由 SwiftUI/NSVisualEffectView 提供液态玻璃。
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // 背景区域可拖拽，窗口自由移动到任意位置。
        isMovableByWindowBackground = true
        // 全空间可见、不随窗口循环切换。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    // 允许成为 key 窗口以便操作控件，但不会激活 App（nonactivatingPanel）。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        var rect = frameRect
        if frame.size.height > 0 && abs(rect.size.height - frame.size.height) > 0.001 {
            let diff = rect.size.height - frame.size.height
            rect.origin.y = frame.origin.y - diff
        }
        super.setFrame(rect, display: displayFlag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        var rect = frameRect
        if frame.size.height > 0 && abs(rect.size.height - frame.size.height) > 0.001 {
            let diff = rect.size.height - frame.size.height
            rect.origin.y = frame.origin.y - diff
        }
        super.setFrame(rect, display: displayFlag, animate: animateFlag)
    }
}
