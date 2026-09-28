import XCTest
@testable import AIQuotaWidget

final class CodexExecutableTests: XCTestCase {
    func testCustomChatGPTBundleResolvesNestedCLI() throws {
        try checkBundle(binary: "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    }

    func testCustomLegacyBundleStillResolvesCLI() throws {
        try checkBundle(binary: "Contents/Resources/codex")
    }

    func testDefaultSearchIncludesChatGPTNestedCLI() {
        XCTAssertTrue(CodexConfig.extraSearchDirs.contains(
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS"))
    }

    private func checkBundle(binary: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("ChatGPT.app")
        let executable = app.appendingPathComponent(binary)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let suite = "CodexExecutableTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.customCodexPath = app.path
        XCTAssertEqual(CodexAppServer.locateExecutable(settings: settings), executable.path)
    }
}
