import Foundation
import Combine
import CoreGraphics

/// 用户偏好，持久化到 `UserDefaults`，启动时恢复。
final class AppSettings: ObservableObject {

    private enum Key {
        static let language = "settings.language"
        static let refreshInterval = "settings.refreshInterval"
        static let waveEnabled = "settings.waveEnabled"
        static let pinnedOnTop = "settings.pinnedOnTop"
        static let windowFrame = "settings.windowFrame"
        static let selectedTab = "settings.selectedTab"
        static let enabledTabs = "settings.enabledTabs"
        static let antigravityDefaultModelId = "settings.antigravityDefaultModelId"
    }

    private let defaults: UserDefaults

    /// 可选刷新间隔（秒）。
    static let intervalOptions: [TimeInterval] = [30, 60, 300, 600, 1800]

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    @Published var waveEnabled: Bool {
        didSet { defaults.set(waveEnabled, forKey: Key.waveEnabled) }
    }

    @Published var pinnedOnTop: Bool {
        didSet { defaults.set(pinnedOnTop, forKey: Key.pinnedOnTop) }
    }

    @Published var selectedTab: ProductTab {
        didSet { defaults.set(selectedTab.rawValue, forKey: Key.selectedTab) }
    }

    @Published var enabledTabs: [ProductTab] {
        didSet {
            defaults.set(enabledTabs.map { $0.rawValue }, forKey: Key.enabledTabs)
            ensureSelectedTabValid()
        }
    }

    @Published var antigravityDefaultModelId: String? {
        didSet {
            if let id = antigravityDefaultModelId {
                defaults.set(id, forKey: Key.antigravityDefaultModelId)
            } else {
                defaults.removeObject(forKey: Key.antigravityDefaultModelId)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: Key.language), let lang = AppLanguage(rawValue: raw) {
            self.language = lang
        } else {
            // 跟随系统：简体中文环境默认中文，否则英文。
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.language = preferred.hasPrefix("zh") ? .chinese : .english
        }

        let storedInterval = defaults.double(forKey: Key.refreshInterval)
        self.refreshInterval = storedInterval > 0 ? storedInterval : 60

        self.waveEnabled = defaults.object(forKey: Key.waveEnabled) as? Bool ?? true
        self.pinnedOnTop = defaults.object(forKey: Key.pinnedOnTop) as? Bool ?? true

        let enabled: [ProductTab]
        if let rawArray = defaults.stringArray(forKey: Key.enabledTabs) {
            let parsed = rawArray.compactMap { ProductTab(rawValue: $0) }
            enabled = parsed.isEmpty ? ProductTab.allCases : parsed
        } else {
            enabled = ProductTab.allCases
        }
        self.enabledTabs = enabled

        if let raw = defaults.string(forKey: Key.selectedTab), let tab = ProductTab(rawValue: raw), enabled.contains(tab) {
            self.selectedTab = tab
        } else {
            self.selectedTab = enabled.first ?? .cursor
        }

        self.antigravityDefaultModelId = defaults.string(forKey: Key.antigravityDefaultModelId)
    }

    func ensureSelectedTabValid() {
        if !enabledTabs.contains(selectedTab) {
            selectedTab = enabledTabs.first ?? .cursor
        }
    }

    func t(_ key: String) -> String {
        Strings.t(key, language)
    }

    // MARK: - 窗口位置记忆

    func savedWindowOrigin() -> CGPoint? {
        guard let arr = defaults.array(forKey: Key.windowFrame) as? [Double], arr.count == 2 else {
            return nil
        }
        return CGPoint(x: arr[0], y: arr[1])
    }

    func saveWindowOrigin(_ origin: CGPoint) {
        defaults.set([Double(origin.x), Double(origin.y)], forKey: Key.windowFrame)
    }
}

/// 额度来源（同时作为顶部 Tab）。
enum ProductTab: String, CaseIterable, Identifiable {
    case cursor
    case codex
    case antigravity

    var id: String { rawValue }

    /// Tab 标题本地化 key。
    var titleKey: String { "tab.\(rawValue)" }

    /// 主维度取值规则的本地化说明 key：
    /// Cursor=月额度 / Codex=5h 窗口 / Antigravity=默认模型。阈值统一复用 <10/<20/≥20。
    var mainDimensionKey: String { "dim.\(rawValue)" }
}
