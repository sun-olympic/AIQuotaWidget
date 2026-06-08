import SwiftUI
import AppKit

/// 角色主题与水球视图：水位高度对应剩余百分比，球心显示「P% Left」或请求次数。
/// 除经典水球外，哆啦A梦全身角色主题的外轮廓以及水位裁剪皆使用其特有的全身形象外形。
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
            // Underlay theme background
            ThemeBackgroundView(theme: theme, size: size)
            
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
        let mainFontSize = hasOverride ? (size * (13.0 / 96.0)) : (theme == .waterBall ? (size * (22.0 / 96.0)) : (size * (17.0 / 96.0)))
        return VStack(spacing: 0) {
            Text(centerTextOverride ?? "\(Int(percent.rounded()))%")
                .font(.system(size: mainFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !hasOverride {
                Text(leftLabel)
                    .font(.system(size: theme == .waterBall ? (size * (10.0 / 96.0)) : (size * (9.0 / 96.0)), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, theme == .waterBall ? 0 : size * 0.05)
        .padding(.vertical, theme == .waterBall ? 0 : size * 0.03)
        .background(
            theme == .waterBall ? Color.clear : Color.black.opacity(0.35),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
        .offset(y: theme == .waterBall ? 0 : -size * 0.15)
    }

    private func waterCanvas(phase: Double, animated: Bool) -> some View {
        Canvas { context, size in
            let clipPath = WaterBallView.silhouettePath(for: theme, in: CGRect(origin: .zero, size: size))
            let containerHeight = size.height
            let containerYStart: CGFloat = 0
            
            context.clip(to: clipPath)

            // 球体底色（经典水球以及各个主题都填充其专属底色/阴影）。
            if theme == .waterBall {
                context.fill(clipPath, with: .color(color.opacity(0.15)))
            } else {
                context.fill(clipPath, with: .color(color.opacity(0.08)))
            }

            let clamped = min(100, max(0, percent))
            let level = containerYStart + (1 - clamped / 100) * containerHeight
            let amplitude = animated ? max(2.0, containerHeight * 0.035) : 0

            // 两层正弦波叠加，如果是角色主题则微调透明度以保留背景清晰度。
            let op1 = theme == .waterBall ? 0.35 : 0.28
            let op2 = theme == .waterBall ? 0.55 : 0.42

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
        let w = rect.width
        let h = rect.height
        var path = Path()

        switch theme {
        case .waterBall:
            path.addEllipse(in: rect)
            
        case .doraemon:
            let ox = rect.origin.x
            let oy = rect.origin.y
            
            // Head
            let headRect = CGRect(x: ox + w * 0.18, y: oy + h * 0.08, width: w * 0.64, height: h * 0.48)
            path.addPath(Path(ellipseIn: headRect))
            
            // Body / Torso
            let bodyRect = CGRect(x: ox + w * 0.22, y: oy + h * 0.52, width: w * 0.56, height: h * 0.36)
            path.addPath(Path(roundedRect: bodyRect, cornerRadius: w * 0.12))
            
            // Left Hand
            let leftHandRect = CGRect(x: ox + w * 0.12, y: oy + h * 0.56, width: w * 0.12, height: h * 0.12)
            path.addPath(Path(ellipseIn: leftHandRect))
            
            // Right Hand
            let rightHandRect = CGRect(x: ox + w * 0.76, y: oy + h * 0.56, width: w * 0.12, height: h * 0.12)
            path.addPath(Path(ellipseIn: rightHandRect))
            
            // Left Foot
            let leftFootRect = CGRect(x: ox + w * 0.20, y: oy + h * 0.84, width: w * 0.24, height: h * 0.12)
            path.addPath(Path(ellipseIn: leftFootRect))
            
            // Right Foot
            let rightFootRect = CGRect(x: ox + w * 0.56, y: oy + h * 0.84, width: w * 0.24, height: h * 0.12)
            path.addPath(Path(ellipseIn: rightFootRect))
        }

        return path
    }
}

/// 绘制各个角色主题的背景视图。
struct ThemeBackgroundView: View {
    let theme: WidgetTheme
    let size: CGFloat
    
    var body: some View {
        ZStack {
            switch theme {
            case .waterBall:
                EmptyView()
            case .doraemon:
                doraemonView
            }
        }
    }
    
    private var doraemonView: some View {
        Group {
            if let nsImage = loadDoraemonImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(DoraemonClipShape())
            } else {
                DoraemonClipShape()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: size, height: size)
            }
        }
    }

    private func loadDoraemonImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "doraemon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let img = NSImage(named: "doraemon") {
            return img
        }
        let fallbacks = [
            "Resources/doraemon.png",
            "../Resources/doraemon.png",
            "./doraemon.png",
            "/Users/sunqilei/Documents/GitHub/Personal/AIQuotaWidget/Resources/doraemon.png"
        ]
        for path in fallbacks {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return nil
    }
}

struct DoraemonClipShape: Shape {
    func path(in rect: CGRect) -> Path {
        return WaterBallView.silhouettePath(for: .doraemon, in: rect)
    }
}
