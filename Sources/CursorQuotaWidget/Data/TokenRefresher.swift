import Foundation

struct TokenRefreshResult {
    var accessToken: String?
    var refreshToken: String?
    var shouldLogout: Bool
}

/// 调用 `POST .../oauth/token`（grant_type=refresh_token，固定 client_id）刷新令牌。
struct TokenRefresher {
    var session: URLSession = .shared

    func refresh(refreshToken: String) async throws -> TokenRefreshResult {
        guard let url = URL(string: CursorAPI.oauthToken) else {
            throw QuotaError.network("invalid oauth url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = CursorAPI.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": CursorAPI.oauthClientID
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.network("no http response")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let shouldLogout = (json["shouldLogout"] as? Bool) ?? false

        if shouldLogout {
            return TokenRefreshResult(accessToken: nil, refreshToken: nil, shouldLogout: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw QuotaError.network("token refresh failed: HTTP \(http.statusCode)")
        }

        let access = (json["accessToken"] as? String) ?? (json["access_token"] as? String)
        let newRefresh = (json["refreshToken"] as? String) ?? (json["refresh_token"] as? String)
        return TokenRefreshResult(accessToken: access, refreshToken: newRefresh, shouldLogout: false)
    }
}
