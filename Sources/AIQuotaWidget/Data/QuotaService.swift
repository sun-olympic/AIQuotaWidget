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
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private let settings: AppSettings
    private let credentialStore: CredentialStore
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var tasks: [ProductTab: Task<Void, Never>] = [:]
    /// 启动后是否还允许把默认 Tab 自动落到一个可用来源（用户手动切换后、或首轮刷新结束后禁用）。
    private var autoSelectArmed = true
    /// 首轮尚未返回的来源；全部返回后定格默认 Tab，避免后续瞬时失效误切。
    private var initialPending: Set<ProductTab> = []

    init(settings: AppSettings, credentialStore: CredentialStore = CredentialStore()) {
        self.settings = settings
        self.credentialStore = credentialStore

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
    }

    /// 手动刷新：立即刷新当前可见 Tab 并重置定时器。
    func refreshNow() {
        refresh(settings.selectedTab)
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
        tasks[tab]?.cancel()
        tasks[tab] = Task { [weak self] in
            await self?.performRefresh(for: tab)
        }
    }

    private func setState(_ state: WidgetState, for tab: ProductTab) {
        switch tab {
        case .cursor: cursorState = state
        case .codex: codexState = state
        case .antigravity: antigravityState = state
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

    private func performRefresh(for tab: ProductTab) async {
        if settings.selectedTab == tab { isRefreshing = true }
        defer { if settings.selectedTab == tab { isRefreshing = false } }

        do {
            let snapshot: QuotaSnapshot
            switch tab {
            case .cursor:
                snapshot = try await fetchCursor()
            case .codex:
                snapshot = try await CodexProvider().fetch()
            case .antigravity:
                snapshot = try await AntigravityProvider(defaultModelOverride: settings.antigravityDefaultModelId).fetch()
            }
            setState(.loaded(snapshot), for: tab)
        } catch QuotaError.needsReLogin {
            setState(.needsReLogin, for: tab)
        } catch QuotaError.notInstalled {
            setState(.notInstalled, for: tab)
        } catch QuotaError.notLoggedIn {
            setState(.notLoggedIn, for: tab)
        } catch {
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
        let provider = CursorProvider(client: client, membershipType: credentials.membershipType)
        return try await provider.fetch()
    }
}
