import Foundation

/// 将 Codex `account/rateLimits/read` 返回归一化为统一 `QuotaSnapshot` 的纯函数。
/// 主维度取 5h 窗口（remaining = 100 - usedPercent），7d 进 `secondaryWindows`。
enum CodexNormalizer {

    struct Input {
        var primaryUsedPercent: Double
        var primaryResetAt: Date?
        var secondaryUsedPercent: Double?
        var secondaryResetAt: Date?
        var planType: String?
    }

    static func make(_ input: Input) -> QuotaSnapshot {
        let remaining = QuotaNormalizer.clamp(100 - input.primaryUsedPercent)
        let primaryText = "\(CodexConfig.primaryWindowName) · \(Int(remaining.rounded()))% left"

        var secondary: [QuotaWindow]?
        if let su = input.secondaryUsedPercent {
            secondary = [
                QuotaWindow(
                    name: CodexConfig.secondaryWindowName,
                    remainingPercent: QuotaNormalizer.clamp(100 - su),
                    resetAt: input.secondaryResetAt
                )
            ]
        }

        return QuotaSnapshot(
            remainingPercent: remaining,
            primaryText: primaryText,
            secondaryText: nil,
            resetAt: input.primaryResetAt,
            planName: input.planType.map(normalizePlan),
            mode: .unknown,
            onDemand: nil,
            secondaryWindows: secondary
        )
    }

    /// plus -> Plus, pro -> Pro。
    static func normalizePlan(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
