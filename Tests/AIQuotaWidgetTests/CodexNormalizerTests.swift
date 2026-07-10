import XCTest
@testable import AIQuotaWidget

final class CodexNormalizerTests: XCTestCase {

    func testPrimaryMainDimension() {
        let snapshot = CodexNormalizer.make(
            .init(primaryUsedPercent: 25, primaryResetAt: nil,
                  secondaryUsedPercent: nil, secondaryResetAt: nil, planType: "plus")
        )
        XCTAssertEqual(snapshot.remainingPercent, 75, accuracy: 0.001)
        XCTAssertEqual(snapshot.ledStatus, .green)
        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertNil(snapshot.secondaryWindows)
    }

    func testPrimaryRedThreshold() {
        let snapshot = CodexNormalizer.make(
            .init(primaryUsedPercent: 92, primaryResetAt: nil,
                  secondaryUsedPercent: nil, secondaryResetAt: nil, planType: nil)
        )
        // 5h 窗口剩余 8% → 红
        XCTAssertEqual(snapshot.remainingPercent, 8, accuracy: 0.001)
        XCTAssertEqual(snapshot.ledStatus, .red)
    }

    func testSecondaryWindowAttached() throws {
        let snapshot = CodexNormalizer.make(
            .init(primaryUsedPercent: 10, primaryResetAt: nil,
                  secondaryUsedPercent: 40, secondaryResetAt: nil, planType: "pro")
        )
        let windows = try XCTUnwrap(snapshot.secondaryWindows)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].name, "7d")
        XCTAssertEqual(windows[0].remainingPercent, 60, accuracy: 0.001)
        // 主维度不受 7d 影响
        XCTAssertEqual(snapshot.remainingPercent, 90, accuracy: 0.001)
    }

    func testExtractsCodexBucketFromMultiBucketRateLimitResponse() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "legacy",
                "primary": ["usedPercent": 80]
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "primary": ["usedPercent": 2],
                    "secondary": ["usedPercent": 0],
                    "planType": "prolite"
                ],
                "codex_bengalfox": [
                    "limitId": "codex_bengalfox",
                    "primary": ["usedPercent": 0]
                ]
            ]
        ]

        let extracted = JSONDigger(CodexAppServer.extractRateLimits(result))
        XCTAssertEqual(extracted.string("limitId"), "codex")
        XCTAssertEqual(extracted.dict("primary")?.double("usedPercent"), 2)
        XCTAssertEqual(extracted.string("planType"), "prolite")
    }

    func testMessageIDAcceptsNumericString() {
        XCTAssertEqual(CodexAppServer.messageID(["id": "2"]), 2)
        XCTAssertEqual(CodexAppServer.messageID(["id": 2]), 2)
    }

    // MARK: - 动态窗口名

    func testDynamicWindowNameFromDurationMins() {
        let snapshot = CodexNormalizer.make(
            .init(primaryUsedPercent: 10, primaryResetAt: nil,
                  primaryWindowDurationMins: 300,
                  secondaryUsedPercent: 20, secondaryResetAt: nil,
                  secondaryWindowDurationMins: 10080,
                  planType: "prolite")
        )
        XCTAssertTrue(snapshot.primaryText.contains("5h"))
        let windows = snapshot.secondaryWindows!
        XCTAssertEqual(windows[0].name, "7d")
    }

    func testFallsBackToHardcodedNameWhenNoDurationMins() {
        let snapshot = CodexNormalizer.make(
            .init(primaryUsedPercent: 10, primaryResetAt: nil,
                  primaryWindowDurationMins: nil,
                  secondaryUsedPercent: 20, secondaryResetAt: nil,
                  secondaryWindowDurationMins: nil,
                  planType: nil)
        )
        XCTAssertTrue(snapshot.primaryText.contains("5h"))
        let windows = snapshot.secondaryWindows!
        XCTAssertEqual(windows[0].name, "7d")
    }

    // MARK: - 多 bucket

    func testExtraBucketsAppearAsSecondaryWindows() throws {
        let snapshot = CodexNormalizer.make(
            .init(primaryUsedPercent: 7, primaryResetAt: nil,
                  primaryWindowDurationMins: 300,
                  secondaryUsedPercent: 1, secondaryResetAt: nil,
                  secondaryWindowDurationMins: 10080,
                  planType: "prolite",
                  extraBuckets: [
                      .init(name: "GPT-5.3-Codex-Spark", primaryUsedPercent: 0,
                            primaryResetAt: nil, primaryWindowDurationMins: 300)
                  ])
        )
        let windows = try XCTUnwrap(snapshot.secondaryWindows)
        XCTAssertEqual(windows.count, 2)
        // 第一个是 7d 窗口
        XCTAssertEqual(windows[0].name, "7d")
        // 第二个是额外 bucket
        XCTAssertTrue(windows[1].name.contains("GPT-5.3-Codex-Spark"))
        XCTAssertEqual(windows[1].remainingPercent, 100, accuracy: 0.001)
    }

    // MARK: - formatWindowDuration

    func testFormatWindowDuration() {
        XCTAssertEqual(CodexNormalizer.formatWindowDuration(300), "5h")
        XCTAssertEqual(CodexNormalizer.formatWindowDuration(10080), "7d")
        XCTAssertEqual(CodexNormalizer.formatWindowDuration(1440), "1d")
        XCTAssertEqual(CodexNormalizer.formatWindowDuration(60), "1h")
        XCTAssertEqual(CodexNormalizer.formatWindowDuration(90), "1.5h")
        XCTAssertEqual(CodexNormalizer.formatWindowDuration(30), "30m")
        XCTAssertNil(CodexNormalizer.formatWindowDuration(nil))
        XCTAssertNil(CodexNormalizer.formatWindowDuration(0))
    }

    // MARK: - 日期解析

    func testFlexibleDateParsing() throws {
        // 秒级 epoch
        let secs = try XCTUnwrap(QuotaNormalizer.dateFromFlexible(1_700_000_000))
        XCTAssertEqual(secs.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        // 毫秒级 epoch 字符串
        let ms = try XCTUnwrap(QuotaNormalizer.dateFromFlexible("1700000000000"))
        XCTAssertEqual(ms.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
        // ISO8601
        let iso = try XCTUnwrap(QuotaNormalizer.dateFromFlexible("2026-01-15T00:00:00Z"))
        XCTAssertGreaterThan(iso.timeIntervalSince1970, 1_700_000_000)
    }
}
