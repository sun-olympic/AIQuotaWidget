import XCTest
@testable import AIQuotaWidget

final class QuotaNormalizerTests: XCTestCase {

    // MARK: - LED 阈值

    func testLEDThresholds() {
        XCTAssertEqual(LEDStatus.from(remainingPercent: 50), .green)
        XCTAssertEqual(LEDStatus.from(remainingPercent: 20), .green)
        XCTAssertEqual(LEDStatus.from(remainingPercent: 19.9), .yellow)
        XCTAssertEqual(LEDStatus.from(remainingPercent: 10), .yellow)
        XCTAssertEqual(LEDStatus.from(remainingPercent: 9.9), .red)
        XCTAssertEqual(LEDStatus.from(remainingPercent: 0), .red)
    }

    // MARK: - Legacy 归一化

    func testLegacyRemainingPercent() {
        let snapshot = QuotaNormalizer.legacy(
            .init(numRequests: 262, maxRequestUsage: 500, startOfMonth: nil, planName: "PRO")
        )
        // (500 - 262) / 500 * 100 = 47.6
        XCTAssertEqual(snapshot.remainingPercent, 47.6, accuracy: 0.001)
        XCTAssertEqual(snapshot.primaryText, "262 / 500 requests")
        XCTAssertEqual(snapshot.mode, .legacy)
        XCTAssertEqual(snapshot.planName, "PRO")
        XCTAssertNil(snapshot.onDemand)
    }

    func testLegacyZeroMaxDoesNotCrash() {
        let snapshot = QuotaNormalizer.legacy(
            .init(numRequests: 5, maxRequestUsage: 0, startOfMonth: nil, planName: nil)
        )
        XCTAssertEqual(snapshot.remainingPercent, 0)
    }

    func testLegacyResetDatePlusOneMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let snapshot = QuotaNormalizer.legacy(
            .init(numRequests: 1, maxRequestUsage: 10, startOfMonth: "2026-01-15T00:00:00.000Z", planName: nil),
            calendar: cal
        )
        let reset = try? XCTUnwrap(snapshot.resetAt)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 2; comps.day = 15
        let expected = cal.date(from: comps)
        XCTAssertEqual(reset?.timeIntervalSince1970, expected?.timeIntervalSince1970)
    }

    // MARK: - Usage-based 归一化

    func testUsageBasedFromRemainingAndLimit() {
        let snapshot = QuotaNormalizer.usageBased(
            .init(totalPercentUsed: nil,
                  remainingCents: 16778,
                  limitCents: 20000,
                  billingCycleEndMillis: nil,
                  planName: "Ultra",
                  spendLimitUsedCents: nil,
                  spendLimitTotalCents: nil)
        )
        XCTAssertEqual(snapshot.primaryText, "$167.78 left")
        // 16778 / 20000 * 100 = 83.89
        XCTAssertEqual(snapshot.remainingPercent, 83.89, accuracy: 0.001)
        XCTAssertEqual(snapshot.mode, .usageBased)
    }

    func testUsageBasedFromTotalPercentUsed() {
        let snapshot = QuotaNormalizer.usageBased(
            .init(totalPercentUsed: 30,
                  remainingCents: nil,
                  limitCents: 20000,
                  billingCycleEndMillis: nil,
                  planName: nil,
                  spendLimitUsedCents: nil,
                  spendLimitTotalCents: nil)
        )
        XCTAssertEqual(snapshot.remainingPercent, 70, accuracy: 0.001)
    }

    func testUsageBasedOnDemandSeparated() throws {
        let snapshot = QuotaNormalizer.usageBased(
            .init(totalPercentUsed: 10,
                  remainingCents: 18000,
                  limitCents: 20000,
                  billingCycleEndMillis: nil,
                  planName: nil,
                  spendLimitUsedCents: 500,
                  spendLimitTotalCents: 5000)
        )
        let onDemand = try XCTUnwrap(snapshot.onDemand)
        XCTAssertEqual(onDemand.usedDollars, 5, accuracy: 0.001)
        XCTAssertEqual(onDemand.limitDollars, 50, accuracy: 0.001)
        // 主水位不并入 on-demand
        XCTAssertEqual(snapshot.remainingPercent, 90, accuracy: 0.001)
    }

    func testMillisTimestampParsing() throws {
        let date = try XCTUnwrap(QuotaNormalizer.dateFromMillisString("1700000000000"))
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    // MARK: - 计费模型探测

    func testUsageBasedDetection() {
        XCTAssertTrue(QuotaNormalizer.isUsageBasedActive(limitCents: 20000, totalPercentUsed: 5))
        XCTAssertFalse(QuotaNormalizer.isUsageBasedActive(limitCents: nil, totalPercentUsed: nil))
        XCTAssertFalse(QuotaNormalizer.isUsageBasedActive(limitCents: 0, totalPercentUsed: nil))
    }
}

final class RedactionTests: XCTestCase {
    func testRedactsJWT() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NSJ9.abcDEF123_-"
        let message = "request failed with token \(token) oops"
        let redacted = Redaction.redact(message)
        XCTAssertFalse(redacted.contains(token))
        XCTAssertTrue(redacted.contains("<redacted-token>"))
    }

    func testRedactsFilePath() {
        let message = "could not open /Users/someone/Library/Application Support/Cursor/state.vscdb"
        let redacted = Redaction.redact(message)
        XCTAssertFalse(redacted.contains("/Users/someone"))
        XCTAssertTrue(redacted.contains("<redacted-path>"))
    }
}
