import SwiftUI

/// 圆形水球：水位高度对应剩余百分比，球心显示「P% Left」。
/// 水面默认正弦晃动，可由设置关闭（关闭则静态水位）。
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

    init(percent: Double, leftLabel: String, waveEnabled: Bool, color: Color, size: CGFloat = 96) {
        self.percent = percent
        self.leftLabel = leftLabel
        self.waveEnabled = waveEnabled
        self.color = color
        self.size = size
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
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
        )
        .frame(width: size, height: size)
    }

    private var label: some View {
        VStack(spacing: 0) {
            Text("\(Int(percent.rounded()))%")
                .font(.system(size: size * (22.0 / 96.0), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(leftLabel)
                .font(.system(size: size * (10.0 / 96.0), weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
    }

    private func waterCanvas(phase: Double, animated: Bool) -> some View {
        Canvas { context, size in
            let circle = Path(ellipseIn: CGRect(origin: .zero, size: size))
            context.clip(to: circle)

            // 球体底色。
            context.fill(circle, with: .color(color.opacity(0.15)))

            let clamped = min(100, max(0, percent))
            let level = (1 - clamped / 100) * size.height
            let amplitude = animated ? max(2.0, size.height * 0.035) : 0

            // 两层正弦波叠加，增加液态层次。
            context.fill(wavePath(size: size, level: level, amplitude: amplitude,
                                   phase: phase * 1.6, wavelength: size.width * 1.1),
                         with: .color(color.opacity(0.35)))
            context.fill(wavePath(size: size, level: level, amplitude: amplitude * 0.7,
                                   phase: phase * 2.3 + .pi, wavelength: size.width * 0.9),
                         with: .color(color.opacity(0.55)))
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
}
