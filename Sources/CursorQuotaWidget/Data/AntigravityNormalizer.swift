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

        let main = models.first { $0.id == defaultModelId } ?? models[0]
        let remaining = QuotaNormalizer.clamp(main.remainingFraction * 100)
        let primaryText = "\(main.name) · \(Int(remaining.rounded()))%"

        let others = models
            .filter { $0.id != main.id }
            .map {
                QuotaWindow(
                    name: $0.name,
                    remainingPercent: QuotaNormalizer.clamp($0.remainingFraction * 100),
                    resetAt: $0.resetAt,
                    isExhausted: $0.isExhausted
                )
            }
            // 剩余少/已耗尽的排前面，便于一眼看到吃紧的模型。
            .sorted { $0.remainingPercent < $1.remainingPercent }

        return QuotaSnapshot(
            remainingPercent: remaining,
            primaryText: primaryText,
            secondaryText: nil,
            resetAt: main.resetAt,
            planName: nil,
            mode: .unknown,
            onDemand: nil,
            secondaryWindows: others.isEmpty ? nil : others
        )
    }

    /// 模型 id 友好显示：取最后一段（去掉 publisher/ 前缀）。
    static func displayName(_ id: String) -> String {
        if let last = id.split(separator: "/").last { return String(last) }
        return id
    }
}
