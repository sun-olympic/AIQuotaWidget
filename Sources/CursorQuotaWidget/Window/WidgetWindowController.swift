import AppKit
import SwiftUI
import Combine

/// 管理悬浮面板：承载 SwiftUI 内容、应用置顶设置、记忆并恢复窗口位置。
@MainActor
final class WidgetWindowController: NSObject, NSWindowDelegate {

    private let panel: FloatingPanel
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    static let defaultSize = NSSize(width: 320, height: 220)

    init(settings: AppSettings, rootView: some View) {
        self.settings = settings

        let origin = settings.savedWindowOrigin()
            ?? CGPoint(x: 200, y: 400)
        let rect = NSRect(origin: origin, size: Self.defaultSize)
        self.panel = FloatingPanel(contentRect: rect)

        super.init()

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: Self.defaultSize)
        panel.contentView = hosting
        panel.delegate = self

        applyPinState(settings.pinnedOnTop)

        // 置顶开关变化即时生效。
        settings.$pinnedOnTop
            .sink { [weak self] pinned in self?.applyPinState(pinned) }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func applyPinState(_ pinned: Bool) {
        panel.level = pinned ? .floating : .normal
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        settings.saveWindowOrigin(panel.frame.origin)
    }
}
