import SwiftUI

/// 设置面板：语言、刷新间隔、水球晃动、置顶。
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: QuotaService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(settings.t("settings.title"))
                    .font(.headline)

                Picker(settings.t("settings.language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)

                Picker(settings.t("settings.refreshInterval"), selection: $settings.refreshInterval) {
                    ForEach(AppSettings.intervalOptions, id: \.self) { interval in
                        Text(intervalLabel(interval)).tag(interval)
                    }
                }

                Picker(settings.t("settings.theme"), selection: $settings.widgetTheme) {
                    ForEach(WidgetTheme.allCases) { theme in
                        Text(settings.t(theme.localizationKey)).tag(theme)
                    }
                }

                if settings.enabledTabs.contains(.cursor) && isCursorUsageBased {
                    Picker(settings.t("settings.cursorBillingMode"), selection: $settings.cursorBillingMode) {
                        ForEach(CursorBillingMode.allCases) { mode in
                            Text(settings.t(mode.localizationKey)).tag(mode)
                        }
                    }
                }

                Toggle(settings.t("settings.wave"), isOn: $settings.waveEnabled)
                Toggle(settings.t("settings.pinned"), isOn: $settings.pinnedOnTop)
                if settings.enabledTabs.contains(.antigravity) {
                    Toggle(settings.t("settings.coarseModelGrouping"), isOn: $settings.coarseModelGrouping)
                }
                Toggle(settings.t("settings.autoCollapse"), isOn: $settings.autoCollapse)

                if settings.enabledTabs.contains(.codex) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.t("settings.customCodexPath"))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.8))
                        TextField(settings.t("settings.customCodexPathPlaceholder"), text: $settings.customCodexPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10))
                    }
                }



                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.t("settings.enabledTabs"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))

                    ForEach(ProductTab.allCases) { tab in
                        Toggle(settings.t(tab.titleKey), isOn: Binding(
                            get: { settings.enabledTabs.contains(tab) },
                            set: { isEnabled in
                                if isEnabled {
                                    if !settings.enabledTabs.contains(tab) {
                                        settings.enabledTabs.append(tab)
                                    }
                                } else {
                                    if settings.enabledTabs.count > 1 {
                                        settings.enabledTabs.removeAll { $0 == tab }
                                    }
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 240)
        .frame(maxHeight: 450)
    }

    private func intervalLabel(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval)) \(settings.t("interval.seconds"))"
        }
        return "\(Int(interval / 60)) \(settings.t("interval.minutes"))"
    }

    private var isCursorUsageBased: Bool {
        if case let .loaded(snapshot) = service.state(for: .cursor) {
            return snapshot.mode == .usageBased
        }
        return false
    }
}
