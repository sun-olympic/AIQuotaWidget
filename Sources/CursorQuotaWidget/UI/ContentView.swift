import SwiftUI

/// 悬浮窗主视图：液态玻璃背景 + 顶部栏 + Tab + 内容区。
struct ContentView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: QuotaService
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TabBarView(selected: settings.selectedTab,
                       onSelect: { service.userSelect($0) },
                       settings: settings)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(width: 320, height: 220)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
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
                SecondaryWindowsView(windows: windows, settings: settings)
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
}
