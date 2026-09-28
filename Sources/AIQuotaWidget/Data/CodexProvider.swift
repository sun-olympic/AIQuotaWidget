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
        let rawResult = try await CodexAppServer.readRateLimitsRaw(executable: executable)

        // 2.4 归一化。
        let rateLimits = JSONDigger(CodexAppServer.extractRateLimits(rawResult))
        let primary = rateLimits.dict("primary")
        let secondary = rateLimits.dict("secondary")

        guard let primaryUsed = windowUsedPercent(primary) else {
            throw QuotaError.decoding("codex rateLimits missing primary window")
        }

        let extraBuckets = Self.parseExtraBuckets(rawResult, mainLimitId: rateLimits.string("limitId"))

        let input = CodexNormalizer.Input(
            primaryUsedPercent: primaryUsed,
            primaryResetAt: windowReset(primary),
            primaryWindowDurationMins: windowDurationMins(primary),
            secondaryUsedPercent: windowUsedPercent(secondary),
            secondaryResetAt: windowReset(secondary),
            secondaryWindowDurationMins: windowDurationMins(secondary),
            planType: rateLimits.string("planType") ?? rateLimits.string("plan_type") ?? rateLimits.string("plan"),
            extraBuckets: extraBuckets
        )
        return CodexNormalizer.make(input)
    }

    private func windowUsedPercent(_ window: JSONDigger?) -> Double? {
        window?.double("usedPercent") ?? window?.double("used_percent")
    }

    private func windowDurationMins(_ window: JSONDigger?) -> Int? {
        window?.int("windowDurationMins") ?? window?.int("window_duration_mins")
    }

    private func windowReset(_ window: JSONDigger?) -> Date? {
        guard let window = window else { return nil }
        if let abs = window.root["resetsAt"] ?? window.root["resets_at"] {
            return QuotaNormalizer.dateFromFlexible(abs)
        }
        if let secs = window.double("resetsInSeconds") ?? window.double("resets_in_seconds") {
            return Date().addingTimeInterval(secs)
        }
        return nil
    }

    /// 从 `rateLimitsByLimitId` 中提取主 bucket 以外的额外限额。
    private static func parseExtraBuckets(_ rawResult: [String: Any], mainLimitId: String?) -> [CodexNormalizer.ExtraBucket] {
        let byId = (rawResult["rateLimitsByLimitId"] as? [String: Any])
            ?? (rawResult["rate_limits_by_limit_id"] as? [String: Any])
        guard let byId = byId else { return [] }
        let mainId = mainLimitId ?? "codex"

        var buckets: [CodexNormalizer.ExtraBucket] = []
        for (key, value) in byId {
            guard key != mainId, let dict = value as? [String: Any] else { continue }
            let digger = JSONDigger(dict)
            guard let primary = digger.dict("primary"),
                  let used = primary.double("usedPercent") ?? primary.double("used_percent") else { continue }
            let name = digger.string("limitName") ?? digger.string("limit_name") ?? key
            buckets.append(CodexNormalizer.ExtraBucket(
                name: name,
                primaryUsedPercent: used,
                primaryResetAt: {
                    if let abs = primary.root["resetsAt"] ?? primary.root["resets_at"] {
                        return QuotaNormalizer.dateFromFlexible(abs)
                    }
                    return nil
                }(),
                primaryWindowDurationMins: primary.int("windowDurationMins") ?? primary.int("window_duration_mins")
            ))
        }
        return buckets.sorted { $0.name < $1.name }
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
                for relativePath in CodexConfig.appExecutableRelativePaths {
                    let appServerBinary = (customPath as NSString).appendingPathComponent(relativePath)
                    if fm.isExecutableFile(atPath: appServerBinary) {
                        return appServerBinary
                    }
                }
                resolvedPath = ""
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
    /// 返回 `extractRateLimits` 后的主 bucket 字典（老接口，保留兼容）。
    static func readRateLimits(executable: String) async throws -> JSONDigger {
        let raw = try await readRateLimitsRaw(executable: executable)
        return JSONDigger(extractRateLimits(raw))
    }

    /// 返回 `account/rateLimits/read` 的完整 result 字典（含多 bucket）。
    static func readRateLimitsRaw(executable: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let dict = try runBlocking(executable: executable)
                    continuation.resume(returning: dict)
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
        let handle = stdout.fileHandleForReading
        let deadline = Date().addingTimeInterval(CodexConfig.timeout)
        var buffer = Data()

        while Date() < deadline {
            for obj in readAvailableMessages(from: handle, buffer: &buffer) {
                if messageID(obj) == 1 {
                    if let error = obj["error"] as? [String: Any] {
                        throw QuotaError.decoding("codex initialize failed: \(error["message"] ?? "unknown")")
                    }
                    send(["jsonrpc": "2.0", "id": 2, "method": CodexConfig.rateLimitsMethod, "params": [:]],
                         to: stdin)
                    return try readRateLimitsResponse(from: handle, buffer: &buffer, deadline: deadline)
                }
            }
        }
        throw QuotaError.timeout
    }

    /// 返回完整的 result 字典（不提取 bucket），由调用方决定是否 extractRateLimits。
    private static func readRateLimitsResponse(
        from handle: FileHandle,
        buffer: inout Data,
        deadline: Date
    ) throws -> [String: Any] {
        while Date() < deadline {
            for obj in readAvailableMessages(from: handle, buffer: &buffer) {
                guard messageID(obj) == 2 else { continue }
                if let result = obj["result"] as? [String: Any] {
                    return result
                }
                if let error = obj["error"] as? [String: Any] {
                    throw QuotaError.decoding("codex rateLimits failed: \(error["message"] ?? "unknown")")
                }
            }
        }
        throw QuotaError.timeout
    }

    private static func readAvailableMessages(from handle: FileHandle, buffer: inout Data) -> [[String: Any]] {
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)

        var messages: [[String: Any]] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            messages.append(obj)
        }
        return messages
    }

    private static func send(_ object: [String: Any], to pipe: Pipe) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        pipe.fileHandleForWriting.write(data)
    }

    static func messageID(_ message: [String: Any]) -> Int? {
        if let id = message["id"] as? Int { return id }
        if let id = message["id"] as? String { return Int(id) }
        if let id = message["id"] as? NSNumber { return id.intValue }
        return nil
    }

    /// 返回可能将限额包在 `rateLimits` 下，做一层兼容；新版还会按 `limit_id` 返回多 bucket。
    static func extractRateLimits(_ result: [String: Any]) -> [String: Any] {
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            return codex
        }
        if let buckets = result["rate_limits_by_limit_id"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            return codex
        }
        if let nested = result["rateLimits"] as? [String: Any] { return nested }
        if let nested = result["rate_limits"] as? [String: Any] { return nested }
        return result
    }
}
