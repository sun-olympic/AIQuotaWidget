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
    /// 外观主题。
    let theme: WidgetTheme

    init(percent: Double, leftLabel: String, waveEnabled: Bool, color: Color, size: CGFloat = 96, theme: WidgetTheme = .waterBall) {
        self.percent = percent
        self.leftLabel = leftLabel
        self.waveEnabled = waveEnabled
        self.color = color
        self.size = size
        self.theme = theme
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

    @ViewBuilder
    private var borderOverlay: some View {
        switch theme {
        case .capybara:
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: size * 0.8, height: size * 0.7)
                .offset(y: size * 0.08)
        default:
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
        }
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
        .offset(y: theme == .capybara ? size * 0.08 : 0)
    }

    private func waterCanvas(phase: Double, animated: Bool) -> some View {
        Canvas { context, size in
            let clipPath: Path
            let containerHeight: CGFloat
            let containerYStart: CGFloat
            
            switch theme {
            case .capybara:
                let rect = CGRect(x: size.width * 0.1, y: size.height * 0.23, width: size.width * 0.8, height: size.height * 0.7)
                clipPath = Path(roundedRect: rect, cornerSize: CGSize(width: size.width * 0.2, height: size.width * 0.2))
                containerHeight = size.height * 0.7
                containerYStart = size.height * 0.23
            default:
                clipPath = Path(ellipseIn: CGRect(origin: .zero, size: size))
                containerHeight = size.height
                containerYStart = 0
            }
            
            context.clip(to: clipPath)

            // 球体底色（仅经典水球才填充底色）。
            if theme == .waterBall {
                context.fill(clipPath, with: .color(color.opacity(0.15)))
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
            case .capybara:
                capybaraView
            case .doraemon:
                doraemonView
            case .snowWhite:
                snowWhiteView
            }
        }
    }
    
    // 矢量卡皮巴拉 (Capybara)
    private var capybaraView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 左耳
                Capsule()
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.35))
                    .frame(width: w * 0.12, height: h * 0.16)
                    .rotationEffect(.degrees(-15))
                    .offset(x: -w * 0.34, y: -h * 0.23)
                
                // 右耳
                Capsule()
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.35))
                    .frame(width: w * 0.12, height: h * 0.16)
                    .rotationEffect(.degrees(15))
                    .offset(x: w * 0.34, y: -h * 0.23)

                // 头部/身体轮廓
                RoundedRectangle(cornerRadius: w * 0.2, style: .continuous)
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.35))
                    .frame(width: w * 0.8, height: h * 0.7)
                    .offset(y: h * 0.08)
                
                // 鼻子/嘴部区域
                Capsule()
                    .fill(Color(red: 0.45, green: 0.3, blue: 0.22))
                    .frame(width: w * 0.34, height: h * 0.26)
                    .offset(y: h * 0.18)
                
                // 黑色鼻尖
                Capsule()
                    .fill(Color.black)
                    .frame(width: w * 0.13, height: h * 0.08)
                    .offset(y: h * 0.10)
                
                // 眯眯眼
                HStack(spacing: w * 0.34) {
                    Path { path in
                        path.addArc(center: CGPoint(x: w * 0.05, y: h * 0.05),
                                    radius: w * 0.04,
                                    startAngle: .degrees(180),
                                    endAngle: .degrees(360),
                                    clockwise: false)
                    }
                    .stroke(Color.black, lineWidth: w * 0.03)
                    .frame(width: w * 0.1, height: h * 0.1)
                    
                    Path { path in
                        path.addArc(center: CGPoint(x: w * 0.05, y: h * 0.05),
                                    radius: w * 0.04,
                                    startAngle: .degrees(180),
                                    endAngle: .degrees(360),
                                    clockwise: false)
                    }
                    .stroke(Color.black, lineWidth: w * 0.03)
                    .frame(width: w * 0.1, height: h * 0.1)
                }
                .offset(y: -h * 0.02)
                
                // 腮红
                HStack(spacing: w * 0.52) {
                    Circle().fill(Color.red.opacity(0.35)).frame(width: w * 0.08, height: w * 0.08)
                    Circle().fill(Color.red.opacity(0.35)).frame(width: w * 0.08, height: w * 0.08)
                }
                .offset(y: h * 0.1)
                
                // 经典头顶小橘子
                ZStack {
                    Circle().fill(Color.orange).frame(width: w * 0.2, height: w * 0.2)
                    Capsule().fill(Color.green).frame(width: w * 0.05, height: w * 0.1)
                        .rotationEffect(.degrees(45))
                        .offset(x: w * 0.05, y: -h * 0.08)
                }
                .offset(y: -h * 0.32)
            }
            .frame(width: w, height: h)
        }
    }
    
    // 矢量哆啦A梦 (Doraemon)
    private var doraemonView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.53, blue: 0.9))
                
                Circle()
                    .fill(Color.white)
                    .frame(width: w * 0.85, height: h * 0.8)
                    .offset(y: h * 0.08)
                
                // 眼睛
                HStack(spacing: w * 0.02) {
                    ZStack {
                        Ellipse().fill(Color.white)
                            .overlay(Ellipse().stroke(Color.black, lineWidth: w * 0.015))
                        Circle().fill(Color.black).frame(width: w * 0.04, height: w * 0.04)
                            .offset(x: w * 0.02, y: 0)
                    }
                    .frame(width: w * 0.18, height: h * 0.24)
                    
                    ZStack {
                        Ellipse().fill(Color.white)
                            .overlay(Ellipse().stroke(Color.black, lineWidth: w * 0.015))
                        Circle().fill(Color.black).frame(width: w * 0.04, height: w * 0.04)
                            .offset(x: -w * 0.02, y: 0)
                    }
                    .frame(width: w * 0.18, height: h * 0.24)
                }
                .offset(y: -h * 0.12)
                
                // 红色鼻子
                Circle()
                    .fill(Color.red)
                    .frame(width: w * 0.12, height: w * 0.12)
                    .offset(y: -h * 0.03)
                    .overlay(
                        Circle().fill(Color.white).frame(width: w * 0.04, height: w * 0.04)
                            .offset(x: -w * 0.02, y: -h * 0.02)
                    )
                
                // 笑容和中线
                Path { path in
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.53))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.72))
                    
                    path.addArc(center: CGPoint(x: w * 0.5, y: h * 0.5),
                                radius: w * 0.22,
                                startAngle: .degrees(45),
                                endAngle: .degrees(135),
                                clockwise: false)
                }
                .stroke(Color.black, lineWidth: w * 0.02)
                
                // 胡须
                Path { path in
                    // Left whiskers
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.42))
                    
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.52))
                    path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.52))
                    
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.59))
                    path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.62))
                    
                    // Right whiskers
                    path.move(to: CGPoint(x: w * 0.68, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.42))
                    
                    path.move(to: CGPoint(x: w * 0.68, y: h * 0.52))
                    path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.52))
                    
                    path.move(to: CGPoint(x: w * 0.68, y: h * 0.59))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.62))
                }
                .stroke(Color.black, lineWidth: w * 0.015)
                
                // 项圈与铃铛
                VStack(spacing: 0) {
                    Spacer()
                    Capsule()
                        .fill(Color.red)
                        .frame(width: w * 0.6, height: h * 0.06)
                    
                    ZStack {
                        Circle().fill(Color(red: 0.98, green: 0.85, blue: 0.1))
                            .overlay(Circle().stroke(Color.black, lineWidth: w * 0.01))
                        Rectangle().fill(Color.black).frame(width: w * 0.08, height: h * 0.015)
                            .offset(y: -h * 0.005)
                        Circle().fill(Color.black).frame(width: w * 0.025, height: w * 0.025)
                            .offset(y: h * 0.01)
                    }
                    .frame(width: w * 0.12, height: w * 0.12)
                    .offset(y: -h * 0.02)
                }
            }
            .frame(width: w, height: h)
        }
    }
    
    // 矢量白雪公主 (Snow White)
    private var snowWhiteView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Circle().fill(Color(red: 0.98, green: 0.96, blue: 0.8))
                
                // 黑色秀发
                Circle()
                    .fill(Color.black)
                    .frame(width: w * 0.76, height: h * 0.76)
                    .offset(y: -h * 0.05)
                
                // 脸部
                Circle()
                    .fill(Color(red: 1.0, green: 0.93, blue: 0.88))
                    .frame(width: w * 0.55, height: h * 0.55)
                    .offset(y: h * 0.02)
                
                // 齐刘海
                Path { path in
                    path.addArc(center: CGPoint(x: w * 0.38, y: h * 0.32),
                                radius: w * 0.18,
                                startAngle: .degrees(180),
                                endAngle: .degrees(360),
                                clockwise: true)
                    path.addArc(center: CGPoint(x: w * 0.62, y: h * 0.32),
                                radius: w * 0.18,
                                startAngle: .degrees(180),
                                endAngle: .degrees(360),
                                clockwise: true)
                }
                .fill(Color.black)
                
                // 蓝色立领服饰
                Path { path in
                    path.move(to: CGPoint(x: w * 0.28, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.95))
                    path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.95))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.1, green: 0.25, blue: 0.55))
                
                // 白色高领
                Path { path in
                    path.move(to: CGPoint(x: w * 0.3, y: h * 0.62))
                    path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.5))
                    path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.65))
                    path.closeSubpath()
                    
                    path.move(to: CGPoint(x: w * 0.7, y: h * 0.62))
                    path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.5))
                    path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.65))
                    path.closeSubpath()
                }
                .fill(Color.white)
                
                // 红色蝴蝶结头饰
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.48, y: h * 0.15))
                        path.addQuadCurve(to: CGPoint(x: w * 0.36, y: h * 0.08), control: CGPoint(x: w * 0.4, y: h * 0.18))
                        path.addQuadCurve(to: CGPoint(x: w * 0.48, y: h * 0.15), control: CGPoint(x: w * 0.42, y: h * 0.06))
                    }
                    .fill(Color.red)
                    
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.52, y: h * 0.15))
                        path.addQuadCurve(to: CGPoint(x: w * 0.64, y: h * 0.08), control: CGPoint(x: w * 0.6, y: h * 0.18))
                        path.addQuadCurve(to: CGPoint(x: w * 0.52, y: h * 0.15), control: CGPoint(x: w * 0.58, y: h * 0.06))
                    }
                    .fill(Color.red)
                    
                    Circle()
                        .fill(Color.red)
                        .frame(width: w * 0.08, height: w * 0.08)
                        .offset(x: 0, y: -h * 0.35)
                }
                
                // 闭眼睫毛
                HStack(spacing: w * 0.16) {
                    Path { path in
                        path.addArc(center: CGPoint(x: w * 0.05, y: h * 0.05),
                                    radius: w * 0.03,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(180),
                                    clockwise: false)
                    }
                    .stroke(Color.black, lineWidth: w * 0.015)
                    .frame(width: w * 0.1, height: h * 0.1)
                    
                    Path { path in
                        path.addArc(center: CGPoint(x: w * 0.05, y: h * 0.05),
                                    radius: w * 0.03,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(180),
                                    clockwise: false)
                    }
                    .stroke(Color.black, lineWidth: w * 0.015)
                    .frame(width: w * 0.1, height: h * 0.1)
                }
                .offset(y: -h * 0.02)
                
                // 红润腮红与红唇
                Group {
                    HStack(spacing: w * 0.28) {
                        Circle().fill(Color.red.opacity(0.25)).frame(width: w * 0.07, height: w * 0.07)
                        Circle().fill(Color.red.opacity(0.25)).frame(width: w * 0.07, height: w * 0.07)
                    }
                    .offset(y: h * 0.05)
                    
                    Image(systemName: "suit.heart.fill")
                        .font(.system(size: w * 0.07))
                        .foregroundStyle(.red)
                        .rotationEffect(.degrees(180))
                        .offset(y: h * 0.1)
                }
            }
            .frame(width: w, height: h)
        }
    }
}
