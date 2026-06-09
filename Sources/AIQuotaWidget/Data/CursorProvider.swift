import Foundation

/// Cursor 额度的对外 provider：每次刷新先探测 usage-based，命中则用新模型，否则回退 legacy。
struct CursorProvider: QuotaProvider {
    let productName = "Cursor"
    let client: AuthorizedHTTPClient
    let membershipType: String?
    let billingMode: CursorBillingMode

    private var planName: String? {
        guard let m = membershipType, !m.isEmpty else { return nil }
        // pro -> PRO, ultra -> Ultra
        if m.lowercased() == "pro" { return "PRO" }
        return m.prefix(1).uppercased() + m.dropFirst()
    }

    func fetch() async throws -> QuotaSnapshot {
        let usageBased = CursorUsageBasedProvider(
            client: client,
            fallbackPlanName: planName,
            billingMode: billingMode
        )
        // 只有接口明确返回“当前账号未启用 usage-based”时才回退 legacy；其它错误继续暴露。
        if let snapshot = try await usageBased.fetchActive() {
            return snapshot
        }
        // 回退 legacy。
        let legacy = CursorLegacyProvider(client: client, planName: planName)
        return try await legacy.fetch()
    }
}
