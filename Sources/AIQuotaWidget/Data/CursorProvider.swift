import Foundation

/// Cursor 额度的对外 provider：每次刷新先探测 usage-based，命中则用新模型，否则回退 legacy。
struct CursorProvider: QuotaProvider {
    let productName = "Cursor"
    let client: AuthorizedHTTPClient
    let membershipType: String?

    private var planName: String? {
        guard let m = membershipType, !m.isEmpty else { return nil }
        // pro -> PRO, ultra -> Ultra
        if m.lowercased() == "pro" { return "PRO" }
        return m.prefix(1).uppercased() + m.dropFirst()
    }

    func fetch() async throws -> QuotaSnapshot {
        let usageBased = CursorUsageBasedProvider(client: client, fallbackPlanName: planName)
        // try? 展平 Optional：抛错或返回 nil（非 usage-based）都回退 legacy。
        if let snapshot = try? await usageBased.fetchActive() {
            return snapshot
        }
        // 回退 legacy。
        let legacy = CursorLegacyProvider(client: client, planName: planName)
        return try await legacy.fetch()
    }
}
