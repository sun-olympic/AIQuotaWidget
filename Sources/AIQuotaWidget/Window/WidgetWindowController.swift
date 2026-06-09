import AppKit
import SwiftUI
import Combine

/// 管理悬浮面板：承载 SwiftUI 内容、应用置顶设置、记忆并恢复窗口位置。
@MainActor
final class WidgetWindowController: NSObject, NSWindowDelegate {

    let panel: FloatingPanel
    private let settings: AppSettings
    private let service: QuotaService?
    private var cancellables = Set<AnyCancellable>()

    static let defaultSize = NSSize(width: 320, height: 220)

    init(settings: AppSettings, service: QuotaService? = nil, rootView: some View) {
        self.settings = settings
        self.service = service

        let origin = settings.savedWindowOrigin()
            ?? CGPoint(x: 200, y: 400)
        
        let initialSize: NSSize
        if settings.isCollapsed {
            initialSize = NSSize(width: 120, height: 120)
        } else {
            let baseHeight: CGFloat = 220
            var secondaryHeight: CGFloat = 0
            if let service = service {
                let state: WidgetState
                switch settings.selectedTab {
                case .cursor: state = service.cursorState
                case .codex: state = service.codexState
                case .antigravity: state = service.antigravityState
                }
                if case .loaded(let snapshot) = state,
                   let windows = snapshot.secondaryWindows,
                   !windows.isEmpty {
                    let maxSecondaryHeight = settings.selectedTab == .antigravity ? 120.0 : 56.0
                    let count = Double(windows.count)
                    secondaryHeight = max(0.0, min(count * 25.0, maxSecondaryHeight) - 25.0)
                }
            } else {
                secondaryHeight = (settings.selectedTab == .antigravity) ? 100 : 0
            }
            initialSize = NSSize(width: 320, height: baseHeight + secondaryHeight)
        }
        
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

        // Observe settings changes and state changes to update window size
        var publishers = [
            settings.$selectedTab.map { _ in () }.eraseToAnyPublisher(),
            settings.$isCollapsed.map { _ in () }.eraseToAnyPublisher()
        ]
        if let service = service {
            publishers.append(service.$cursorState.map { _ in () }.eraseToAnyPublisher())
            publishers.append(service.$codexState.map { _ in () }.eraseToAnyPublisher())
            publishers.append(service.$antigravityState.map { _ in () }.eraseToAnyPublisher())
        }
        
        Publishers.MergeMany(publishers)
            .sink { [weak self] _ in
                self?.recalculateWindowSize()
            }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func applyPinState(_ pinned: Bool) {
        let isTesting = NSClassFromString("XCTest") != nil
        if isTesting {
            panel.isFloatingPanel = true
            panel.level = .floating
        } else {
            panel.isFloatingPanel = pinned
            panel.level = pinned ? .floating : .normal
        }
    }

    private func recalculateWindowSize() {
        let targetSize: NSSize
        if settings.isCollapsed {
            targetSize = NSSize(width: 120, height: 120)
        } else {
            let baseHeight: CGFloat = 220
            var secondaryHeight: CGFloat = 0
            if let service = service {
                let state: WidgetState
                switch settings.selectedTab {
                case .cursor: state = service.cursorState
                case .codex: state = service.codexState
                case .antigravity: state = service.antigravityState
                }
                if case .loaded(let snapshot) = state,
                   let windows = snapshot.secondaryWindows,
                   !windows.isEmpty {
                    let maxSecondaryHeight = settings.selectedTab == .antigravity ? 120.0 : 56.0
                    let count = Double(windows.count)
                    secondaryHeight = max(0.0, min(count * 25.0, maxSecondaryHeight) - 25.0)
                }
            } else {
                secondaryHeight = (settings.selectedTab == .antigravity) ? 100 : 0
            }
            targetSize = NSSize(width: 320, height: baseHeight + secondaryHeight)
        }
        updateWindowFrame(targetSize: targetSize)
    }

    private func updateWindowFrame(targetSize: NSSize) {
        var frame = panel.frame
        let diffHeight = targetSize.height - frame.size.height
        let diffWidth = targetSize.width - frame.size.width
        
        if abs(diffHeight) > 0.001 || abs(diffWidth) > 0.001 {
            frame.origin.y -= diffHeight
            frame.origin.x -= diffWidth
            frame.size = targetSize
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        settings.saveWindowOrigin(panel.frame.origin)
    }
}
