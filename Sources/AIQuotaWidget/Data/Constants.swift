import Foundation

/// 逆向得到的 Cursor 接口常量集中于此，便于接口变更时快速修补。
/// 免责声明：以下端点与字段均为逆向获取的非官方接口，可能随 Cursor 版本变更而失效。
enum CursorAPI {
    static let host = "https://api2.cursor.sh"

    static let legacyUsage = "\(host)/auth/usage"
    static let getCurrentPeriodUsage = "\(host)/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    static let getPlanInfo = "\(host)/aiserver.v1.DashboardService/GetPlanInfo"
    static let oauthToken = "\(host)/oauth/token"

    /// token 刷新使用的固定 client_id（逆向获取）。
    static let oauthClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    static let requestTimeout: TimeInterval = 15
}

/// `state.vscdb` 中 `ItemTable` 的凭证键名。
enum CredentialKeys {
    static let accessToken = "cursorAuth/accessToken"
    static let refreshToken = "cursorAuth/refreshToken"
    static let cachedEmail = "cursorAuth/cachedEmail"
    static let membershipType = "cursorAuth/stripeMembershipType"
    static let subscriptionStatus = "cursorAuth/stripeSubscriptionStatus"
}

/// 本地 Cursor 数据库相对路径（相对于用户主目录）。
enum LocalPaths {
    static let stateDBRelative = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    static var stateDBURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(stateDBRelative)
    }
}

/// Codex 相关常量（逆向/实验性，`codex app-server` 标注 experimental，随版本可能变更）。
enum CodexConfig {
    static let executableName = "codex"
    static let appServerArgs = ["app-server"]

    static let initializeMethod = "initialize"
    static let rateLimitsMethod = "account/rateLimits/read"

    /// `initialize` 之后、发 rateLimits 之前的握手延迟，规避连接就绪前空响应。
    static let handshakeDelay: TimeInterval = 0.6
    /// 整体取数超时，超时即结束子进程并转引导/错误态，避免阻塞。
    static let timeout: TimeInterval = 8

    /// `~/.codex/auth.json`（app-server 自行用它认证）。
    static let authJSONRelative = ".codex/auth.json"

    /// 常见可执行目录（PATH 之外的兜底搜索）。
    static let extraSearchDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
    ]

    /// 窗口展示名。
    static let primaryWindowName = "5h"
    static let secondaryWindowName = "7d"
}

/// Antigravity 相关常量（逆向/实验性）。
/// 本机实测：Antigravity 内置 Codeium 系 `language_server`，本地暴露 Connect 接口，
/// 内部带缓存地代理云端 `FetchAvailableModels`，自带认证（无需我们管理 OAuth）。
enum AntigravityConfig {
    // MARK: 本地 Language Server（首选）

    /// 进程可执行名（用于在 `ps` 输出中定位 language_server 进程）。
    static let localServerExecutableHint = "language_server"
    /// 进一步确认是 Antigravity（而非其它 Codeium 系 IDE）的参数标记。
    static let localServerIdeMarker = "antigravity"
    /// CSRF token 在进程参数中的标记：`--csrf_token <uuid>`。
    static let csrfArgName = "--csrf_token"
    /// 本地 Connect 方法路径。
    static let getAvailableModelsPath = "/exa.language_server_pb.LanguageServerService/GetAvailableModels"
    /// CSRF 校验所需的请求头名（实测）。
    static let csrfHeaderName = "x-codeium-csrf-token"

    // MARK: 云模式（回退；当前缺 Antigravity 专属 OAuth client，待逆向确认）

    static let oauthTokenURL = "https://oauth2.googleapis.com/token"
    static let fetchModelsURL = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    static let oauthClientID = ""
    static let oauthClientSecret = ""

    static let requestTimeout: TimeInterval = 10
    /// 轻量缓存时长，避免频繁拉取。
    static let cacheTTL: TimeInterval = 300
}
