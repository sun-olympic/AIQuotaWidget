import AppKit

/// 无边框、透明背景的悬浮窗口。
final class FloatingPanel: NSWindow {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let isTesting = NSClassFromString("XCTest") != nil
        level = isTesting ? .floating : .normal
        // 透明背景，由 SwiftUI/NSVisualEffectView 提供液态玻璃。
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // 背景区域可拖拽，窗口自由移动到任意位置。
        isMovableByWindowBackground = true
        // 全空间可见、不随窗口循环切换。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    // 允许成为 key 窗口以便操作控件。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        var rect = frameRect
        if frame.size.height > 0 && abs(rect.size.height - frame.size.height) > 0.001 {
            let diffY = rect.size.height - frame.size.height
            rect.origin.y = frame.origin.y - diffY
        }
        if frame.size.width > 0 && abs(rect.size.width - frame.size.width) > 0.001 {
            let diffX = rect.size.width - frame.size.width
            rect.origin.x = frame.origin.x - diffX
        }
        let clampedRect = clampToScreen(rect)
        super.setFrame(clampedRect, display: displayFlag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        var rect = frameRect
        if frame.size.height > 0 && abs(rect.size.height - frame.size.height) > 0.001 {
            let diffY = rect.size.height - frame.size.height
            rect.origin.y = frame.origin.y - diffY
        }
        if frame.size.width > 0 && abs(rect.size.width - frame.size.width) > 0.001 {
            let diffX = rect.size.width - frame.size.width
            rect.origin.x = frame.origin.x - diffX
        }
        let clampedRect = clampToScreen(rect)
        super.setFrame(clampedRect, display: displayFlag, animate: animateFlag)
    }

    private func clampToScreen(_ rect: NSRect) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let activeScreen = screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? self.screen
            ?? NSScreen.main
        
        guard let screen = activeScreen else {
            return rect
        }
        let visibleFrame = screen.visibleFrame
        var clampedRect = rect
        
        clampedRect.size.width = min(clampedRect.size.width, visibleFrame.size.width)
        clampedRect.size.height = min(clampedRect.size.height, visibleFrame.size.height)
        
        if clampedRect.origin.x < visibleFrame.minX {
            clampedRect.origin.x = visibleFrame.minX
        } else if clampedRect.origin.x + clampedRect.size.width > visibleFrame.maxX {
            clampedRect.origin.x = visibleFrame.maxX - clampedRect.size.width
        }
        
        if clampedRect.origin.y < visibleFrame.minY {
            clampedRect.origin.y = visibleFrame.minY
        } else if clampedRect.origin.y + clampedRect.size.height > visibleFrame.maxY {
            clampedRect.origin.y = visibleFrame.maxY - clampedRect.size.height
        }
        
        return clampedRect
    }
}
