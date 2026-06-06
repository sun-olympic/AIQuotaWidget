import SwiftUI

extension LEDStatus {
    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var localizationKey: String {
        switch self {
        case .green: return "status.green"
        case .yellow: return "status.yellow"
        case .red: return "status.red"
        }
    }
}

/// 三色 LED 状态灯 + 状态文字。
struct LEDView: View {
    let status: LEDStatus
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
                .shadow(color: status.color.opacity(0.8), radius: 4)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
