import Foundation

/// usage-based 美元额度模型：`POST GetCurrentPeriodUsage`（+ `GetPlanInfo` 取计划名）。
struct CursorUsageBasedProvider: QuotaProvider {
    let productName = "Cursor"
    let client: AuthorizedHTTPClient
    let fallbackPlanName: String?
    let billingMode: CursorBillingMode

    func fetch() async throws -> QuotaSnapshot {
        guard let snapshot = try await fetchActive() else {
            throw QuotaError.unsupported
        }
        return snapshot
    }

    /// 拉取并探测：返回 nil 表示当前账号未启用 usage-based（应回退 legacy）。
    func fetchActive() async throws -> QuotaSnapshot? {
        let data = try await postEmpty(CursorAPI.getCurrentPeriodUsage)
        guard let digger = JSONDigger(data) else {
            throw QuotaError.decoding("usage-based decode failed")
        }

        let planUsage = digger.dict("planUsage")
        let limitCents = planUsage?.double("limit")
        let totalPercentUsed = planUsage?.double("totalPercentUsed")

        // 自动探测：无有效 planUsage 即非 usage-based。
        guard QuotaNormalizer.isUsageBasedActive(limitCents: limitCents, totalPercentUsed: totalPercentUsed) else {
            return nil
        }

        let apiPercentUsed = planUsage?.double("apiPercentUsed")
        let autoPercentUsed = planUsage?.double("autoPercentUsed")

        let selectedPercentUsed: Double?
        switch billingMode {
        case .api:
            selectedPercentUsed = apiPercentUsed ?? totalPercentUsed
        case .auto:
            selectedPercentUsed = autoPercentUsed ?? totalPercentUsed
        }

        let remainingCents = planUsage?.double("remaining")
        let calculatedRemainingCents: Double?
        if let limit = limitCents, let used = selectedPercentUsed {
            calculatedRemainingCents = limit * (1 - used / 100)
        } else {
            calculatedRemainingCents = remainingCents
        }

        let billingCycleEnd = digger.string("billingCycleEnd")

        let spend = digger.dict("spendLimitUsage")
        let spendUsed = spend?.double("used") ?? spend?.double("totalUsed")
        let spendLimit = spend?.double("limit")

        let plan = (try? await fetchPlanName()) ?? fallbackPlanName

        return QuotaNormalizer.usageBased(
            .init(totalPercentUsed: selectedPercentUsed,
                  remainingCents: calculatedRemainingCents,
                  limitCents: limitCents,
                  billingCycleEndMillis: billingCycleEnd,
                  planName: plan,
                  spendLimitUsedCents: spendUsed,
                  spendLimitTotalCents: spendLimit)
        )
    }

    private func fetchPlanName() async throws -> String? {
        let data = try await postEmpty(CursorAPI.getPlanInfo)
        guard let digger = JSONDigger(data) else { return nil }
        return digger.string("planName")
            ?? digger.dict("plan")?.string("name")
            ?? fallbackPlanName
    }

    private func postEmpty(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw QuotaError.network("invalid url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)
        return try await client.send(request)
    }
}
