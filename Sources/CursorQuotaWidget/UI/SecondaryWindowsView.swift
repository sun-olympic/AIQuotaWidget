import SwiftUI

/// 次级维度条列表：Codex 的 7d 窗口、Antigravity 的其余模型，三来源共用同一渲染范式。
/// 颜色阈值与主水球一致（<10 红 / <20 黄 / ≥20 绿）。
struct SecondaryWindowsView: View {
    let windows: [QuotaWindow]
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(windows) { window in
                    windowBar(window)
                }
            }
        }
        .frame(maxHeight: 56)
    }

    private func windowBar(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(window.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if window.isExhausted {
                    Text(settings.t("window.exhausted"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                } else {
                    Text("\(Int(window.clampedPercent.rounded()))% · \(Countdown.format(until: window.resetAt, settings: settings))")
                        .font(.system(size: 9))
                }
            }
            .foregroundStyle(.white.opacity(0.8))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(window.ledStatus.color)
                        .frame(width: geo.size.width * CGFloat(window.clampedPercent / 100))
                }
            }
            .frame(height: 4)
        }
    }
}
