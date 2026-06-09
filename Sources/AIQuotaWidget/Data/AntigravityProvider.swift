import Foundation

struct AntigravityRawData: Equatable {
    let models: [AntigravityNormalizer.Model]
    let defaultModelId: String?
    var planName: String? = nil
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

protocol AntigravityRawDataSource {
    func fetchRawData() async throws -> AntigravityRawData?
}

/// Antigravity 额度 provider：连接 IDE 内运行的 Codeium 系 `language_server` 本地 Connect 接口，
/// 调 `GetAvailableModels`（内部已认证并缓存代理云端 FetchAvailableModels），解析各模型额度。
struct AntigravityProvider: QuotaProvider {
    let productName = "Antigravity"
    let defaultModelOverride: String?
    let coarseModelGrouping: Bool
    private let localSource: any AntigravityRawDataSource
    private let cloudSource: any AntigravityRawDataSource

    init(defaultModelOverride: String? = nil,
         coarseModelGrouping: Bool = false,
         localSource: any AntigravityRawDataSource = AntigravityLocalClient(),
         cloudSource: any AntigravityRawDataSource = AntigravityCloudClient()) {
        self.defaultModelOverride = defaultModelOverride
        self.coarseModelGrouping = coarseModelGrouping
        self.localSource = localSource
        self.cloudSource = cloudSource
    }

    func fetch() async throws -> QuotaSnapshot {
        if let cached = await AntigravityCache.shared.get() {
            if let snapshot = makeSnapshot(from: cached) {
                return snapshot
            }
        }

        // 本地优先：连得上则不发任何外部网络请求。
        if let raw = try? await localSource.fetchRawData() {
            await AntigravityCache.shared.set(raw)
            if let snapshot = makeSnapshot(from: raw) {
                return snapshot
            }
        }

        // 云模式回退（当前缺 Antigravity 专属 OAuth client，多数情况下不可用）。
        if let raw = try await cloudSource.fetchRawData() {
            await AntigravityCache.shared.set(raw)
            if let snapshot = makeSnapshot(from: raw) {
                return snapshot
            }
        }

        // 本地连不上且无有效云端凭证 → 未登录/未就绪引导态。
        throw QuotaError.notLoggedIn
    }

    private func makeSnapshot(from raw: AntigravityRawData) -> QuotaSnapshot? {
        let activeDefaultId = defaultModelOverride ?? raw.defaultModelId
        return AntigravityNormalizer.make(
            models: raw.models,
            defaultModelId: activeDefaultId,
            coarseGrouping: coarseModelGrouping,
            planName: raw.planName
        )
    }

    /// Compatibility shim for existing tests and callers; parsing now lives in AntigravityPayloadParser.
    static func parseRawData(_ data: Data) -> AntigravityRawData? {
        AntigravityPayloadParser.parseAvailableModels(data)
    }

    /// Compatibility shim for existing tests and callers; parsing now lives in AntigravityPayloadParser.
    static func parsePlanName(from data: Data) -> String? {
        AntigravityPayloadParser.parsePlanName(from: data)
    }
}
