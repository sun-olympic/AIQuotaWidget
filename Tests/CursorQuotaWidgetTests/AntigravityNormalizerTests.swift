import XCTest
@testable import CursorQuotaWidget

final class AntigravityNormalizerTests: XCTestCase {

    func testDefaultModelIsMainDimension() throws {
        let models = [
            AntigravityNormalizer.Model(id: "google/gemini-pro", remainingFraction: 0.6, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "anthropic/claude", remainingFraction: 0.2, resetAt: nil, isExhausted: false)
        ]
        let snapshot = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "google/gemini-pro"))
        XCTAssertEqual(snapshot.remainingPercent, 60, accuracy: 0.001)
        XCTAssertEqual(snapshot.ledStatus, .green)
        let others = try XCTUnwrap(snapshot.secondaryWindows)
        XCTAssertEqual(others.count, 1)
        XCTAssertEqual(others[0].name, "claude")
        XCTAssertEqual(others[0].remainingPercent, 20, accuracy: 0.001)
    }

    func testMainDimensionYellowThreshold() throws {
        let models = [
            AntigravityNormalizer.Model(id: "m1", remainingFraction: 0.15, resetAt: nil, isExhausted: false)
        ]
        let snapshot = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "m1"))
        XCTAssertEqual(snapshot.remainingPercent, 15, accuracy: 0.001)
        XCTAssertEqual(snapshot.ledStatus, .yellow)
        XCTAssertNil(snapshot.secondaryWindows)
    }

    func testFallbackToFirstWhenDefaultMissing() throws {
        let models = [
            AntigravityNormalizer.Model(id: "a", remainingFraction: 0.8, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "b", remainingFraction: 0.3, resetAt: nil, isExhausted: false)
        ]
        let snapshot = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "nonexistent"))
        XCTAssertEqual(snapshot.remainingPercent, 80, accuracy: 0.001)
    }

    func testEmptyModelsReturnsNil() {
        XCTAssertNil(AntigravityNormalizer.make(models: [], defaultModelId: nil))
    }
}
