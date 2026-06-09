import SwiftUI

/// 水球视图：水位高度对应剩余百分比，球心显示「P% Left」或请求次数。
struct WaterBallView: View {
    /// 剩余百分比 0–100。
    let percent: Double
    /// 「Left / 剩余」文案。
    let leftLabel: String
    /// 是否启用晃动动画。
    let waveEnabled: Bool
    /// 主色（随 LED 状态变化）。
    let color: Color
    /// 水球尺寸。
    let size: CGFloat
    /// 外观主题。
    let theme: WidgetTheme
    /// 自定义中心文本（例如 "238/500"），如提供则不显示百分比和左下文案。
    let centerTextOverride: String?

    init(percent: Double, leftLabel: String, waveEnabled: Bool, color: Color, size: CGFloat = 96, theme: WidgetTheme = .waterBall, centerTextOverride: String? = nil) {
        self.percent = percent
        self.leftLabel = leftLabel
        self.waveEnabled = waveEnabled
        self.color = color
        self.size = size
        self.theme = theme
        self.centerTextOverride = centerTextOverride
    }

    var body: some View {
        ZStack {
            if waveEnabled {
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    waterCanvas(phase: phase, animated: true)
                }
            } else {
                waterCanvas(phase: 0, animated: false)
            }
            label
        }
        .overlay(
            borderOverlay
        )
        .frame(width: size, height: size)
    }

    private var borderOverlay: some View {
        WaterBallView.silhouettePath(for: theme, in: CGRect(x: 0, y: 0, width: size, height: size))
            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
    }

    private var label: some View {
        let hasOverride = centerTextOverride != nil
        let mainFontSize = hasOverride ? (size * (17.0 / 96.0)) : (size * (22.0 / 96.0))
        return VStack(spacing: 0) {
            Text(centerTextOverride ?? "\(Int(percent.rounded()))%")
                .font(.system(size: mainFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !hasOverride {
                Text(leftLabel)
                    .font(.system(size: size * (10.0 / 96.0), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
    }

    private func waterCanvas(phase: Double, animated: Bool) -> some View {
        Canvas { context, size in
            let clipPath = WaterBallView.silhouettePath(for: theme, in: CGRect(origin: .zero, size: size))
            let containerHeight = size.height
            let containerYStart: CGFloat = 0
            
            context.clip(to: clipPath)
            context.fill(clipPath, with: .color(color.opacity(0.15)))

            let clamped = min(100, max(0, percent))
            let level = containerYStart + (1 - clamped / 100) * containerHeight
            let amplitude = animated ? max(2.0, containerHeight * 0.035) : 0

            let op1 = 0.35
            let op2 = 0.55

            context.fill(wavePath(size: size, level: level, amplitude: amplitude,
                                   phase: phase * 1.6, wavelength: size.width * 1.1),
                         with: .color(color.opacity(op1)))
            context.fill(wavePath(size: size, level: level, amplitude: amplitude * 0.7,
                                   phase: phase * 2.3 + .pi, wavelength: size.width * 0.9),
                         with: .color(color.opacity(op2)))
        }
    }

    private func wavePath(size: CGSize, level: CGFloat, amplitude: CGFloat,
                           phase: Double, wavelength: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: level))
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= size.width {
            let relative = Double(x / max(wavelength, 1)) * 2 * .pi
            let y = level + amplitude * CGFloat(sin(relative + phase))
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    /// 根据主题类型获取全身形象的外形 Path 轮廓。
    static func silhouettePath(for theme: WidgetTheme, in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }
}
