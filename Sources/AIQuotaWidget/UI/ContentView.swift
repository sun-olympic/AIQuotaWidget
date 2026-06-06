import SwiftUI

/// 悬浮窗主视图：液态玻璃背景 + 顶部栏 + Tab + 内容区。
struct ContentView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: QuotaService
    @State private var showSettings = false

    @State private var collapseTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if settings.isCollapsed {
                collapsedView
                    .transition(.scale.combined(with: .opacity))
            } else {
                expandedView
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(settings.isCollapsed ? 0 : 14)
        .frame(width: settings.isCollapsed ? 80 : 320,
               height: settings.isCollapsed ? 80 : currentExpandedHeight)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: settings.isCollapsed ? 40 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: settings.isCollapsed ? 40 : 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: settings.isCollapsed ? 40 : 18, style: .continuous))
        .onHover { hovering in
            handleHover(hovering)
        }
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TabBarView(selected: settings.selectedTab,
                       onSelect: { service.userSelect($0) },
                       settings: settings)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            ledOrTitle
            Spacer()
            actionButtons
        }
    }

    @ViewBuilder
    private var ledOrTitle: some View {
        if case let .loaded(snapshot) = service.state(for: settings.selectedTab) {
            LEDView(status: snapshot.ledStatus,
                    label: settings.t(snapshot.ledStatus.localizationKey))
        } else {
            Text(settings.t("app.title"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            iconButton("arrow.clockwise", help: settings.t("action.refresh")) {
                service.refreshNow()
            }
            iconButton(settings.pinnedOnTop ? "pin.fill" : "pin", help: settings.t("action.pin")) {
                settings.pinnedOnTop.toggle()
            }
            iconButton("globe", help: settings.t("action.language")) {
                settings.language = settings.language.toggled
            }
            iconButton("gearshape", help: settings.t("action.settings")) {
                showSettings.toggle()
            }
            .popover(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            iconButton("power", help: settings.t("action.quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch service.state(for: settings.selectedTab) {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .loaded(let snapshot):
            loadedView(snapshot)
        case .notLoggedIn:
            placeholder(text: settings.t("state.notLoggedIn"),
                        subtitle: settings.t(loginHintKey(for: settings.selectedTab)),
                        systemImage: "person.crop.circle.badge.questionmark")
        case .needsReLogin:
            placeholder(text: settings.t("state.needsReLogin"),
                        subtitle: settings.t("state.needsReLogin.hint"),
                        systemImage: "exclamationmark.triangle")
        case .notInstalled:
            placeholder(text: settings.t("state.notInstalled"),
                        subtitle: settings.t("codex.install.hint"),
                        systemImage: "shippingbox")
        case .error(let message):
            placeholder(text: settings.t("state.error"),
                        subtitle: message,
                        systemImage: "wifi.exclamationmark")
        }
    }

    /// 未登录提示文案随来源不同。
    private func loginHintKey(for tab: ProductTab) -> String {
        switch tab {
        case .cursor: return "state.notLoggedIn.hint"
        case .codex: return "codex.login.hint"
        case .antigravity: return "antigravity.login.hint"
        }
    }

    private func loadedView(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                WaterBallView(
                    percent: snapshot.clampedPercent,
                    leftLabel: settings.t("left.suffix"),
                    waveEnabled: settings.waveEnabled,
                    color: snapshot.ledStatus.color
                )
                InfoBlockView(snapshot: snapshot, settings: settings)
                Spacer(minLength: 0)
            }
            if let windows = snapshot.secondaryWindows, !windows.isEmpty {
                SecondaryWindowsView(
                    windows: windows,
                    settings: settings,
                    maxHeight: max(25.0, min(Double(windows.count) * 25.0, settings.selectedTab == .antigravity ? 120.0 : 56.0))
                )
            }
        }
    }

    private func placeholder(text: String, subtitle: String? = nil, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.7))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Collapse & Adaptive Height Helpers

    private struct CollapsedWaterBallData {
        let percent: Double
        let leftLabel: String
        let color: Color
    }

    private var collapsedWaterBallData: CollapsedWaterBallData {
        switch service.state(for: settings.selectedTab) {
        case .loaded(let snapshot):
            return CollapsedWaterBallData(
                percent: snapshot.clampedPercent,
                leftLabel: settings.t("left.suffix"),
                color: snapshot.ledStatus.color
            )
        case .loading:
            return CollapsedWaterBallData(
                percent: 0,
                leftLabel: "...",
                color: .blue
            )
        case .notLoggedIn, .needsReLogin, .notInstalled:
            return CollapsedWaterBallData(
                percent: 0,
                leftLabel: "?",
                color: .orange
            )
        case .error:
            return CollapsedWaterBallData(
                percent: 0,
                leftLabel: "!",
                color: .red
            )
        }
    }

    private var collapsedView: some View {
        let data = collapsedWaterBallData
        return WaterBallView(
            percent: data.percent,
            leftLabel: data.leftLabel,
            waveEnabled: settings.waveEnabled && data.percent > 0,
            color: data.color,
            size: 64
        )
        .frame(width: 80, height: 80, alignment: .center)
    }

    private var currentExpandedHeight: CGFloat {
        let baseHeight: CGFloat = 220
        if case .loaded(let snapshot) = service.state(for: settings.selectedTab),
           let windows = snapshot.secondaryWindows,
           !windows.isEmpty {
            let maxSecondaryHeight = settings.selectedTab == .antigravity ? 120.0 : 56.0
            let count = Double(windows.count)
            let secondaryHeight = max(0.0, min(count * 25.0, maxSecondaryHeight) - 25.0)
            return baseHeight + secondaryHeight
        }
        return baseHeight
    }

    private func handleHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            if settings.isCollapsed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    settings.isCollapsed = false
                }
            }
        } else {
            guard settings.autoCollapse else { return }
            collapseTask?.cancel()
            collapseTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    if !Task.isCancelled {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            settings.isCollapsed = true
                        }
                    }
                } catch {}
            }
        }
    }
}
