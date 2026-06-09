import Foundation

/// 本地 Antigravity `language_server` 探测：从进程参数取 CSRF token，用 lsof 取监听端口。
enum AntigravityLocalServer {
    struct Server {
        let csrfToken: String
        let ports: [Int]
    }

    static func discover() -> Server? {
        guard let (pid, csrf) = findProcess() else { return nil }
        let ports = listeningPorts(pid: pid)
        guard !ports.isEmpty else { return nil }
        return Server(csrfToken: csrf, ports: ports)
    }

    /// 在 `ps` 输出中定位 antigravity 的 language_server，返回 (pid, csrfToken)。
    private static func findProcess() -> (pid: Int, csrf: String)? {
        guard let output = run("/bin/ps", ["-axww", "-o", "pid=,args="]) else { return nil }
        for line in output.split(separator: "\n") {
            let s = String(line)
            guard s.contains(AntigravityConfig.localServerExecutableHint),
                  s.lowercased().contains(AntigravityConfig.localServerIdeMarker),
                  let csrf = capture(s, "\(AntigravityConfig.csrfArgName)[ =]([A-Za-z0-9\\-]+)") else {
                continue
            }
            // 行首是 pid。
            let trimmed = s.drop(while: { $0 == " " })
            let pidStr = trimmed.prefix(while: { $0.isNumber })
            guard let pid = Int(pidStr) else { continue }
            return (pid, csrf)
        }
        return nil
    }

    /// lsof 取该进程在回环上的 TCP 监听端口。
    private static func listeningPorts(pid: Int) -> [Int] {
        // 关键：`-a` 把多个筛选条件按 AND 组合，否则 lsof 默认 OR 会返回全机所有监听端口。
        let args = ["-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        guard let output = run("/usr/sbin/lsof", args) ?? run("/usr/bin/lsof", args) else {
            return []
        }
        var ports: [Int] = []
        for line in output.split(separator: "\n") {
            // 形如 ... TCP 127.0.0.1:57531 (LISTEN)
            if let port = capture(String(line), ":([0-9]+) \\(LISTEN\\)").flatMap(Int.init) {
                ports.append(port)
            }
        }
        return Array(Set(ports)).sorted()
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}

/// 接受 127.0.0.1 自签名证书的 URLSession（本地 language_server 用自签名 TLS）。
final class LocalhostInsecureSession: NSObject, URLSessionDelegate {
    static func make(timeout: TimeInterval) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        return URLSession(configuration: config, delegate: LocalhostInsecureSession(), delegateQueue: nil)
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1",
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

