import SwiftUI

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
        let mainFontSize = hasOverride ? (size * (13.0 / 96.0)) : (size * (22.0 / 96.0))
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
        .offset(y: theme == .waterBall ? 0 : size * 0.08)
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

/// 绘制各个角色主题的矢量背景视图。
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
    
    // 矢量全身哆啦A梦 (Doraemon)
    private var doraemonView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 左手
                Circle()
                    .fill(Color.white)
                    .frame(width: w * 0.12, height: w * 0.12)
                    .overlay(Circle().stroke(Color.black, lineWidth: w * 0.01))
                    .offset(x: -w * 0.32, y: h * 0.12)
                
                // 右手
                Circle()
                    .fill(Color.white)
                    .frame(width: w * 0.12, height: w * 0.12)
                    .overlay(Circle().stroke(Color.black, lineWidth: w * 0.01))
                    .offset(x: w * 0.32, y: h * 0.12)

                // Left arm
                Capsule()
                    .fill(Color(red: 0.12, green: 0.53, blue: 0.9))
                    .frame(width: w * 0.12, height: h * 0.18)
                    .rotationEffect(.degrees(30))
                    .offset(x: -w * 0.26, y: h * 0.13)
                
                // Right arm
                Capsule()
                    .fill(Color(red: 0.12, green: 0.53, blue: 0.9))
                    .frame(width: w * 0.12, height: h * 0.18)
                    .rotationEffect(.degrees(-30))
                    .offset(x: w * 0.26, y: h * 0.13)

                // Left foot
                Ellipse()
                    .fill(Color.white)
                    .overlay(Ellipse().stroke(Color.black, lineWidth: w * 0.01))
                    .frame(width: w * 0.24, height: h * 0.12)
                    .offset(x: -w * 0.18, y: h * 0.40)
                
                // Right foot
                Ellipse()
                    .fill(Color.white)
                    .overlay(Ellipse().stroke(Color.black, lineWidth: w * 0.01))
                    .frame(width: w * 0.24, height: h * 0.12)
                    .offset(x: w * 0.18, y: h * 0.40)

                // Torso (blue)
                RoundedRectangle(cornerRadius: w * 0.12)
                    .fill(Color(red: 0.12, green: 0.53, blue: 0.9))
                    .frame(width: w * 0.56, height: h * 0.36)
                    .offset(y: h * 0.20)
                
                // White belly
                Circle()
                    .fill(Color.white)
                    .frame(width: w * 0.44, height: w * 0.44)
                    .offset(y: h * 0.18)
                
                // Pocket
                Path { path in
                    path.addArc(center: CGPoint(x: w * 0.5, y: h * 0.70),
                                radius: w * 0.16,
                                startAngle: .degrees(0),
                                endAngle: .degrees(180),
                                clockwise: false)
                }
                .stroke(Color.black, lineWidth: w * 0.015)

                // Blue head
                Ellipse()
                    .fill(Color(red: 0.12, green: 0.53, blue: 0.9))
                    .frame(width: w * 0.64, height: h * 0.48)
                    .offset(y: -h * 0.18)
                
                // White face
                Ellipse()
                    .fill(Color.white)
                    .frame(width: w * 0.56, height: h * 0.42)
                    .offset(y: -h * 0.14)
                
                // Eyes
                HStack(spacing: w * 0.02) {
                    ZStack {
                        Ellipse().fill(Color.white)
                            .overlay(Ellipse().stroke(Color.black, lineWidth: w * 0.015))
                        Circle().fill(Color.black).frame(width: w * 0.04, height: w * 0.04)
                            .offset(x: w * 0.02, y: 0)
                    }
                    .frame(width: w * 0.16, height: h * 0.20)
                    
                    ZStack {
                        Ellipse().fill(Color.white)
                            .overlay(Ellipse().stroke(Color.black, lineWidth: w * 0.015))
                        Circle().fill(Color.black).frame(width: w * 0.04, height: w * 0.04)
                            .offset(x: -w * 0.02, y: 0)
                    }
                    .frame(width: w * 0.16, height: h * 0.20)
                }
                .offset(y: -h * 0.25)
                
                // Red nose
                Circle()
                    .fill(Color.red)
                    .frame(width: w * 0.11, height: w * 0.11)
                    .offset(y: -h * 0.16)
                    .overlay(
                        Circle().fill(Color.white).frame(width: w * 0.03, height: w * 0.03)
                            .offset(x: -w * 0.015, y: -h * 0.015)
                    )
                
                // Smile and midline
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.39))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.52))
                    
                    path.addArc(center: CGPoint(x: w * 0.5, y: h * 0.36),
                                radius: w * 0.18,
                                startAngle: .degrees(45),
                                endAngle: .degrees(135),
                                clockwise: false)
                }
                .stroke(Color.black, lineWidth: w * 0.018)
                
                // Whiskers
                Path { path in
                    // Left whiskers
                    path.move(to: CGPoint(x: w * 0.36, y: h * 0.33))
                    path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.30))
                    
                    path.move(to: CGPoint(x: w * 0.36, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.38))
                    
                    path.move(to: CGPoint(x: w * 0.36, y: h * 0.43))
                    path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.46))
                    
                    // Right whiskers
                    path.move(to: CGPoint(x: w * 0.64, y: h * 0.33))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.30))
                    
                    path.move(to: CGPoint(x: w * 0.64, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.38))
                    
                    path.move(to: CGPoint(x: w * 0.64, y: h * 0.43))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.46))
                }
                .stroke(Color.black, lineWidth: w * 0.012)
                
                // Collar and bell
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.red)
                        .frame(width: w * 0.48, height: h * 0.05)
                        .offset(y: h * 0.05)
                    
                    ZStack {
                        Circle().fill(Color(red: 0.98, green: 0.85, blue: 0.1))
                            .overlay(Circle().stroke(Color.black, lineWidth: w * 0.01))
                        Rectangle().fill(Color.black).frame(width: w * 0.07, height: h * 0.015)
                            .offset(y: -h * 0.005)
                        Circle().fill(Color.black).frame(width: w * 0.02, height: w * 0.02)
                            .offset(y: h * 0.008)
                    }
                    .frame(width: w * 0.12, height: w * 0.12)
                    .offset(y: h * 0.035)
                }
            }
            .frame(width: w, height: h)
        }
    }
}
