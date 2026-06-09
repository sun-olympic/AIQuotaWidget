import Foundation

enum AntigravityPayloadParser {
    /// 解析 GetAvailableModels / fetchAvailableModels 响应：
    /// `[response.]models.<id>.quotaInfo`（remainingFraction/resetTime/isExhausted）+ `defaultAgentModelId`。
    static func parseAvailableModels(_ data: Data) -> AntigravityRawData? {
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
            models.append(
                .init(
                    id: id,
                    displayName: displayName,
                    remainingFraction: fraction,
                    resetAt: reset,
                    isExhausted: exhausted
                )
            )
        }
        guard !models.isEmpty else { return nil }

        let rawPlan = root.string("planName")
            ?? root.dict("userState")?.string("tier")
            ?? root.dict("userState")?.string("userTier")
            ?? root.dict("userState")?.string("planName")
            ?? root.string("tier")

        return AntigravityRawData(
            models: models,
            defaultModelId: root.string("defaultAgentModelId"),
            planName: normalizePlanName(rawPlan)
        )
    }

    static func parsePlanName(from data: Data) -> String? {
        guard let root = JSONDigger(data) else { return nil }
        let status = root.dict("userStatus") ?? root
        let rawPlan: String?
        if let tierName = status.dict("userTier")?.string("name"), !tierName.isEmpty {
            rawPlan = tierName
        } else if let planInfoName = status.dict("planStatus")?.dict("planInfo")?.string("planName"),
                  !planInfoName.isEmpty {
            rawPlan = planInfoName
        } else {
            rawPlan = nil
        }

        return normalizePlanName(rawPlan, preserveSpacedNames: true)
    }

    static func normalizePlanName(_ raw: String?, preserveSpacedNames: Bool = false) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "pro":
            return "PRO"
        case "individual":
            return "Individual"
        case "teams":
            return "Teams"
        case "enterprise":
            return "Enterprise"
        default:
            if preserveSpacedNames, raw.contains(" ") {
                return raw
            }
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}

