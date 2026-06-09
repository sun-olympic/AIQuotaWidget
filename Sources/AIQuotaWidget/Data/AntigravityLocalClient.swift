import Foundation

/// Antigravity local mode: talks to the IDE-owned Connect server on 127.0.0.1.
struct AntigravityLocalClient: AntigravityRawDataSource {
    var discoverServer: () -> AntigravityLocalServer.Server? = AntigravityLocalServer.discover
    var makeSession: () -> URLSession = {
        LocalhostInsecureSession.make(timeout: AntigravityConfig.requestTimeout)
    }

    func fetchRawData() async throws -> AntigravityRawData? {
        guard let server = discoverServer() else { return nil }

        let session = makeSession()
        // 进程可能监听多个端口，HTTPS Connect 接口只在其中之一，逐个尝试。
        for port in server.ports {
            guard let modelsData = try? await post(
                path: AntigravityConfig.getAvailableModelsPath,
                port: port,
                csrfToken: server.csrfToken,
                session: session
            ) else {
                continue
            }

            var raw = AntigravityPayloadParser.parseAvailableModels(modelsData)
            if raw == nil {
                continue
            }

            if let statusData = try? await post(
                path: AntigravityConfig.getUserStatusPath,
                port: port,
                csrfToken: server.csrfToken,
                session: session
            ), let planName = AntigravityPayloadParser.parsePlanName(from: statusData) {
                raw?.planName = planName
            }

            return raw
        }
        return nil
    }

    private func post(path: String, port: Int, csrfToken: String, session: URLSession) async throws -> Data? {
        guard let url = URL(string: "https://127.0.0.1:\(port)\(path)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: AntigravityConfig.csrfHeaderName)
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return data
    }
}

