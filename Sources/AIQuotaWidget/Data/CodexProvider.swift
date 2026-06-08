import Foundation

/// Codex 额度 provider：spawn 短命 `codex app-server`（JSON-RPC over stdio），
/// `initialize` 握手 +（延迟）→ `account/rateLimits/read`，读取 5h/7d 双窗口后立即结束子进程。
struct CodexProvider: QuotaProvider {
    let productName = "Codex"
    private let settings: AppSettings?

    init(settings: AppSettings? = nil) {
        self.settings = settings
    }

    func fetch() async throws -> QuotaSnapshot {
        // 2.1 探测：区分「未安装」与「未登录」。
        guard let executable = CodexAppServer.locateExecutable(settings: settings) else {
            throw QuotaError.notInstalled
        }
        guard CodexAppServer.isLoggedIn() else {
            throw QuotaError.notLoggedIn
        }

        // 2.2/2.3 子进程取数（在后台线程执行，带超时）。
        let rateLimits = try await CodexAppServer.readRateLimits(executable: executable)

        // 2.4 归一化。
        let primary = rateLimits.dict("primary")
        let secondary = rateLimits.dict("secondary")

        guard let primaryUsed = windowUsedPercent(primary) else {
            throw QuotaError.decoding("codex rateLimits missing primary window")
        }

        let input = CodexNormalizer.Input(
            primaryUsedPercent: primaryUsed,
            primaryResetAt: windowReset(primary),
            secondaryUsedPercent: windowUsedPercent(secondary),
            secondaryResetAt: windowReset(secondary),
            planType: rateLimits.string("planType") ?? rateLimits.string("plan_type") ?? rateLimits.string("plan")
        )
        return CodexNormalizer.make(input)
    }

    private func windowUsedPercent(_ window: JSONDigger?) -> Double? {
        window?.double("usedPercent") ?? window?.double("used_percent")
    }

    private func windowReset(_ window: JSONDigger?) -> Date? {
        guard let window = window else { return nil }
        if let abs = window.root["resetsAt"] ?? window.root["resets_at"] {
            return QuotaNormalizer.dateFromFlexible(abs)
        }
        // 相对秒数兜底。
        if let secs = window.double("resetsInSeconds") ?? window.double("resets_in_seconds") {
            return Date().addingTimeInterval(secs)
        }
        return nil
    }
}

/// `codex app-server` 子进程封装。命令与方法名集中在 `CodexConfig`。
enum CodexAppServer {

    /// 在 PATH 与常见目录中定位 `codex` 可执行文件。
    static func locateExecutable(settings: AppSettings? = nil) -> String? {
        let fm = FileManager.default
        if let customPath = settings?.customCodexPath, !customPath.isEmpty {
            var resolvedPath = customPath
            if customPath.hasSuffix(".app") {
                let appServerBinary = (customPath as NSString).appendingPathComponent("Contents/Resources/codex")
                if fm.isExecutableFile(atPath: appServerBinary) {
                    resolvedPath = appServerBinary
                }
            }
            if fm.isExecutableFile(atPath: resolvedPath) {
                return resolvedPath
            }
        }

        var dirs: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        dirs.append(contentsOf: CodexConfig.extraSearchDirs)
        let home = fm.homeDirectoryForCurrentUser.path
        dirs.append("\(home)/.codex/bin")
        dirs.append("\(home)/.local/bin")

        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent(CodexConfig.executableName)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// `~/.codex/auth.json` 存在且非空视为已登录。
    static func isLoggedIn() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(CodexConfig.authJSONRelative)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0 else {
            return false
        }
        return true
    }

    /// 后台线程跑阻塞式子进程交互，整体超时由看门狗强制结束进程。
    static func readRateLimits(executable: String) async throws -> JSONDigger {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let dict = try runBlocking(executable: executable)
                    continuation.resume(returning: JSONDigger(dict))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(executable: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = CodexConfig.appServerArgs

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw QuotaError.notInstalled
        }

        // 看门狗：超时强制结束 → 关闭管道 → availableData 返回 EOF → 跳出读循环。
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + CodexConfig.timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        send(["jsonrpc": "2.0", "id": 1, "method": CodexConfig.initializeMethod,
              "params": ["clientInfo": ["name": "CursorQuotaWidget", "version": "1.0"]]],
             to: stdin)
        Thread.sleep(forTimeInterval: CodexConfig.handshakeDelay)
        send(["jsonrpc": "2.0", "id": 2, "method": CodexConfig.rateLimitsMethod, "params": [:]],
             to: stdin)

        let handle = stdout.fileHandleForReading
        let deadline = Date().addingTimeInterval(CodexConfig.timeout)
        var buffer = Data()

        while Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
                if let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   (obj["id"] as? Int) == 2,
                   let result = obj["result"] as? [String: Any] {
                    return extractRateLimits(result)
                }
            }
        }
        throw QuotaError.timeout
    }

    private static func send(_ object: [String: Any], to pipe: Pipe) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        pipe.fileHandleForWriting.write(data)
    }

    /// 返回可能将限额包在 `rateLimits` 下，做一层兼容。
    private static func extractRateLimits(_ result: [String: Any]) -> [String: Any] {
        if let nested = result["rateLimits"] as? [String: Any] { return nested }
        if let nested = result["rate_limits"] as? [String: Any] { return nested }
        return result
    }
}
