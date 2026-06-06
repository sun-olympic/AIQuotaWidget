import AppKit
import SwiftUI
import Combine

/// 管理悬浮面板：承载 SwiftUI 内容、应用置顶设置、记忆并恢复窗口位置。
@MainActor
final class WidgetWindowController: NSObject, NSWindowDelegate {

    let panel: FloatingPanel
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    static let defaultSize = NSSize(width: 320, height: 220)

    init(settings: AppSettings, rootView: some View) {
        self.settings = settings

        let origin = settings.savedWindowOrigin()
            ?? CGPoint(x: 200, y: 400)
        let initialHeight: CGFloat = (settings.selectedTab == .antigravity) ? 320 : 220
        let initialSize = NSSize(width: 320, height: initialHeight)
        let rect = NSRect(origin: origin, size: initialSize)
        self.panel = FloatingPanel(contentRect: rect)

        super.init()

        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: initialSize)
        panel.contentView = hosting
        panel.delegate = self

        applyPinState(settings.pinnedOnTop)

        // 置顶开关变化即时生效。
        settings.$pinnedOnTop
            .sink { [weak self] pinned in self?.applyPinState(pinned) }
            .store(in: &cancellables)

        // Tab 变化时自动调整窗口高度
        settings.$selectedTab
            .sink { [weak self] tab in
                DispatchQueue.main.async {
                    self?.updateWindowHeight(for: tab)
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func applyPinState(_ pinned: Bool) {
        panel.level = pinned ? .floating : .normal
    }

    private func updateWindowHeight(for tab: ProductTab) {
        let targetHeight: CGFloat = (tab == .antigravity) ? 320 : 220
        var frame = panel.frame
        let diff = targetHeight - frame.size.height
        if abs(diff) > 0.001 {
            frame.origin.y -= diff // 保持顶部不变，向下延展
            frame.size.height = targetHeight
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        settings.saveWindowOrigin(panel.frame.origin)
    }
}
