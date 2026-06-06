import Foundation

/// 将 Antigravity `fetchAvailableModels` 返回归一化为统一 `QuotaSnapshot` 的纯函数。
/// 主维度取默认模型（remaining = remainingFraction * 100），其余模型进 `secondaryWindows`。
enum AntigravityNormalizer {

    struct Model: Equatable {
        let id: String
        /// 友好显示名（来自接口 label）；缺省时回退到 id。
        var displayName: String? = nil
        /// 0~1。
        let remainingFraction: Double
        let resetAt: Date?
        let isExhausted: Bool

        var name: String { displayName ?? AntigravityNormalizer.displayName(id) }
    }

    static func make(models: [Model], defaultModelId: String?) -> QuotaSnapshot? {
        guard !models.isEmpty else { return nil }

        // 1. 全局按 name 友好名去重
        var uniqueModelsDict: [String: Model] = [:]
        for model in models {
            if let existing = uniqueModelsDict[model.name] {
                if model.id == defaultModelId {
                    uniqueModelsDict[model.name] = model
                } else if existing.id != defaultModelId && model.remainingFraction < existing.remainingFraction {
                    uniqueModelsDict[model.name] = model
                }
            } else {
                uniqueModelsDict[model.name] = model
            }
        }
        let dedupedModels = Array(uniqueModelsDict.values)

        // 2. 确定主维度模型
        let main = dedupedModels.first { $0.id == defaultModelId } ?? dedupedModels[0]
        let remaining = QuotaNormalizer.clamp(main.remainingFraction * 100)
        let primaryText = "\(main.name) · \(Int(remaining.rounded()))%"

        // 3. 构建 secondaryWindows
        var sortedOthers: [QuotaWindow] = []
        for model in dedupedModels.filter({ $0.id != main.id }) {
            sortedOthers.append(QuotaWindow(
                name: model.name,
                remainingPercent: QuotaNormalizer.clamp(model.remainingFraction * 100),
                resetAt: model.resetAt,
                isExhausted: model.isExhausted
            ))
        }
        sortedOthers.sort {
            if abs($0.remainingPercent - $1.remainingPercent) < 0.001 {
                return $0.name < $1.name
            }
            return $0.remainingPercent < $1.remainingPercent
        }

        // 4. 构建用于切换的下拉列表（按友好名排序）
        let switcherModels = dedupedModels.map {
            AntigravityModelInfo(id: $0.id, name: $0.name)
        }.sorted { $0.name < $1.name }

        return QuotaSnapshot(
            remainingPercent: remaining,
            primaryText: primaryText,
            secondaryText: nil,
            resetAt: main.resetAt,
            planName: nil,
            mode: .unknown,
            onDemand: nil,
            secondaryWindows: sortedOthers.isEmpty ? nil : sortedOthers,
            antigravityModels: switcherModels,
            activeAntigravityModelId: main.id
        )
    }

    /// 模型 id 友好显示：取最后一段（去掉 publisher/ 前缀）。
    static func displayName(_ id: String) -> String {
        if let last = id.split(separator: "/").last { return String(last) }
        return id
    }
}
