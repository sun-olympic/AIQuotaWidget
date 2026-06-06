import Foundation

struct AntigravityRawData: Equatable {
    let models: [AntigravityNormalizer.Model]
    let defaultModelId: String?
}

/// 轻量缓存，避免频繁拉取（5 分钟，TTL 见 AntigravityConfig.cacheTTL）。
actor AntigravityCache {
    static let shared = AntigravityCache()
    private var entry: (timestamp: Date, data: AntigravityRawData)?

    func get() -> AntigravityRawData? {
        guard let entry = entry, Date().timeIntervalSince(entry.timestamp) < AntigravityConfig.cacheTTL else {
            return nil
        }
        return entry.data
    }

    func set(_ data: AntigravityRawData) {
        entry = (Date(), data)
    }

    func clear() {
        entry = nil
    }
}

/// Antigravity 额度 provider：连接 IDE 内运行的 Codeium 系 `language_server` 本地 Connect 接口，
/// 调 `GetAvailableModels`（内部已认证并缓存代理云端 FetchAvailableModels），解析各模型额度。
struct AntigravityProvider: QuotaProvider {
    let productName = "Antigravity"
    let defaultModelOverride: String?
    let coarseModelGrouping: Bool

    init(defaultModelOverride: String? = nil, coarseModelGrouping: Bool = false) {
        self.defaultModelOverride = defaultModelOverride
        self.coarseModelGrouping = coarseModelGrouping
    }

    func fetch() async throws -> QuotaSnapshot {
        if let cached = await AntigravityCache.shared.get() {
            let activeDefaultId = defaultModelOverride ?? cached.defaultModelId
            if let snapshot = AntigravityNormalizer.make(models: cached.models, defaultModelId: activeDefaultId, coarseGrouping: coarseModelGrouping) {
                return snapshot
            }
        }

        // 本地优先：连得上则不发任何外部网络请求。
        if let raw = try? await fetchViaLocalServer() {
            await AntigravityCache.shared.set(raw)
            let activeDefaultId = defaultModelOverride ?? raw.defaultModelId
            if let snapshot = AntigravityNormalizer.make(models: raw.models, defaultModelId: activeDefaultId, coarseGrouping: coarseModelGrouping) {
                return snapshot
            }
        }

        // 云模式回退（当前缺 Antigravity 专属 OAuth client，多数情况下不可用）。
        if let raw = try await fetchViaCloud() {
            await AntigravityCache.shared.set(raw)
            let activeDefaultId = defaultModelOverride ?? raw.defaultModelId
            if let snapshot = AntigravityNormalizer.make(models: raw.models, defaultModelId: activeDefaultId, coarseGrouping: coarseModelGrouping) {
                return snapshot
            }
        }

        // 本地连不上且无有效云端凭证 → 未登录/未就绪引导态。
        throw QuotaError.notLoggedIn
    }

    // MARK: - 本地模式

    private func fetchViaLocalServer() async throws -> AntigravityRawData? {
        guard let server = AntigravityLocalServer.discover() else { return nil }

        let session = LocalhostInsecureSession.make(timeout: AntigravityConfig.requestTimeout)
        // 进程可能监听多个端口，HTTPS Connect 接口只在其中之一，逐个尝试。
        for port in server.ports {
            guard let url = URL(string: "https://127.0.0.1:\(port)\(AntigravityConfig.getAvailableModelsPath)") else {
                continue
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(server.csrfToken, forHTTPHeaderField: AntigravityConfig.csrfHeaderName)
            request.httpBody = Data("{}".utf8)

            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                continue
            }
            if let raw = Self.parseRawData(data) {
                return raw
            }
        }
        return nil
    }

    // MARK: - 云模式（回退）

