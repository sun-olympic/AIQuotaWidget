import Foundation

struct ClaudeUsage {
    var input: Int = 0
    var output: Int = 0
    var cacheCreation: Int = 0
    var cacheRead: Int = 0
    
    var total: Int { input + output }
}

/// Claude Code 额度提供者：扫描本地 `~/.claude/projects/` 或 `~/.config/claude/projects/` 下的 `.jsonl` 会话日志，
/// 提取事件中的 Token 并计算估算花费（由于无云端 API 凭证，全部采用本地解析与估计）。
struct ClaudeCodeProvider: QuotaProvider {
    let productName = "Claude Code"
    let basePaths: [URL]
    
    init(basePaths: [URL]? = nil) {
        if let basePaths = basePaths {
            self.basePaths = basePaths
        } else {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            self.basePaths = [
                home.appendingPathComponent(".claude/projects"),
                home.appendingPathComponent(".config/claude/projects")
            ]
        }
    }
    
    func fetch() async throws -> QuotaSnapshot {
        let fm = FileManager.default
        
        // 1. 检查是否安装：如果任何一个 basePaths 的父目录（如 .claude 或 .config/claude）存在，即视为已安装
        var parentExists = false
        for path in basePaths {
            let parent = path.deletingLastPathComponent()
            if fm.fileExists(atPath: parent.path) {
                parentExists = true
                break
            }
        }
        guard parentExists else {
            throw QuotaError.notInstalled
        }
        
        // 2. 扫描目录下所有 .jsonl 结尾的会话文件
        var jsonlFiles: [URL] = []
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        for path in basePaths {
            guard fm.fileExists(atPath: path.path) else { continue }
            guard let enumerator = fm.enumerator(
                at: path,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            ) else { continue }
            
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "jsonl" {
                    jsonlFiles.append(fileURL)
                }
            }
        }
        
        // 3. 如果没找到任何日志，说明没有产生过会话，提示未登录/未产生会话
        guard !jsonlFiles.isEmpty else {
            throw QuotaError.notLoggedIn
        }
        
        // 4. 解析日志行并以 messageId:requestId 去重，流式更新取最大值
        var records: [String: ClaudeUsage] = [:]
        
        for fileURL in jsonlFiles {
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    guard let data = trimmed.data(using: .utf8) else { continue }
                    
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        // 获取去重 key
                        let messageId = (json["message"] as? [String: Any])?["id"] as? String ?? json["messageId"] as? String
                        let requestId = json["requestId"] as? String
                        
                        // 若全空，生成随机 key 以保证记录不被漏掉，但尽可能利用 ID 去重
                        let key: String
                        if messageId == nil && requestId == nil {
                            key = UUID().uuidString
                        } else {
                            key = requestId != nil ? "\(messageId ?? ""):\(requestId!)" : messageId!
                        }
                        
                        // 提取本行内的全部 usage 结构
                        let usages = extractUsages(from: json)
                        guard !usages.isEmpty else { continue }
                        
                        // 汇总本行所有 usage 块
                        var lineInput = 0
                        var lineOutput = 0
                        var lineCacheCreation = 0
                        var lineCacheRead = 0
                        
                        for u in usages {
                            lineInput += u.input
                            lineOutput += u.output
                            lineCacheCreation += u.cacheCreation
                            lineCacheRead += u.cacheRead
                        }
                        
                        let newRecord = ClaudeUsage(input: lineInput, output: lineOutput, cacheCreation: lineCacheCreation, cacheRead: lineCacheRead)
                        
                        if let existing = records[key] {
                            // 流式响应：仅在当前行 Token 数更多时更新它，避免重复计费
                            if newRecord.total > existing.total {
                                records[key] = newRecord
                            }
                        } else {
                            records[key] = newRecord
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        // 5. 汇总数据
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0
        
        for r in records.values {
            totalInput += r.input
            totalOutput += r.output
            totalCacheCreation += r.cacheCreation
            totalCacheRead += r.cacheRead
        }
        
        // 6. 花费定价估计（基于 Claude 3.5 Sonnet 模型官网标准）：
        // - 输入基础：$3.00 / M
        // - 缓存写入（创建）：$3.75 / M (1.25x)
        // - 缓存读取：$0.30 / M (0.1x)
        // - 输出：$15.00 / M
        let nonCacheInput = max(0, totalInput - totalCacheCreation - totalCacheRead)
        let cost = (Double(nonCacheInput) * 3.0 +
                    Double(totalCacheCreation) * 3.75 +
                    Double(totalCacheRead) * 0.30 +
                    Double(totalOutput) * 15.0) / 1_000_000.0
        
        let totalTokens = totalInput + totalOutput
        let formattedCost = String(format: "$%.2f", cost)
        let formattedTokens = formatTokens(totalTokens)
        
        return QuotaSnapshot(
            remainingPercent: 100, // 账单型无剩余百分比限制，水球默认显示满值
            primaryText: "\(formattedCost) spent",
            secondaryText: "\(formattedTokens) tokens",
            resetAt: nil,
            planName: nil,
            mode: .usageBased,
            onDemand: nil,
            secondaryWindows: nil,
            antigravityModels: nil,
            activeAntigravityModelId: nil,
            ledStatus: .green
        )
    }
    
    private func extractUsages(from value: Any) -> [ClaudeUsage] {
        var results: [ClaudeUsage] = []
        if let dict = value as? [String: Any] {
            if dict.keys.contains("input_tokens") || dict.keys.contains("inputTokens") ||
               dict.keys.contains("output_tokens") || dict.keys.contains("outputTokens") {
                let input = (dict["input_tokens"] as? Int) ?? (dict["inputTokens"] as? Int) ?? 0
                let output = (dict["output_tokens"] as? Int) ?? (dict["outputTokens"] as? Int) ?? 0
                let cacheCreation = (dict["cache_creation_input_tokens"] as? Int) ?? (dict["cacheCreationInputTokens"] as? Int) ?? 0
                let cacheRead = (dict["cache_read_input_tokens"] as? Int) ?? (dict["cacheReadInputTokens"] as? Int) ?? 0
                results.append(ClaudeUsage(input: input, output: output, cacheCreation: cacheCreation, cacheRead: cacheRead))
            }
            for (_, val) in dict {
                results.append(contentsOf: extractUsages(from: val))
            }
        } else if let arr = value as? [Any] {
            for val in arr {
                results.append(contentsOf: extractUsages(from: val))
            }
        }
        return results
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}
