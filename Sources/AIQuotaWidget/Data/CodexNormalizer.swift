import Foundation

/// 将 Codex `account/rateLimits/read` 返回归一化为统一 `QuotaSnapshot` 的纯函数。
/// 主维度取 5h 窗口（remaining = 100 - usedPercent），7d 进 `secondaryWindows`。
enum CodexNormalizer {

    struct Input {
        var primaryUsedPercent: Double
        var primaryResetAt: Date?
        /// 新版返回的主窗口时长（分钟），用于动态窗口名；nil 时回退硬编码 "5h"。
        var primaryWindowDurationMins: Int?
        var secondaryUsedPercent: Double?
        var secondaryResetAt: Date?
        /// 新版返回的次窗口时长（分钟），用于动态窗口名；nil 时回退硬编码 "7d"。
        var secondaryWindowDurationMins: Int?
        var planType: String?
        /// 新版多 bucket：主 bucket 以外的额外限额（如 codex_bengalfox）。
        var extraBuckets: [ExtraBucket] = []
    }

    /// 非主 bucket 的限额信息（如 codex_bengalfox）。
    struct ExtraBucket {
        var name: String
        var primaryUsedPercent: Double
        var primaryResetAt: Date?
        var primaryWindowDurationMins: Int?
    }

    static func make(_ input: Input) -> QuotaSnapshot {
        let remaining = QuotaNormalizer.clamp(100 - input.primaryUsedPercent)
        let windowName = formatWindowDuration(input.primaryWindowDurationMins)
            ?? CodexConfig.primaryWindowName
        let primaryText = "\(windowName) · \(Int(remaining.rounded()))% left"

        var secondary: [QuotaWindow] = []
        if let su = input.secondaryUsedPercent {
            let secondaryRemaining = QuotaNormalizer.clamp(100 - su)
            let secName = formatWindowDuration(input.secondaryWindowDurationMins)
                ?? CodexConfig.secondaryWindowName
            secondary.append(
                QuotaWindow(
                    name: secName,
                    remainingPercent: secondaryRemaining,
                    resetAt: input.secondaryResetAt,
                    ledStatus: LEDStatus.from(remainingPercent: secondaryRemaining)
                )
            )
        }

        for bucket in input.extraBuckets {
            let rem = QuotaNormalizer.clamp(100 - bucket.primaryUsedPercent)
            let bName: String
            if let mins = bucket.primaryWindowDurationMins {
                bName = "\(bucket.name) (\(formatWindowDuration(mins) ?? "\(mins)m"))"
            } else {
                bName = bucket.name
            }
            secondary.append(
                QuotaWindow(
                    name: bName,
                    remainingPercent: rem,
                    resetAt: bucket.primaryResetAt,
                    ledStatus: LEDStatus.from(remainingPercent: rem)
                )
            )
        }

        return QuotaSnapshot(
            remainingPercent: remaining,
            primaryText: primaryText,
            secondaryText: nil,
            resetAt: input.primaryResetAt,
            planName: input.planType.map(normalizePlan),
            mode: .unknown,
            onDemand: nil,
            secondaryWindows: secondary.isEmpty ? nil : secondary,
            ledStatus: LEDStatus.from(remainingPercent: remaining)
        )
    }

    /// plus -> Plus, pro -> Pro。
    static func normalizePlan(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// 将分钟数转为人类可读窗口名：300 → "5h"、10080 → "7d"、90 → "1.5h"、60 → "1h"。
    static func formatWindowDuration(_ mins: Int?) -> String? {
        guard let mins = mins, mins > 0 else { return nil }
        if mins >= 1440 && mins % 1440 == 0 {
            return "\(mins / 1440)d"
        }
        if mins >= 60 && mins % 60 == 0 {
            return "\(mins / 60)h"
        }
        if mins >= 60 {
            let h = Double(mins) / 60.0
            let formatted = h.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(h))" : String(format: "%.1f", h)
            return "\(formatted)h"
        }
        return "\(mins)m"
    }
}
