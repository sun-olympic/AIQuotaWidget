import XCTest
import SwiftUI
import Combine
@testable import AIQuotaWidget

final class WidgetWindowControllerTests: XCTestCase {

    struct TestView: View {
        @ObservedObject var settings: AppSettings
        var body: some View {
            Text("Test")
                .frame(width: 320, height: settings.selectedTab == .antigravity ? 320 : 220)
        }
    }

    @MainActor
    func testWindowHeightResizingOnTabChange() throws {
        let settings = AppSettings()
        // Ensure selectedTab is initially cursor
        settings.selectedTab = .cursor
        
        let controller = WidgetWindowController(settings: settings, rootView: TestView(settings: settings))
        
        // Check initial height is defaultSize.height (220)
        XCTAssertEqual(controller.panel.frame.size.height, 220)
        let initialTop = controller.panel.frame.origin.y + controller.panel.frame.size.height
        
        // Change selectedTab to antigravity
        settings.selectedTab = .antigravity
        
        // Wait for next run loop iteration so that sink executes on MainActor
        let expectation = self.expectation(description: "Resize complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(controller.panel.frame.size.height, 320)
            let newTop = controller.panel.frame.origin.y + controller.panel.frame.size.height
            // Verify top edge remains unchanged
            XCTAssertEqual(initialTop, newTop, accuracy: 0.001)
            
            // Change back to cursor
            settings.selectedTab = .cursor
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(controller.panel.frame.size.height, 220)
                let finalTop = controller.panel.frame.origin.y + controller.panel.frame.size.height
                XCTAssertEqual(initialTop, finalTop, accuracy: 0.001)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0, handler: nil)
    }

    func testEnabledTabsAndSelectedTabValidation() throws {
        // Use a clean temporary UserDefaults to isolate the test
        let suiteName = "test.AIQuotaWidget.AppSettings"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        let settings = AppSettings(defaults: defaults)
        
        // Initial setup should have all cases enabled and selected tab as cursor
        XCTAssertEqual(settings.enabledTabs, ProductTab.allCases)
        XCTAssertEqual(settings.selectedTab, .cursor)
        
        // Disable codex and antigravity (leaving only cursor)
        settings.enabledTabs = [.cursor]
        XCTAssertEqual(settings.selectedTab, .cursor)
        
        // Try setting selectedTab to a disabled tab (.codex)
        settings.selectedTab = .codex
        // Should immediately trigger ensureSelectedTabValid and reset to the first enabled tab (.cursor)
        settings.ensureSelectedTabValid()
        XCTAssertEqual(settings.selectedTab, .cursor)
        
        // Change enabledTabs to [.antigravity, .codex] (selectedTab .cursor is now disabled)
        settings.enabledTabs = [.antigravity, .codex]
        // selectedTab should automatically fall back to the first enabled tab (.antigravity)
        XCTAssertEqual(settings.selectedTab, .antigravity)
        
        // Clean up
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testAntigravityDefaultModelIdPersistence() throws {
        let suiteName = "test.AIQuotaWidget.AppSettings.ModelId"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        var settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.antigravityDefaultModelId)
        
        settings.antigravityDefaultModelId = "google/gemini-flash"
        
        // Re-init settings to see if it retrieves from defaults
        settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.antigravityDefaultModelId, "google/gemini-flash")
        
        // Test clear
        settings.antigravityDefaultModelId = nil
        settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.antigravityDefaultModelId)
        
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testQuotaServiceReactsToModelIdChange() async throws {
        let suiteName = "test.AIQuotaWidget.QuotaService.ModelId"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        let settings = AppSettings(defaults: defaults)
        settings.selectedTab = .antigravity
        
        let models = [
            AntigravityNormalizer.Model(id: "m1", displayName: "Model A", remainingFraction: 0.7, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m2", displayName: "Model B", remainingFraction: 0.4, resetAt: nil, isExhausted: false)
        ]
        let rawData = AntigravityRawData(models: models, defaultModelId: "m1")
        await AntigravityCache.shared.set(rawData)
        
        let service = QuotaService(settings: settings)
        
        // Trigger initial refresh
        service.start()
        
        // Wait for state to load
        let expectation = self.expectation(description: "First load")
        var cancellables = Set<AnyCancellable>()
        service.$antigravityState
            .sink { state in
                if case .loaded(let snapshot) = state {
                    if snapshot.activeAntigravityModelId == "m1" {
                        expectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellables.removeAll()
        
        // Now, change antigravityDefaultModelId to "m2"
        let expectation2 = self.expectation(description: "Second load after model override change")
        service.$antigravityState
            .sink { state in
                if case .loaded(let snapshot) = state {
                    if snapshot.activeAntigravityModelId == "m2" {
                        expectation2.fulfill()
                    }
                }
            }
            .store(in: &cancellables)
        
        settings.antigravityDefaultModelId = "m2"
        
        await fulfillment(of: [expectation2], timeout: 1.0)
        
        // Clean up
        service.stop()
        await AntigravityCache.shared.clear()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testCoarseModelGroupingPersistence() throws {
        let suiteName = "test.AIQuotaWidget.AppSettings.CoarseGrouping"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        var settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.coarseModelGrouping) // Default should be true
        
        settings.coarseModelGrouping = false
        
        // Re-init settings to see if it retrieves from defaults
        settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.coarseModelGrouping)
        
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testQuotaServiceReactsToCoarseModelGroupingChange() async throws {
        let suiteName = "test.AIQuotaWidget.QuotaService.CoarseGrouping"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        let settings = AppSettings(defaults: defaults)
        settings.selectedTab = .antigravity
        
        let models = [
            AntigravityNormalizer.Model(id: "m1", displayName: "Gemini 3.5 Flash", remainingFraction: 0.7, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m2", displayName: "Claude Sonnet", remainingFraction: 0.4, resetAt: nil, isExhausted: false)
        ]
        let rawData = AntigravityRawData(models: models, defaultModelId: "m1")
        await AntigravityCache.shared.set(rawData)
        
        let service = QuotaService(settings: settings)
        service.start()
        
        // Wait for first load (coarseModelGrouping default: true)
        let expectation = self.expectation(description: "First load - coarse")
        var cancellables = Set<AnyCancellable>()
        service.$antigravityState
            .sink { state in
                if case .loaded(let snapshot) = state {
                    if let list = snapshot.antigravityModels, list.count == 2,
                       list[0].name == "Claude", list[1].name == "Gemini" {
                        expectation.fulfill()
                    }
                }
            }
            .store(in: &cancellables)
            
        await fulfillment(of: [expectation], timeout: 1.0)
        cancellables.removeAll()
        
        // Now change settings.coarseModelGrouping to false
        let expectation2 = self.expectation(description: "Second load - fine-grained")
        service.$antigravityState
            .sink { state in
                if case .loaded(let snapshot) = state {
                    if let list = snapshot.antigravityModels, list.count == 2,
                       list[0].name == "Claude Sonnet", list[1].name == "Gemini 3.5 Flash" {
                        expectation2.fulfill()
                    }
                }
            }
            .store(in: &cancellables)
            
        settings.coarseModelGrouping = false
        
        await fulfillment(of: [expectation2], timeout: 1.0)
        
        // Clean up
        service.stop()
        await AntigravityCache.shared.clear()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
