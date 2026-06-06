import XCTest
@testable import CursorQuotaWidget

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
