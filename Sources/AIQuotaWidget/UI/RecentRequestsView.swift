import SwiftUI

/// 最近 N 次请求的 token 消耗列表；鼠标悬停于消耗量上显示详细分类。
struct RecentRequestsView: View {
    let requests: [RecentRequest]
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(settings.t("recent.title"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 1)

            ForEach(requests) { req in
                requestRow(req)
            }
        }
    }

    private func requestRow(_ req: RecentRequest) -> some View {
        HStack(spacing: 0) {
            Text(req.model)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.formatTokens(req.totalTokens, lang: settings.language))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .help(tokenTooltip(req))
                .padding(.horizontal, 4)

            Text(Self.formatTime(req.timestamp))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 68, alignment: .trailing)
        }
    }

    // MARK: - Formatting

    static func formatTokens(_ count: Int, lang: AppLanguage) -> String {
        if lang == .chinese {
            if count >= 10_000 {
                return String(format: "%.1f万", Double(count) / 10_000)
            }
        } else {
            if count >= 1_000_000 {
                return String(format: "%.1fM", Double(count) / 1_000_000)
            }
            if count >= 1_000 {
                return String(format: "%.1fK", Double(count) / 1_000)
            }
        }
        return NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
    }

    static func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
        } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
            fmt.dateFormat = "M/d HH:mm"
        } else {
            fmt.dateFormat = "yy/M/d HH:mm"
        }
        return fmt.string(from: date)
    }

    private func tokenTooltip(_ req: RecentRequest) -> String {
        let n = Self.fmtNum
        var lines: [String] = []
        if req.cacheReadTokens > 0 {
            lines.append("Cache Read: \(n(req.cacheReadTokens))")
        }
        if req.cacheWriteTokens > 0 {
            lines.append("Cache Write: \(n(req.cacheWriteTokens))")
        }
        lines.append("\(settings.t("recent.input")): \(n(req.inputTokens))")
        lines.append("\(settings.t("recent.output")): \(n(req.outputTokens))")
        lines.append("Total: \(n(req.totalTokens))")
        return lines.joined(separator: "\n")
    }

    static func fmtNum(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }
}
