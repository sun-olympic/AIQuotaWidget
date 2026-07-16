import Foundation
import Combine

/// UI 消费的额度展示状态。
enum WidgetState: Equatable {
    case loading
    case loaded(QuotaSnapshot)
    case notLoggedIn
    case needsReLogin
    case notInstalled
    case error(String)
}

/// 串联数据层与 UI：三来源各自独立刷新与状态，互不影响（单来源失效隔离）。
@MainActor
final class QuotaService: ObservableObject {

    @Published private(set) var cursorState: WidgetState = .loading
    @Published private(set) var codexState: WidgetState = .loading
    @Published private(set) var antigravityState: WidgetState = .loading
    @Published private(set) var claudecodeState: WidgetState = .loading
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private let settings: AppSettings
    private let credentialStore: CredentialStore
    private let fetchSnapshotOverride: ((ProductTab) async throws -> QuotaSnapshot)?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var tasks: [ProductTab: Task<Void, Never>] = [:]
    private var refreshIDs: [ProductTab: UUID] = [:]
    /// 启动后是否还允许把默认 Tab 自动落到一个可用来源（用户手动切换后、或首轮刷新结束后禁用）。
    private var autoSelectArmed = true
    /// 首轮尚未返回的来源；全部返回后定格默认 Tab，避免后续瞬时失效误切。
    private var initialPending: Set<ProductTab> = []

    init(settings: AppSettings,
         credentialStore: CredentialStore = CredentialStore(),
         fetchSnapshotOverride: ((ProductTab) async throws -> QuotaSnapshot)? = nil) {
        self.settings = settings
        self.credentialStore = credentialStore
        self.fetchSnapshotOverride = fetchSnapshotOverride

        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in self?.rescheduleTimer() }
            .store(in: &cancellables)

        // Tab 变化（含用户点击与自动选择）：刷新该来源（仅优先刷新可见 Tab）并重置定时器。
        settings.$selectedTab
            .dropFirst()
            .sink { [weak self] tab in
                self?.refresh(tab)
                self?.rescheduleTimer()
            }
            .store(in: &cancellables)

        settings.$antigravityDefaultModelId
            .dropFirst()
            .sink { [weak self] _ in
                self?.refresh(.antigravity)
            }
            .store(in: &cancellables)

        settings.$coarseModelGrouping
            .dropFirst()
            .sink { [weak self] _ in
                self?.refresh(.antigravity)
            }
            .store(in: &cancellables)

