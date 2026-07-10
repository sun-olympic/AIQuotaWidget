import XCTest
@testable import AIQuotaWidget

final class ClaudeCodeProviderTests: XCTestCase {
    
    private var tempDirURL: URL!
    
    override func setUp() {
        super.setUp()
        tempDirURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirURL)
        super.tearDown()
    }
    
    func testClaudeProviderNotInstalled() async {
        // 使用一个不存在的路径
        let path = tempDirURL.appendingPathComponent("non_existent/.claude/projects")
        let provider = ClaudeCodeProvider(basePaths: [path])
        
        do {
            _ = try await provider.fetch()
            XCTFail("Should throw error")
        } catch QuotaError.notInstalled {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testClaudeProviderNotLoggedIn() async throws {
        // 创建父目录（.claude 存在表示已安装），但 projects 目录下没有 jsonl 文件
        let parentDir = tempDirURL.appendingPathComponent(".claude")
        let projectsDir = parentDir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true, attributes: nil)
        
        let provider = ClaudeCodeProvider(basePaths: [projectsDir])
        
        do {
            _ = try await provider.fetch()
            XCTFail("Should throw error")
        } catch QuotaError.notLoggedIn {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testClaudeProviderSuccessAndCostEstimation() async throws {
        let parentDir = tempDirURL.appendingPathComponent(".claude")
        let projectsDir = parentDir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true, attributes: nil)
        
        let sessionFile = projectsDir.appendingPathComponent("session_1.jsonl")
        
        // 模拟 jsonl 文件内容
        // 1. msg1 流式阶段 1 (input: 10000, output: 2000)
        // 2. msg1 流式阶段 2 (input: 10000, output: 4000) -> 应该只保留最大的这个
        // 3. msg2 (input: 5000, cache_creation: 2000, cache_read: 1000, output: 1000)
        let logLines = [
            #"{"message":{"id":"msg1","usage":{"input_tokens":10000,"output_tokens":2000}}, "requestId":"req1"}"#,
            #"{"message":{"id":"msg1","usage":{"input_tokens":10000,"output_tokens":4000}}, "requestId":"req1"}"#,
            #"{"message":{"id":"msg2","usage":{"input_tokens":5000,"output_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":1000}}, "requestId":"req2"}"#
        ].joined(separator: "\n")
        
        try logLines.write(to: sessionFile, atomically: true, encoding: .utf8)
        
        let provider = ClaudeCodeProvider(basePaths: [projectsDir])
        let snapshot = try await provider.fetch()
        
        // 验证去重后的总 Tokens：
        // msg1 最终: 10000 + 4000 = 14000
        // msg2 最终: 5000 + 1000 = 6000
        // 总数 = 20000 -> "20.0k tokens"
        XCTAssertEqual(snapshot.secondaryText, "20.0k tokens")
        
        // 验证估算花费：
        // msg1: nonCacheInput = 10000, output = 4000
        //       cost1 = (10000 * 3.0 + 4000 * 15.0) / 1M = (30000 + 60000) / 1M = 0.09 美元
        // msg2: nonCacheInput = 5000 - 2000 - 1000 = 2000, cacheCreation = 2000, cacheRead = 1000, output = 1000
        //       cost2 = (2000 * 3.0 + 2000 * 3.75 + 1000 * 0.3 + 1000 * 15.0) / 1M
        //             = (6000 + 7500 + 300 + 15000) / 1M = 0.0288 美元
        // 总花费 = 0.09 + 0.0288 = 0.1188 美元 -> 格式化为 "$0.12 spent"
        XCTAssertEqual(snapshot.primaryText, "$0.12 spent")
        XCTAssertEqual(snapshot.remainingPercent, 100)
        XCTAssertEqual(snapshot.ledStatus, .green)
        XCTAssertEqual(snapshot.mode, .usageBased)
    }
}
