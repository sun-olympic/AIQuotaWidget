import Foundation

/// Antigravity cloud fallback. It is usually inactive until the product-specific OAuth client is known.
struct AntigravityCloudClient: AntigravityRawDataSource {
    var loadCredentials: () -> AntigravityCredentials.Credentials? = AntigravityCredentials.load
    var session: URLSession = .shared

    func fetchRawData() async throws -> AntigravityRawData? {
        guard let creds = loadCredentials(),
              !AntigravityConfig.oauthClientID.isEmpty,
              let accessToken = try await refreshAccessToken(refreshToken: creds.refreshToken) else {
            return nil
        }
        guard let url = URL(string: AntigravityConfig.fetchModelsURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AntigravityConfig.requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project": creds.projectId])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return AntigravityPayloadParser.parseAvailableModels(data)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String? {
        guard let url = URL(string: AntigravityConfig.oauthTokenURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AntigravityConfig.requestTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": AntigravityConfig.oauthClientID,
            "client_secret": AntigravityConfig.oauthClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = form.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["access_token"] as? String
    }
}

/// Antigravity 云端 OAuth 凭证读取（回退用；本机凭证在 `~/.gemini/oauth_creds.json`，但缺专属 OAuth client）。
enum AntigravityCredentials {
    struct Credentials {
        let refreshToken: String
        let projectId: String
    }

    static func load() -> Credentials? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: url), let digger = JSONDigger(data),
              let refresh = digger.string("refresh_token") else {
            return nil
        }
        // project 在该文件中通常缺失；置空，云模式当前不依赖它跑通。
        return Credentials(refreshToken: refresh, projectId: "")
    }
}