        settings.$cursorBillingMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.refresh(.cursor)
            }
            .store(in: &cancellables)
    }

    /// 用户主动点击 Tab：永久禁用自动默认选择，并切换。
    func userSelect(_ tab: ProductTab) {
        autoSelectArmed = false
        settings.selectedTab = tab
    }

    func state(for tab: ProductTab) -> WidgetState {
        switch tab {
        case .cursor: return cursorState
        case .codex: return codexState
        case .antigravity: return antigravityState
        case .claudecode: return claudecodeState
        }
    }

    func start() {
        // 启动刷新全部来源（用于判定可用性与默认 Tab 落点），各自独立、互不阻塞。
        initialPending = Set(settings.enabledTabs)
        for tab in settings.enabledTabs { refresh(tab) }
        rescheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        refreshIDs.removeAll()
    }

    /// 手动刷新：立即刷新当前可见 Tab 并重置定时器。
    func refreshNow() {
        Task {
            await AntigravityCache.shared.clear()
            refresh(settings.selectedTab)
        }
        rescheduleTimer()
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        let interval = settings.refreshInterval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh(self.settings.selectedTab) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh(_ tab: ProductTab) {
        let refreshID = UUID()
        refreshIDs[tab] = refreshID
        tasks[tab]?.cancel()
        tasks[tab] = Task { [weak self] in
            await self?.performRefresh(for: tab, refreshID: refreshID)
        }
    }

    private func isCurrentRefresh(_ refreshID: UUID, for tab: ProductTab) -> Bool {
        refreshIDs[tab] == refreshID && !Task.isCancelled
    }

    private func setState(_ state: WidgetState, for tab: ProductTab) {
        switch tab {
        case .cursor: cursorState = state
        case .codex: codexState = state
        case .antigravity: antigravityState = state
        case .claudecode: claudecodeState = state
        }
        if case .loaded = state { lastUpdated = Date() }

        // 仅在首轮内参与默认 Tab 落点；首轮全部返回后定格，避免后续瞬时失效误切。
        if initialPending.contains(tab) {
            initialPending.remove(tab)
            maybeAutoSelectDefault()
            if initialPending.isEmpty { autoSelectArmed = false }
        }
    }

    /// 启动时若当前选中来源未就绪而存在已加载来源，则自动切到该可用来源（仅一次）。
    private func maybeAutoSelectDefault() {
        guard autoSelectArmed else { return }
        if case .loaded = state(for: settings.selectedTab) { return }
        // 仅在启用的 Tab 中且就绪的来源中自动选择
        for tab in settings.enabledTabs where tab != settings.selectedTab {
            if case .loaded = state(for: tab) {
                autoSelectArmed = false
                settings.selectedTab = tab
                return
            }
        }
    }

    private func performRefresh(for tab: ProductTab, refreshID: UUID) async {
        if settings.selectedTab == tab { isRefreshing = true }
        defer {
            if isCurrentRefresh(refreshID, for: tab) {
                tasks[tab] = nil
                refreshIDs[tab] = nil
                if settings.selectedTab == tab { isRefreshing = false }
            }
        }

        do {
            var snapshot: QuotaSnapshot
            if let fetchSnapshotOverride {
                snapshot = try await fetchSnapshotOverride(tab)
            } else {
                switch tab {
                case .cursor:
                    snapshot = try await fetchCursor()
                case .codex:
                    snapshot = try await CodexProvider(settings: settings).fetch()
                    let codexRecent = Self.readCodexRecentTurns()
                    if !codexRecent.isEmpty { snapshot.recentRequests = codexRecent }
                case .antigravity:
                    snapshot = try await AntigravityProvider(
                        defaultModelOverride: settings.antigravityDefaultModelId,
                        coarseModelGrouping: settings.coarseModelGrouping
                    ).fetch()
                case .claudecode:
                    snapshot = try await ClaudeCodeProvider().fetch()
                }
            }
            guard isCurrentRefresh(refreshID, for: tab) else { return }
            setState(.loaded(snapshot), for: tab)
        } catch QuotaError.needsReLogin {
            guard isCurrentRefresh(refreshID, for: tab) else { return }
            setState(.needsReLogin, for: tab)
        } catch QuotaError.notInstalled {
            guard isCurrentRefresh(refreshID, for: tab) else { return }
            setState(.notInstalled, for: tab)
        } catch QuotaError.notLoggedIn {
            guard isCurrentRefresh(refreshID, for: tab) else { return }
            setState(.notLoggedIn, for: tab)
        } catch {
            guard isCurrentRefresh(refreshID, for: tab) else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            setState(.error(Redaction.redact(message)), for: tab)
        }
    }

    private func fetchCursor() async throws -> QuotaSnapshot {
        let credentials: CursorCredentials
        do {
            credentials = try credentialStore.load()
        } catch {
            throw QuotaError.notLoggedIn
        }
        let client = AuthorizedHTTPClient(
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken
        )
        let provider = CursorProvider(
            client: client,
            membershipType: credentials.membershipType,
            billingMode: settings.cursorBillingMode
        )
        var snapshot = try await provider.fetch()
        let recent = await Self.fetchCursorRecentRequests(client: client)
        if !recent.isEmpty { snapshot.recentRequests = recent }
        return snapshot
    }

    /// gRPC 端点拉取最近 N 条请求（best-effort，失败不影响主流程）。
    private static func fetchCursorRecentRequests(client: AuthorizedHTTPClient) async -> [RecentRequest] {
        guard let url = URL(string: CursorDashboardAPI.getFilteredUsageEvents) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "page": 1,
            "pageSize": CursorDashboardAPI.recentPageSize
        ])
        do {
            let data = try await client.send(request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["usageEventsDisplay"] as? [[String: Any]] else { return [] }
            return events.compactMap { Self.parseUsageEvent($0) }
        } catch { return [] }
    }

    private static func parseUsageEvent(_ event: [String: Any]) -> RecentRequest? {
        guard let model = event["model"] as? String,
              let tsStr = event["timestamp"] as? String,
              let tsMs = Double(tsStr) else { return nil }
        let tok = event["tokenUsage"] as? [String: Any]
        return RecentRequest(
            id: "\(tsStr)-\(model)",
            model: model,
            timestamp: Date(timeIntervalSince1970: tsMs / 1000),
            inputTokens: tok?["inputTokens"] as? Int ?? 0,
            outputTokens: tok?["outputTokens"] as? Int ?? 0,
            cacheReadTokens: tok?["cacheReadTokens"] as? Int ?? 0,
            cacheWriteTokens: tok?["cacheWriteTokens"] as? Int ?? 0
        )
    }

    // MARK: - Codex session 日志解析

    /// 从最近的 Codex session JSONL 中提取 per-turn token 消耗（累积差值）。
    private static func readCodexRecentTurns() -> [RecentRequest] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".codex/sessions")
        guard fm.fileExists(atPath: sessionsDir.path) else { return [] }

        let model = readCodexModel(home: home)

        // 按修改时间倒序找最近的 session 文件
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [(URL, Date)] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                candidates.append((url, date))
            }
        }
        candidates.sort { $0.1 > $1.1 }

        // 最多扫描最近 3 个 session 文件，凑齐 5 条
        var results: [RecentRequest] = []
        for (url, _) in candidates.prefix(3) {
            let turns = parseTurnsFromSession(url: url, model: model)
            results.append(contentsOf: turns)
            if results.count >= 5 { break }
        }

        // 按时间倒序，取最近 5 条
        results.sort { $0.timestamp > $1.timestamp }
        return Array(results.prefix(5))
    }

    nonisolated private static func readCodexModel(home: URL) -> String {
        let configPath = home.appendingPathComponent(".codex/config.toml").path
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return "Codex" }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("model") && trimmed.contains("=") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                }
            }
        }
        return "Codex"
    }

    nonisolated private static func parseTurnsFromSession(url: URL, model fallbackModel: String) -> [RecentRequest] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var currentModel = fallbackModel
        var turns: [RecentRequest] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }

            let eventType = (obj["type"] as? String) ?? (payload["type"] as? String) ?? ""

            if eventType == "turn_context" || eventType == "session_meta",
               let m = payload["model"] as? String, !m.isEmpty {
                currentModel = m
            }

            guard eventType == "token_count" || (payload["type"] as? String) == "token_count",
                  let tsStr = obj["timestamp"] as? String,
                  let ts = QuotaNormalizer.parseISODate(tsStr),
                  let info = payload["info"] as? [String: Any],
                  let lastUsage = info["last_token_usage"] as? [String: Any] else { continue }

            let input = lastUsage["input_tokens"] as? Int ?? 0
            let output = lastUsage["output_tokens"] as? Int ?? 0
            let cached = lastUsage["cached_input_tokens"] as? Int ?? 0
            guard input + output > 0 else { continue }

            turns.append(RecentRequest(
                id: "codex-\(ts.timeIntervalSince1970)",
                model: currentModel,
                timestamp: ts,
                inputTokens: max(0, input - cached),
                outputTokens: output,
                cacheReadTokens: cached,
                cacheWriteTokens: 0
            ))
        }
        return turns
    }

    /// 读取最近 N 天所有 Codex session 的 per-turn token 消耗，用于导出 CSV。
    nonisolated static func readCodexAllTurns(daysBack: Int = 30) -> [RecentRequest] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let sessionsDir = home.appendingPathComponent(".codex/sessions")
        guard fm.fileExists(atPath: sessionsDir.path) else { return [] }

        let model = readCodexModel(home: home)
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()

        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [RecentRequest] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < cutoff { continue }
            results.append(contentsOf: parseTurnsFromSession(url: url, model: model))
        }
        results.sort { $0.timestamp > $1.timestamp }
        return results.filter { $0.timestamp >= cutoff }
    }

    #if DEBUG
    func setTestState(_ state: WidgetState, for tab: ProductTab) {
        setState(state, for: tab)
    }
    #endif
}
