import Foundation

/// legacy 请求次数模型：`GET /auth/usage`。
struct CursorLegacyProvider: QuotaProvider {
    let productName = "Cursor"
    let client: AuthorizedHTTPClient
    let planName: String?

    func fetch() async throws -> QuotaSnapshot {
        guard let url = URL(string: CursorAPI.legacyUsage) else {
            throw QuotaError.network("invalid legacy url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await client.send(request)

        guard let digger = JSONDigger(data) else {
            throw QuotaError.decoding("legacy usage decode failed")
        }
        let (num, max) = primaryModelUsage(digger)
        let startOfMonth = digger.string("startOfMonth")

        return QuotaNormalizer.legacy(
            .init(numRequests: num,
                  maxRequestUsage: max,
                  startOfMonth: startOfMonth,
                  planName: planName)
        )
    }

    /// 选取主模型（优先 gpt-4），取其请求数与上限。
    private func primaryModelUsage(_ digger: JSONDigger) -> (Int, Int) {
        let preferredKeys = ["gpt-4", "gpt-4o", "gpt-3.5-turbo"]
        for key in preferredKeys {
            if let model = digger.dict(key),
               let max = model.int("maxRequestUsage"), max > 0 {
                return (model.int("numRequests") ?? 0, max)
            }
        }
        // 兜底：扫描所有子字典，取含 maxRequestUsage 的第一个。
        for (_, value) in digger.root {
            if let model = value as? [String: Any] {
                let d = JSONDigger(model)
                if let max = d.int("maxRequestUsage"), max > 0 {
                    return (d.int("numRequests") ?? 0, max)
                }
            }
        }
        return (0, 0)
    }
}
