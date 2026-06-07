import Foundation

/// 将各计费模型的原始数据归一化为 `QuotaSnapshot` 的纯函数集合。
/// 这里只做计算、不做网络/IO，便于单元测试。
enum QuotaNormalizer {

    // MARK: - Legacy（按请求次数）

    struct LegacyInput {
        var numRequests: Int
        var maxRequestUsage: Int
        /// `startOfMonth` ISO8601 字符串，可能带毫秒与时区。
        var startOfMonth: String?
        var planName: String?
    }

    static func legacy(_ input: LegacyInput,
                       calendar: Calendar = .current,
                       requestsUnit: String = "requests") -> QuotaSnapshot {
        let max = Swift.max(input.maxRequestUsage, 0)
        let used = Swift.max(input.numRequests, 0)
        let remainingPercent: Double
        if max > 0 {
            remainingPercent = Double(Swift.max(max - used, 0)) / Double(max) * 100
        } else {
            remainingPercent = 0
        }

        let primary = "\(used) / \(max) \(requestsUnit)"
        let reset = resetDateFromStartOfMonth(input.startOfMonth, calendar: calendar)

        return QuotaSnapshot(
            remainingPercent: remainingPercent,
            primaryText: primary,
            secondaryText: nil,
            resetAt: reset,
            planName: input.planName,
            mode: .legacy,
            onDemand: nil,
            ledStatus: LEDStatus.from(remainingPercent: remainingPercent)
        )
    }

    /// legacy 重置时间 = `startOfMonth` 加一个计费周期（一个自然月）。
    static func resetDateFromStartOfMonth(_ raw: String?, calendar: Calendar = .current) -> Date? {
        guard let raw = raw, let start = parseISODate(raw) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: start)
    }

    // MARK: - Usage-based（按美元额度）

    struct UsageBasedInput {
        /// 已用百分比（0–100），若服务端直接给出则优先使用。
        var totalPercentUsed: Double?
        /// 剩余金额（美分）。
        var remainingCents: Double?
        /// 额度上限（美分）。
        var limitCents: Double?
        /// `billingCycleEnd` 毫秒时间戳字符串。
        var billingCycleEndMillis: String?
        var planName: String?
        /// on-demand 已用美分。
        var spendLimitUsedCents: Double?
        /// on-demand 上限美分。
        var spendLimitTotalCents: Double?
    }

    static func usageBased(_ input: UsageBasedInput) -> QuotaSnapshot {
        let remainingPercent = computeRemainingPercent(
            totalPercentUsed: input.totalPercentUsed,
            remainingCents: input.remainingCents,
            limitCents: input.limitCents
        )

        let primary: String
        if let remainingCents = input.remainingCents {
            primary = "$\(formatDollars(remainingCents / 100)) left"
        } else if let limit = input.limitCents, let used = input.totalPercentUsed {
            let remaining = limit * (1 - used / 100)
            primary = "$\(formatDollars(remaining / 100)) left"
        } else {
            primary = "—"
        }

        let reset = dateFromMillisString(input.billingCycleEndMillis)

        var onDemand: OnDemandUsage?
        if let limit = input.spendLimitTotalCents, limit > 0 {
            onDemand = OnDemandUsage(
                usedDollars: (input.spendLimitUsedCents ?? 0) / 100,
                limitDollars: limit / 100
            )
        }

        return QuotaSnapshot(
            remainingPercent: remainingPercent,
            primaryText: primary,
            secondaryText: nil,
            resetAt: reset,
            planName: input.planName,
            mode: .usageBased,
            onDemand: onDemand,
            ledStatus: LEDStatus.from(remainingPercent: remainingPercent)
        )
    }

    static func computeRemainingPercent(totalPercentUsed: Double?,
                                        remainingCents: Double?,
                                        limitCents: Double?) -> Double {
        if let used = totalPercentUsed {
            return clamp(100 - used)
        }
        if let remaining = remainingCents, let limit = limitCents, limit > 0 {
            return clamp(remaining / limit * 100)
        }
        return 0
    }

    /// 判定 usage-based 是否生效：存在有效 `planUsage`（limit > 0 或可用百分比）。
    static func isUsageBasedActive(limitCents: Double?, totalPercentUsed: Double?) -> Bool {
        if let limit = limitCents, limit > 0 { return true }
        if let used = totalPercentUsed, used >= 0, (limitCents ?? 0) > 0 { return true }
        return false
    }

    // MARK: - Helpers

    static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    static func formatDollars(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func dateFromMillisString(_ raw: String?) -> Date? {
        guard let raw = raw, let millis = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFractional, plain]
    }()

    /// 灵活解析时间：支持 ISO8601 字符串、秒/毫秒 epoch（数字或字符串）。
    static func dateFromFlexible(_ value: Any?) -> Date? {
        if let s = value as? String {
            if let d = parseISODate(s) { return d }
            if let n = Double(s) { return dateFromEpoch(n) }
            return nil
        }
        if let n = value as? Double { return dateFromEpoch(n) }
        if let n = value as? Int { return dateFromEpoch(Double(n)) }
        if let n = value as? NSNumber { return dateFromEpoch(n.doubleValue) }
        return nil
    }

    /// 按量级判定秒还是毫秒。
    static func dateFromEpoch(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value > 1_000_000_000_000 ? value / 1000 : value)
    }

    static func parseISODate(_ raw: String) -> Date? {
        for formatter in isoFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        // 兜底：纯数字（秒或毫秒时间戳）。
        if let millis = Double(raw) {
            return Date(timeIntervalSince1970: millis > 1_000_000_000_000 ? millis / 1000 : millis)
        }
        return nil
    }
}
