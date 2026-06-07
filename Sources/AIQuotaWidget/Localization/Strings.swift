import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    var toggled: AppLanguage {
        self == .english ? .chinese : .english
    }
}

/// 运行时本地化文案表。语言切换即时刷新（不依赖 .lproj bundle 重启）。
enum Strings {
    static func t(_ key: String, _ language: AppLanguage) -> String {
        table[key]?[language] ?? key
    }

    private static let table: [String: [AppLanguage: String]] = [
        "app.title": [.english: "AI Quota", .chinese: "AI 额度"],
        "tab.cursor": [.english: "Cursor", .chinese: "Cursor"],
        "tab.codex": [.english: "Codex", .chinese: "Codex"],
        "tab.antigravity": [.english: "Antigravity", .chinese: "Antigravity"],
        "dim.cursor": [.english: "Monthly quota", .chinese: "月额度"],
        "dim.codex": [.english: "5h window", .chinese: "5 小时窗口"],
        "dim.antigravity": [.english: "Default model", .chinese: "默认模型"],
        "window.exhausted": [.english: "Exhausted", .chinese: "已耗尽"],
        "left.suffix": [.english: "Left", .chinese: "剩余"],
        "status.green": [.english: "Green", .chinese: "充足"],
        "status.yellow": [.english: "Yellow", .chinese: "偏低"],
        "status.red": [.english: "Red", .chinese: "告急"],
        "reset.in": [.english: "Resets in", .chinese: "重置剩余"],
        "reset.unknown": [.english: "Reset time unknown", .chinese: "重置时间未知"],
        "plan.label": [.english: "Plan", .chinese: "计划"],
        "ondemand.label": [.english: "On-demand", .chinese: "按需用量"],
        "state.loading": [.english: "Loading…", .chinese: "加载中…"],
        "state.notLoggedIn": [.english: "Not signed in", .chinese: "未登录"],
        "state.notLoggedIn.hint": [.english: "Please sign in to Cursor first", .chinese: "请先登录 Cursor"],
        "state.needsReLogin": [.english: "Session expired", .chinese: "登录已过期"],
        "state.needsReLogin.hint": [.english: "Please sign in to Cursor again", .chinese: "请在 Cursor 中重新登录"],
        "state.notInstalled": [.english: "Codex CLI not installed", .chinese: "未安装 Codex CLI"],
        "state.error": [.english: "Failed to load", .chinese: "加载失败"],
        "codex.comingSoon": [.english: "Coming soon", .chinese: "即将支持"],
        "codex.install.hint": [.english: "Install Codex CLI and sign in", .chinese: "请先安装 Codex CLI 并登录"],
        "codex.login.hint": [.english: "Please sign in to Codex", .chinese: "请先在 Codex 中登录"],
        "antigravity.login.hint": [.english: "Please sign in to Antigravity", .chinese: "请先在 Antigravity 中登录"],
        "settings.title": [.english: "Settings", .chinese: "设置"],
        "settings.enabledTabs": [.english: "Supported Tools", .chinese: "支持的工具"],
        "settings.language": [.english: "Language", .chinese: "语言"],
        "settings.refreshInterval": [.english: "Refresh interval", .chinese: "刷新间隔"],
        "settings.wave": [.english: "Water wave animation", .chinese: "水球晃动动画"],
        "settings.pinned": [.english: "Always on top", .chinese: "窗口置顶"],
        "settings.coarseModelGrouping": [.english: "Group same series models (Antigravity)", .chinese: "合并同系列模型 (Antigravity)"],
        "settings.autoCollapse": [.english: "Auto-collapse when mouse leaves", .chinese: "鼠标离开后自动收起"],
        "settings.cursorBillingMode": [.english: "Cursor Billing Mode", .chinese: "Cursor 计费模式"],
        "cursor.billingMode.api": [.english: "API Mode", .chinese: "API 模式"],
        "cursor.billingMode.auto": [.english: "Auto Mode", .chinese: "Auto 模式"],
        "settings.theme": [.english: "Theme Style", .chinese: "外观主题"],
        "theme.waterBall": [.english: "Classic Water Ball", .chinese: "经典水球"],
        "theme.doraemon": [.english: "Doraemon", .chinese: "哆啦A梦"],
        "action.refresh": [.english: "Refresh", .chinese: "刷新"],
        "action.pin": [.english: "Pin on top", .chinese: "置顶"],
        "action.settings": [.english: "Settings", .chinese: "设置"],
        "action.language": [.english: "Switch language", .chinese: "切换语言"],
        "action.quit": [.english: "Quit", .chinese: "退出"],
        "action.close": [.english: "Close", .chinese: "关闭"],
        "action.expand": [.english: "Expand", .chinese: "展开"],
        "action.switchTool": [.english: "Switch AI Tool", .chinese: "切换 AI 工具"],
        "interval.seconds": [.english: "sec", .chinese: "秒"],
        "interval.minutes": [.english: "min", .chinese: "分钟"],
        "time.days": [.english: "d", .chinese: "天"],
        "time.hours": [.english: "h", .chinese: "小时"],
        "time.minutes": [.english: "m", .chinese: "分"]
    ]
}
