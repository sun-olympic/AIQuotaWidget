import Foundation

/// 错误信息脱敏：移除令牌明文（JWT）与本地文件系统路径，避免在 UI/日志中泄露。
enum Redaction {

    /// 形如 xxx.yyy.zzz 的 JWT。
    private static let jwtRegex = try? NSRegularExpression(
        pattern: "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
        options: []
    )

    /// 形如 /Users/... 或 /Library/... 的绝对路径。
    private static let pathRegex = try? NSRegularExpression(
        pattern: "(/Users/|/Library/|/var/|/private/|/home/)[^\\s\"']*",
        options: []
    )

    static func redact(_ message: String) -> String {
        var result = message
        result = replace(result, regex: jwtRegex, with: "<redacted-token>")
        result = replace(result, regex: pathRegex, with: "<redacted-path>")
        return result
    }

    private static func replace(_ input: String, regex: NSRegularExpression?, with replacement: String) -> String {
        guard let regex = regex else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }
}
