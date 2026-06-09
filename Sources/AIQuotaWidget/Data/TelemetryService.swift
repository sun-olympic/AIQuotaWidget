import Foundation
import AppKit

/// 后台发送匿名使用时长统计的单例服务。
/// 每 60 秒上报一次心跳，包含设备 ID、用户名/邮箱、本次心跳时长。
@MainActor
final class TelemetryService {
    static let shared = TelemetryService()

    private var timer: Timer?
    private var lastHeartbeatTime: Date = Date()
    private var settings: AppSettings?
    private var service: QuotaService?

    private init() {}

    @MainActor
    func start(settings: AppSettings, service: QuotaService) {
        self.settings = settings
        self.service = service

        lastHeartbeatTime = Date()

        // 停止之前的定时器以防重复启动
        timer?.invalidate()

        // 60秒定时器
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.sendHeartbeat()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 启动时立即发送一次初始心跳
        sendHeartbeat(force: true)
    }

    @MainActor
    func stop() {
        sendHeartbeat() // 退出时发送最后一次心跳
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func sendHeartbeat(force: Bool = false) {
        guard let settings = settings else { return }

        let now = Date()
        let duration = now.timeIntervalSince(lastHeartbeatTime)
        lastHeartbeatTime = now

        // 限制单次心跳的最大上报时长为 90 秒，规避休眠后唤醒造成的超大时长突刺
        guard let durationToSend = Self.durationToSend(duration, force: force) else { return }

        // 获取用户名（优先获取绑定的邮箱，否则 fallback 到 macOS 用户名）
        var userName = NSUserName()
        if let cursorEmail = getCursorEmail(), !cursorEmail.isEmpty {
            userName = cursorEmail
        } else if let antigravityEmail = getAntigravityEmail(), !antigravityEmail.isEmpty {
            userName = antigravityEmail
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.7"
        let durationMsec = Int(durationToSend.rounded()) * 1000
        let eventParams: [String: Any] = [
            "engagement_time_msec": durationMsec,
            "user_name": userName,
            "device_id": settings.telemetryInstallationId,
            "app_version": appVersion
        ]
        let event: [String: Any] = [
            "name": "app_heartbeat",
            "params": eventParams
        ]
        let payload: [String: Any] = [
            "client_id": settings.telemetryInstallationId,
            "events": [event]
        ]

        let urlString = "https://www.google-analytics.com/mp/collect?measurement_id=\(settings.gaMeasurementId)&api_secret=\(settings.gaApiSecret)"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 5

        let task = URLSession.shared.dataTask(with: request) { _, _, _ in
            // 静默失败，不打扰用户
        }
        task.resume()
    }

    nonisolated static func durationToSend(_ duration: TimeInterval, force: Bool = false) -> TimeInterval? {
        let clamped = min(duration, 90)
        if force {
            return max(1, clamped)
        }
        guard clamped >= 1 else { return nil }
        return clamped
    }

    private func getCursorEmail() -> String? {
        let store = CredentialStore()
        let creds = try? store.load()
        return creds?.cachedEmail
    }

    private func getAntigravityEmail() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".gemini/google_accounts.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let active = json["active"] as? String else {
            return nil
        }
        return active
    }
}