    private func fetchViaCloud() async throws -> AntigravityRawData? {
        guard let creds = AntigravityCredentials.load(),
              !AntigravityConfig.oauthClientID.isEmpty,
              let accessToken = try await refreshAccessToken(refreshToken: creds.refreshToken) else {
            return nil
        }
        guard let url = URL(string: AntigravityConfig.fetchModelsURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AntigravityConfig.requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project": creds.projectId])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return Self.parseRawData(data)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String? {
        guard let url = URL(string: AntigravityConfig.oauthTokenURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AntigravityConfig.requestTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": AntigravityConfig.oauthClientID,
            "client_secret": AntigravityConfig.oauthClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = form.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["access_token"] as? String
    }

    // MARK: - 解析（本地/云共用）

    /// 解析 GetAvailableModels / fetchAvailableModels 响应：
    /// `[response.]models.<id>.quotaInfo`（remainingFraction/resetTime/isExhausted）+ `defaultAgentModelId`。
    static func parseRawData(_ data: Data) -> AntigravityRawData? {
        guard let outer = JSONDigger(data) else { return nil }
        // 本地 Connect 响应外层包了一层 "response"；云端直接是顶层。
        let root = outer.dict("response") ?? outer
        guard let modelsDict = root.root["models"] as? [String: Any] else { return nil }

        var models: [AntigravityNormalizer.Model] = []
        for (id, value) in modelsDict {
            guard let modelObj = value as? [String: Any] else { continue }
            let m = JSONDigger(modelObj)
            // 仅保留用户可见模型（带 displayName 且非内部），过滤 chat_xxxx 等内部占位，降低次级列表噪声。
            guard let displayName = m.string("displayName"), !displayName.isEmpty,
                  m.bool("isInternal") != true else { continue }
            let quota = m.dict("quotaInfo")
            // remainingFraction 缺省视为 1（满额）。
            let fraction = quota?.double("remainingFraction") ?? 1
            let reset = quota.flatMap { QuotaNormalizer.dateFromFlexible($0.root["resetTime"]) }
            let exhausted = quota?.bool("isExhausted") ?? false
            models.append(.init(id: id, displayName: displayName, remainingFraction: fraction, resetAt: reset, isExhausted: exhausted))
        }
        guard !models.isEmpty else { return nil }

        let defaultId = root.string("defaultAgentModelId")
        return AntigravityRawData(models: models, defaultModelId: defaultId)
    }
}

/// 本地 Antigravity `language_server` 探测：从进程参数取 CSRF token，用 lsof 取监听端口。
enum AntigravityLocalServer {
    struct Server {
        let csrfToken: String
        let ports: [Int]
    }

    static func discover() -> Server? {
        guard let (pid, csrf) = findProcess() else { return nil }
        let ports = listeningPorts(pid: pid)
        guard !ports.isEmpty else { return nil }
        return Server(csrfToken: csrf, ports: ports)
    }

    /// 在 `ps` 输出中定位 antigravity 的 language_server，返回 (pid, csrfToken)。
    private static func findProcess() -> (pid: Int, csrf: String)? {
        guard let output = run("/bin/ps", ["-axww", "-o", "pid=,args="]) else { return nil }
        for line in output.split(separator: "\n") {
            let s = String(line)
            guard s.contains(AntigravityConfig.localServerExecutableHint),
                  s.lowercased().contains(AntigravityConfig.localServerIdeMarker),
                  let csrf = capture(s, "\(AntigravityConfig.csrfArgName)[ =]([A-Za-z0-9\\-]+)") else {
                continue
            }
            // 行首是 pid。
            let trimmed = s.drop(while: { $0 == " " })
            let pidStr = trimmed.prefix(while: { $0.isNumber })
            guard let pid = Int(pidStr) else { continue }
            return (pid, csrf)
        }
        return nil
    }

    /// lsof 取该进程在回环上的 TCP 监听端口。
    private static func listeningPorts(pid: Int) -> [Int] {
        // 关键：`-a` 把多个筛选条件按 AND 组合，否则 lsof 默认 OR 会返回全机所有监听端口。
        let args = ["-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        guard let output = run("/usr/sbin/lsof", args) ?? run("/usr/bin/lsof", args) else {
            return []
        }
        var ports: [Int] = []
        for line in output.split(separator: "\n") {
            // 形如 ... TCP 127.0.0.1:57531 (LISTEN)
            if let port = capture(String(line), ":([0-9]+) \\(LISTEN\\)").flatMap(Int.init) {
                ports.append(port)
            }
        }
        return Array(Set(ports)).sorted()
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}

/// 接受 127.0.0.1 自签名证书的 URLSession（本地 language_server 用自签名 TLS）。
final class LocalhostInsecureSession: NSObject, URLSessionDelegate {
    static func make(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        return URLSession(configuration: config, delegate: LocalhostInsecureSession(), delegateQueue: nil)
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

/// Antigravity 云端 OAuth 凭证读取（回退用；本机凭证在 `~/.gemini/oauth_creds.json`，但缺专属 OAuth client）。
enum AntigravityCredentials {
    struct Credentials {
        let refreshToken: String
        let projectId: String
    }

    static func load() -> Credentials? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: url), let digger = JSONDigger(data),
              let refresh = digger.string("refresh_token") else {
            return nil
        }
        // project 在该文件中通常缺失；置空，云模式当前不依赖它跑通。
        return Credentials(refreshToken: refresh, projectId: "")
    }
}
