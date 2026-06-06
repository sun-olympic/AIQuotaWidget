import SwiftUI

/// 倒计时格式化（与本地化单位结合）。
enum Countdown {
    static func format(until date: Date?, now: Date = Date(), settings: AppSettings) -> String {
        guard let date = date else { return settings.t("reset.unknown") }
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return settings.t("reset.unknown") }

        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        let d = settings.t("time.days")
        let h = settings.t("time.hours")
        let m = settings.t("time.minutes")

        if days > 0 { return "\(days)\(d) \(hours)\(h)" }
        if hours > 0 { return "\(hours)\(h) \(minutes)\(m)" }
        return "\(minutes)\(m)"
    }
}

/// 右侧信息块：主额度文本、重置倒计时、计划名称，以及 usage-based 的 on-demand 小条。
struct InfoBlockView: View {
    let snapshot: QuotaSnapshot
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.selectedTab == .antigravity, let models = snapshot.antigravityModels, !models.isEmpty {
                Menu {
                    ForEach(models) { model in
                        Button(action: {
                            settings.antigravityDefaultModelId = model.id
                        }) {
                            HStack {
                                Text(model.name)
                                if model.id == snapshot.activeAntigravityModelId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(snapshot.primaryText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .menuStyle(.borderlessButton)
            } else {
                Text(snapshot.primaryText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text("\(settings.t("reset.in")) \(Countdown.format(until: snapshot.resetAt, settings: settings))")
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.8))

            if let plan = snapshot.planName {
                Text("\(settings.t("plan.label")): \(plan)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let onDemand = snapshot.onDemand {
                onDemandBar(onDemand)
            }
        }
    }

    /// on-demand（spendLimitUsage）作为独立小条，不并入主水位。
    private func onDemandBar(_ usage: OnDemandUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(settings.t("ondemand.label")): $\(String(format: "%.2f", usage.usedDollars)) / $\(String(format: "%.2f", usage.limitDollars))")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.75))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.orange)
                        .frame(width: geo.size.width * CGFloat(usage.usedPercent / 100))
                }
            }
            .frame(height: 4)
        }
    }
}
