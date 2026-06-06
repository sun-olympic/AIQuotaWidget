import Foundation

/// 统一请求封装：注入 `Authorization` 头，401/未授权时用 refreshToken 自动续期并重试一次。
/// 令牌仅驻内存。`shouldLogout=true` 时进入「需重新登录」态并停止自动刷新。
actor AuthorizedHTTPClient {

    private var accessToken: String
    private var refreshToken: String?
    private var needsReLogin = false

    private let session: URLSession
    private let refresher: TokenRefresher

    init(accessToken: String,
         refreshToken: String?,
         session: URLSession = .shared,
         refresher: TokenRefresher = TokenRefresher()) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.session = session
        self.refresher = refresher
    }

    /// 发送请求；调用方提供「不含 Authorization 头」的请求，鉴权由本方法统一注入。
    func send(_ request: URLRequest) async throws -> Data {
        if needsReLogin { throw QuotaError.needsReLogin }

        let (data, http) = try await perform(request, token: accessToken)
        if http.statusCode == 401 || http.statusCode == 403 {
            // 自动刷新一次再重试。
            try await refreshOnce()
            let (retryData, retryHTTP) = try await perform(request, token: accessToken)
            guard (200..<300).contains(retryHTTP.statusCode) else {
                throw QuotaError.network("HTTP \(retryHTTP.statusCode) after token refresh")
            }
            return retryData
        }

        guard (200..<300).contains(http.statusCode) else {
            throw QuotaError.network("HTTP \(http.statusCode)")
        }
        return data
    }

    private func perform(_ request: URLRequest, token: String) async throws -> (Data, HTTPURLResponse) {
        var authed = request
        authed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if authed.timeoutInterval <= 0 { authed.timeoutInterval = CursorAPI.requestTimeout }
        do {
            let (data, response) = try await session.data(for: authed)
            guard let http = response as? HTTPURLResponse else {
                throw QuotaError.network("no http response")
            }
            return (data, http)
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.network(error.localizedDescription)
        }
    }

    private func refreshOnce() async throws {
        guard let refreshToken = refreshToken else {
            needsReLogin = true
            throw QuotaError.needsReLogin
        }
        let result = try await refresher.refresh(refreshToken: refreshToken)
        if result.shouldLogout {
            needsReLogin = true
            throw QuotaError.needsReLogin
        }
        if let newAccess = result.accessToken {
            accessToken = newAccess
        }
        if let newRefresh = result.refreshToken {
            self.refreshToken = newRefresh
        }
    }
}
