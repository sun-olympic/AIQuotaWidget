import XCTest
@testable import AIQuotaWidget

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

    func testDefaultModelOverrideAndDeduplication() throws {
        // Test that deduplication prioritizes keeping the defaultModelId entry
        let models = [
            AntigravityNormalizer.Model(id: "m1", displayName: "Duplicate Name", remainingFraction: 0.8, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m2", displayName: "Duplicate Name", remainingFraction: 0.3, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m3", displayName: "Unique Name", remainingFraction: 0.9, resetAt: nil, isExhausted: false)
        ]

        // 1. With defaultModelId = "m1" -> should prioritize keeping m1 (80%) over m2 (30%)
        let snapshot1 = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "m1"))
        XCTAssertEqual(snapshot1.activeAntigravityModelId, "m1")
        XCTAssertEqual(snapshot1.remainingPercent, 80)
        let secondary1 = try XCTUnwrap(snapshot1.secondaryWindows)
        XCTAssertEqual(secondary1.count, 1)
        XCTAssertEqual(secondary1[0].name, "Unique Name")
        XCTAssertEqual(secondary1[0].remainingPercent, 90)

        // 2. With defaultModelId = "m2" -> should prioritize keeping m2 (30%) over m1 (80%)
        let snapshot2 = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "m2"))
        XCTAssertEqual(snapshot2.activeAntigravityModelId, "m2")
        XCTAssertEqual(snapshot2.remainingPercent, 30)
        let secondary2 = try XCTUnwrap(snapshot2.secondaryWindows)
        XCTAssertEqual(secondary2.count, 1)
        XCTAssertEqual(secondary2[0].name, "Unique Name")
        XCTAssertEqual(secondary2[0].remainingPercent, 90)
    }

    func testAlphabeticalSortingOfSwitcherModels() throws {
        let models = [
            AntigravityNormalizer.Model(id: "c", displayName: "C Model", remainingFraction: 0.8, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "a", displayName: "A Model", remainingFraction: 0.9, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "b", displayName: "B Model", remainingFraction: 1.0, resetAt: nil, isExhausted: false)
        ]
        let snapshot = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "b"))
        let switcherModels = try XCTUnwrap(snapshot.antigravityModels)
        XCTAssertEqual(switcherModels.count, 3)
        XCTAssertEqual(switcherModels[0].name, "A Model")
        XCTAssertEqual(switcherModels[1].name, "B Model")
        XCTAssertEqual(switcherModels[2].name, "C Model")
        XCTAssertEqual(snapshot.activeAntigravityModelId, "b")
    }

    func testProviderFetchWithCacheAndOverride() async throws {
        let models = [
            AntigravityNormalizer.Model(id: "m1", displayName: "Model A", remainingFraction: 0.7, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m2", displayName: "Model B", remainingFraction: 0.4, resetAt: nil, isExhausted: false)
        ]
        let rawData = AntigravityRawData(models: models, defaultModelId: "m1")
        await AntigravityCache.shared.set(rawData)
        
        // Fetch with no override (should use defaultModelId "m1")
        let provider1 = AntigravityProvider()
        let snapshot1 = try await provider1.fetch()
        XCTAssertEqual(snapshot1.activeAntigravityModelId, "m1")
        XCTAssertEqual(snapshot1.remainingPercent, 70, accuracy: 0.001)
        
        // Fetch with override "m2"
        let provider2 = AntigravityProvider(defaultModelOverride: "m2")
        let snapshot2 = try await provider2.fetch()
        XCTAssertEqual(snapshot2.activeAntigravityModelId, "m2")
        XCTAssertEqual(snapshot2.remainingPercent, 40, accuracy: 0.001)
        
        // Clean cache
        await AntigravityCache.shared.clear()
    }

    func testCoarseGroupingLogic() throws {
        let models = [
            AntigravityNormalizer.Model(id: "g1", displayName: "Gemini 2.5 Flash", remainingFraction: 1.0, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "g2", displayName: "Gemini 1.5 Pro", remainingFraction: 0.8, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "c1", displayName: "Claude 3.5 Sonnet", remainingFraction: 0.9, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "c2", displayName: "Claude 3 Haiku", remainingFraction: 0.6, resetAt: nil, isExhausted: false)
        ]

        // Case 1: defaultModelId is "g1" (Gemini 2.5 Flash).
        // Since "g1" is default, the representative for "Gemini" group should be "g1" (100%).
        // For "Claude" group, representative should be "c2" (lowest remaining: 60%).
        let snapshot1 = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "g1", coarseGrouping: true))
        XCTAssertEqual(snapshot1.activeAntigravityModelId, "g1")
        XCTAssertEqual(snapshot1.remainingPercent, 100)
        XCTAssertEqual(snapshot1.primaryText, "Gemini · 100%")
        
        let secondary1 = try XCTUnwrap(snapshot1.secondaryWindows)
        XCTAssertEqual(secondary1.count, 1)
        XCTAssertEqual(secondary1[0].name, "Claude")
        XCTAssertEqual(secondary1[0].remainingPercent, 60)
        
        let switcher1 = try XCTUnwrap(snapshot1.antigravityModels)
        XCTAssertEqual(switcher1.count, 2)
        XCTAssertEqual(switcher1[0].name, "Claude")
        XCTAssertEqual(switcher1[1].name, "Gemini")

        // Case 2: defaultModelId is "c1" (Claude 3.5 Sonnet).
        // For "Gemini" group, representative should be "g2" (lowest remaining: 80%).
        // Since "c1" is default, representative for "Claude" group should be "c1" (90%).
        let snapshot2 = try XCTUnwrap(AntigravityNormalizer.make(models: models, defaultModelId: "c1", coarseGrouping: true))
        XCTAssertEqual(snapshot2.activeAntigravityModelId, "c1")
        XCTAssertEqual(snapshot2.remainingPercent, 90)
        XCTAssertEqual(snapshot2.primaryText, "Claude · 90%")
        
        let secondary2 = try XCTUnwrap(snapshot2.secondaryWindows)
        XCTAssertEqual(secondary2.count, 1)
        XCTAssertEqual(secondary2[0].name, "Gemini")
        XCTAssertEqual(secondary2[0].remainingPercent, 80)
    }

    func testWaterBallViewSizeAndFontScaling() {
        let view96 = WaterBallView(percent: 50, leftLabel: "Left", waveEnabled: true, color: .blue, size: 96)
        XCTAssertEqual(view96.size, 96)
        
        let view64 = WaterBallView(percent: 80, leftLabel: "Left", waveEnabled: false, color: .green, size: 64)
        XCTAssertEqual(view64.size, 64)

        // Instantiate for all themes
        for theme in WidgetTheme.allCases {
            let view = WaterBallView(percent: 50, leftLabel: "Left", waveEnabled: true, color: .blue, size: 96, theme: theme)
            XCTAssertEqual(view.theme, theme)
        }
    }
}

