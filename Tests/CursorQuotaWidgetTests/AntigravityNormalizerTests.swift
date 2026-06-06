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

    func testDumpRealModels() throws {
        let url = URL(fileURLWithPath: "/Users/sunqilei/Documents/GitHub/Personal/CursorQuotaWidget/models.json")
        let data = try Data(contentsOf: url)
        if let snapshot = AntigravityProvider.normalize(data) {
            print("--- SNAPSHOT ---")
            print("Remaining percent: \(snapshot.remainingPercent)")
            print("Primary text: \(snapshot.primaryText)")
            if let windows = snapshot.secondaryWindows {
                print("Secondary windows count: \(windows.count)")
                for w in windows {
                    print("  - \(w.name): \(w.remainingPercent)% (resetAt: \(String(describing: w.resetAt)))")
                }
            } else {
                print("No secondary windows")
            }
        } else {
            print("Failed to normalize models.json")
        }
    }
    func testDeduplicationAndSorting() throws {
        let models = [
            AntigravityNormalizer.Model(id: "m1", displayName: "Gemini 3.1 Flash Lite", remainingFraction: 0.8, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m2", displayName: "Gemini 3.1 Flash Lite", remainingFraction: 0.5, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m3", displayName: "Claude Sonnet 4.6 (Thinking)", remainingFraction: 0.9, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m4", displayName: "Gemini 3.5 Flash (Medium)", remainingFraction: 1.0, resetAt: nil, isExhausted: false),
        ]
        
        let snapshot = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "m4"))
        
        XCTAssertEqual(snapshot.remainingPercent, 100)
        XCTAssertEqual(snapshot.primaryText, "Gemini 3.5 Flash (Medium) · 100%")
        
        let secondary = try XCTUnwrap(snapshot.secondaryWindows)
        XCTAssertEqual(secondary.count, 2)
        
        XCTAssertEqual(secondary[0].name, "Gemini 3.1 Flash Lite")
        XCTAssertEqual(secondary[0].remainingPercent, 50, accuracy: 0.001)
        
        XCTAssertEqual(secondary[1].name, "Claude Sonnet 4.6 (Thinking)")
        XCTAssertEqual(secondary[1].remainingPercent, 90, accuracy: 0.001)
    }
}

