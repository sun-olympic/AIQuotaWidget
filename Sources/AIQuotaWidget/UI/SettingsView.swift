import SwiftUI

/// 设置面板：语言、刷新间隔、水球晃动、置顶。
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
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

            Toggle(settings.t("settings.wave"), isOn: $settings.waveEnabled)
            Toggle(settings.t("settings.pinned"), isOn: $settings.pinnedOnTop)
            Toggle(settings.t("settings.coarseModelGrouping"), isOn: $settings.coarseModelGrouping)

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
        .frame(width: 240)
    }

    private func intervalLabel(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval)) \(settings.t("interval.seconds"))"
        }
        return "\(Int(interval / 60)) \(settings.t("interval.minutes"))"
    }
}
