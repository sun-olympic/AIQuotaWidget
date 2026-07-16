import SwiftUI
import UniformTypeIdentifiers

/// 悬浮窗主视图：液态玻璃背景 + 顶部栏 + Tab + 内容区。
struct ContentView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: QuotaService
    @State private var showSettings = false
    @State private var isHovering = false

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
        .frame(width: settings.isCollapsed ? 120 : 320,
               height: settings.isCollapsed ? 120 : currentExpandedHeight)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(WidgetClipShape(isCollapsed: settings.isCollapsed, theme: settings.widgetTheme, cornerRadius: currentCornerRadius))
        .overlay(
            WidgetClipShape(isCollapsed: settings.isCollapsed, theme: settings.widgetTheme, cornerRadius: currentCornerRadius)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .contentShape(WidgetClipShape(isCollapsed: settings.isCollapsed, theme: settings.widgetTheme, cornerRadius: currentCornerRadius))
        .onHover { hovering in
            isHovering = hovering
            handleHover(hovering)
        }
        .onChange(of: showSettings) { show in
            if !show {
                if !isHovering {
                    triggerCollapseTask()
                }
            } else {
                collapseTask?.cancel()
                collapseTask = nil
            }
        }
        .popover(isPresented: $showSettings) {
            SettingsView(settings: settings, service: service)
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
            if let url = settings.selectedTab.dashboardURL {
                iconButton("safari", help: settings.t("action.dashboard")) {
                    NSWorkspace.shared.open(url)
                }
            }
            iconButton("gearshape", help: settings.t("action.settings")) {
                showSettings.toggle()
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
        case .claudecode: return "claudecode.login.hint"
        }
    }

    private func loadedView(_ snapshot: QuotaSnapshot) -> some View {
        let overrideText = (settings.selectedTab == .cursor && snapshot.mode == .legacy)
            ? snapshot.primaryText.replacingOccurrences(of: " requests", with: "").replacingOccurrences(of: " / ", with: "/")
            : nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                WaterBallView(
                    percent: snapshot.clampedPercent,
                    leftLabel: settings.t("left.suffix"),
                    waveEnabled: settings.waveEnabled,
                    color: snapshot.ledStatus.color,
                    theme: settings.widgetTheme,
                    centerTextOverride: overrideText
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
            if let recent = snapshot.recentRequests, !recent.isEmpty {
                RecentRequestsView(requests: recent, settings: settings)
            }
            if settings.selectedTab == .codex {
                codexExportButton
            }
        }
    }

    @State private var codexExportMessage: String?

    private var codexExportButton: some View {
        HStack(spacing: 4) {
            Button(action: exportCodexCSV) {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 9))
                    Text(settings.t("codex.export"))
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(settings.t("codex.export.help"))

            if let msg = codexExportMessage {
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func exportCodexCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "codex-usage-\(dateFmt.string(from: Date())).csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let rows = QuotaService.readCodexAllTurns(daysBack: 30)
            var csv = "\u{FEFF}日期时间,模型,输入Tokens,输出Tokens,缓存读取Tokens,缓存写入Tokens,总Tokens\n"
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            for r in rows {
                csv += "\(df.string(from: r.timestamp)),\(r.model),\(r.inputTokens),\(r.outputTokens),\(r.cacheReadTokens),\(r.cacheWriteTokens),\(r.totalTokens)\n"
            }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    codexExportMessage = "\(settings.t("codex.export.done")) (\(rows.count))"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { codexExportMessage = nil }
                }
            } catch {
                DispatchQueue.main.async {
                    codexExportMessage = settings.t("codex.export.fail")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { codexExportMessage = nil }
                }
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
        let centerTextOverride: String?
    }

    private var collapsedWaterBallData: CollapsedWaterBallData {
        switch service.state(for: settings.selectedTab) {
        case .loaded(let snapshot):
            let overrideText = (settings.selectedTab == .cursor && snapshot.mode == .legacy)
                ? snapshot.primaryText.replacingOccurrences(of: " requests", with: "").replacingOccurrences(of: " / ", with: "/")
                : nil
            return CollapsedWaterBallData(
                percent: snapshot.clampedPercent,
                leftLabel: settings.t("left.suffix"),
                color: snapshot.ledStatus.color,
                centerTextOverride: overrideText
            )
        case .loading:
            return CollapsedWaterBallData(
                percent: 0,
                leftLabel: "...",
                color: .blue,
                centerTextOverride: nil
            )
        case .notLoggedIn, .needsReLogin, .notInstalled:
            return CollapsedWaterBallData(
                percent: 0,
                leftLabel: "?",
                color: .orange,
                centerTextOverride: nil
            )
        case .error:
            return CollapsedWaterBallData(
                percent: 0,
                leftLabel: "!",
                color: .red,
                centerTextOverride: nil
            )
        }
    }

    var collapsedTooltipText: String {
        let toolName = settings.t("tab.\(settings.selectedTab.rawValue)")
        var lines: [String] = []

        switch settings.selectedTab {
        case .cursor:
            if case let .loaded(snapshot) = service.state(for: .cursor), snapshot.mode == .usageBased {
                let modeStr = settings.cursorBillingMode == .api ? settings.t("cursor.billingMode.api") : settings.t("cursor.billingMode.auto")
                lines.append("\(toolName) (\(modeStr))")
            } else {
                lines.append(toolName)
            }
        case .antigravity:
            if case let .loaded(snapshot) = service.state(for: .antigravity),
               let modelId = snapshot.activeAntigravityModelId ?? settings.antigravityDefaultModelId {
                let modelName = snapshot.antigravityModels?.first(where: { $0.id == modelId })?.name ?? modelId
                lines.append("\(toolName) (\(modelName))")
            } else if let modelId = settings.antigravityDefaultModelId {
                lines.append("\(toolName) (\(modelId))")
            } else {
                lines.append(toolName)
            }
        default:
            lines.append(toolName)
        }

        if case let .loaded(snapshot) = service.state(for: settings.selectedTab) {
            lines.append(snapshot.primaryText)
            if let resetAt = snapshot.resetAt {
                lines.append("\(settings.t("reset.in")) \(Countdown.format(until: resetAt, settings: settings))")
            }
            if let plan = snapshot.planName {
                lines.append("\(settings.t("plan.label")): \(plan)")
            }
            if let recent = snapshot.recentRequests, !recent.isEmpty {
                lines.append("")
                lines.append(settings.t("recent.title"))
                let fmtNum = RecentRequestsView.fmtNum
                for req in recent {
                    let tokens = RecentRequestsView.formatTokens(req.totalTokens, lang: settings.language)
                    let time = RecentRequestsView.formatTime(req.timestamp)
                    var detail = "\(req.model)  \(tokens)  \(time)"
                    var parts: [String] = []
                    if req.cacheReadTokens > 0 { parts.append("CR:\(fmtNum(req.cacheReadTokens))") }
                    if req.cacheWriteTokens > 0 { parts.append("CW:\(fmtNum(req.cacheWriteTokens))") }
                    parts.append("\(settings.t("recent.input")):\(fmtNum(req.inputTokens))")
                    parts.append("\(settings.t("recent.output")):\(fmtNum(req.outputTokens))")
                    detail += "\n  " + parts.joined(separator: " / ")
                    lines.append(detail)
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private var collapsedView: some View {
        let data = collapsedWaterBallData
        let size: CGFloat = 96
        return WaterBallView(
            percent: data.percent,
            leftLabel: data.leftLabel,
            waveEnabled: settings.waveEnabled && data.percent > 0,
            color: data.color,
            size: size,
            theme: settings.widgetTheme,
            centerTextOverride: data.centerTextOverride
        )
        .frame(width: 120, height: 120, alignment: .center)
        .contentShape(Rectangle())
        .help(collapsedTooltipText)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                settings.isCollapsed = false
            }
        }
        .contextMenu {
            Button(settings.t("action.expand")) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    settings.isCollapsed = false
                }
            }
            Divider()
            Button(settings.t("action.refresh")) {
                service.refreshNow()
            }
            Toggle(settings.t("settings.autoCollapse"), isOn: $settings.autoCollapse)
            Divider()
            Button(settings.t("action.settings")) {
                showSettings = true
            }
            Menu(settings.t("action.switchTool")) {
                ForEach(settings.enabledTabs) { tab in
                    Button(action: {
                        service.userSelect(tab)
                    }) {
                        HStack {
                            Text(settings.t(tab.titleKey))
                            if tab == settings.selectedTab {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            if settings.selectedTab == .cursor {
                if case let .loaded(snapshot) = service.state(for: .cursor), snapshot.mode == .usageBased {
                    Menu(settings.t("settings.cursorBillingMode")) {
                        ForEach(CursorBillingMode.allCases) { mode in
                            Button(action: {
                                settings.cursorBillingMode = mode
                            }) {
                                HStack {
                                    Text(settings.t(mode.localizationKey))
                                    if mode == settings.cursorBillingMode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } else if settings.selectedTab == .antigravity {
                if case let .loaded(snapshot) = service.state(for: .antigravity),
                   let models = snapshot.antigravityModels, !models.isEmpty {
                    Menu(settings.t("dim.antigravity")) {
                        ForEach(models) { model in
                            Button(action: {
                                settings.antigravityDefaultModelId = model.id
                            }) {
                                HStack {
                                    Text(model.name)
                                    if model.id == snapshot.activeAntigravityModelId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Button(settings.t("action.quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var currentExpandedHeight: CGFloat {
        var height: CGFloat = 220
        guard case .loaded(let snapshot) = service.state(for: settings.selectedTab) else {
            return height
        }
        if let windows = snapshot.secondaryWindows, !windows.isEmpty {
            let maxSecondaryHeight = settings.selectedTab == .antigravity ? 120.0 : 56.0
            let count = Double(windows.count)
            height += max(0.0, min(count * 25.0, maxSecondaryHeight) - 25.0)
        }
        if let recent = snapshot.recentRequests, !recent.isEmpty {
            // ponytail: 标题 14 + 每行 16，留 4 间距
            height += 18 + CGFloat(recent.count) * 16
        }
        if settings.selectedTab == .codex {
            height += 24
        }
        return height
    }

    private var currentCornerRadius: CGFloat {
        if settings.isCollapsed {
            return 60
        } else {
            return 18
        }
    }

    private func triggerCollapseTask() {
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

    private func handleHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
        } else {
            guard !showSettings else { return }
            triggerCollapseTask()
        }
    }
}

/// 统一的窗口剪影裁剪形状，支持折叠态下的全身卡通主题外廓。
struct WidgetClipShape: Shape {
    let isCollapsed: Bool
    let theme: WidgetTheme
    let cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        if isCollapsed {
            // 折叠状态下，如果为经典水球，则大小为 96x96，居中放置在 120x120 窗口中（留白 12pt）
            let size: CGFloat = 96
            let padding = (rect.width - size) / 2
            let ballRect = CGRect(x: padding, y: padding, width: size, height: size)
            return WaterBallView.silhouettePath(for: theme, in: ballRect)
        } else {
            var path = Path()
            path.addPath(Path(roundedRect: rect, cornerRadius: cornerRadius))
            return path
        }
    }
}
