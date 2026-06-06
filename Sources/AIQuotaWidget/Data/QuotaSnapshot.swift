import Foundation

/// 当前生效的计费模型标识。
enum BillingMode: String, Equatable {
    case usageBased
    case legacy
    case unknown
}

/// LED 三色状态。
enum LEDStatus: String, Equatable {
    case green
    case yellow
    case red

    /// 阈值：剩余 < 10% 红、< 20% 黄、≥ 20% 绿。
    static func from(remainingPercent percent: Double) -> LEDStatus {
        if percent < 10 { return .red }
        if percent < 20 { return .yellow }
        return .green
    }
}

/// 次级维度：Codex 的 7d 窗口、Antigravity 的各模型，统一用此结构表达。
/// UI 以「次级条列表」渲染，与主水球共用一套范式。
struct QuotaWindow: Equatable, Identifiable {
    /// 展示名称（如 "7d"、模型名）。
    let name: String
    /// 剩余百分比 0–100。
    let remainingPercent: Double
    /// 该维度重置时间。
    let resetAt: Date?
    /// 是否已耗尽。
    var isExhausted: Bool = false

    var id: String { name }

    var clampedPercent: Double { min(100, max(0, remainingPercent)) }

    /// 阈值与主维度复用同一套（<10 红 / <20 黄 / ≥20 绿）。
    var ledStatus: LEDStatus { LEDStatus.from(remainingPercent: remainingPercent) }
}

/// usage-based 下的 on-demand（按需）预算使用情况，作为独立小条展示。
struct OnDemandUsage: Equatable {
    /// 已使用美元。
    let usedDollars: Double
    /// 预算上限美元（0 表示未设置上限）。
    let limitDollars: Double

    var usedPercent: Double {
        guard limitDollars > 0 else { return 0 }
        return min(100, max(0, usedDollars / limitDollars * 100))
    }
}

/// 供 UI 消费的统一额度快照。两种计费模型的原始返回都会被归一化为此结构。
struct QuotaSnapshot: Equatable {
    /// 剩余百分比，范围 0–100（主维度）。
    var remainingPercent: Double
    /// 主展示文本，如「238 / 500 requests」或「$167.78 left」。
    var primaryText: String
    /// 次级文本（可选），如计费周期说明。
    var secondaryText: String?
    /// 下次重置时间。
    var resetAt: Date?
    /// 计划名称，如 PRO / Ultra。
    var planName: String?
    /// 当前计费模型。
    var mode: BillingMode
    /// usage-based 下的 on-demand 独立展示数据（legacy 下为 nil）。
    var onDemand: OnDemandUsage?
    /// 次级窗口/模型分组（Codex 7d、Antigravity 其余模型）；无则为 nil。
    var secondaryWindows: [QuotaWindow]? = nil

    var ledStatus: LEDStatus {
        LEDStatus.from(remainingPercent: remainingPercent)
    }

    /// 归一化后保证 0–100。
    var clampedPercent: Double {
        min(100, max(0, remainingPercent))
    }
}
