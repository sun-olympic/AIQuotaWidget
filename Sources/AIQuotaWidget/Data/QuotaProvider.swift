import Foundation

enum QuotaError: Error, LocalizedError {
    case unauthorized
    case needsReLogin
    case notLoggedIn
    case notInstalled
    case timeout
    case network(String)
    case decoding(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized"
        case .needsReLogin: return "Please sign in to Cursor again"
        case .notLoggedIn: return "Not signed in"
        case .notInstalled: return "CLI not installed"
        case .timeout: return "Request timed out"
        case .network(let m): return Redaction.redact(m)
        case .decoding(let m): return Redaction.redact(m)
        case .unsupported: return "Not supported yet"
        }
    }
}

/// 额度数据 provider 协议。UI 只认 `QuotaSnapshot`，计费/产品差异隔离在各实现中。
protocol QuotaProvider {
    var productName: String { get }
    func fetch() async throws -> QuotaSnapshot
}
