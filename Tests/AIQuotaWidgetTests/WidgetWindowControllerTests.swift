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

    private func getSafeOrigin() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        return CGPoint(x: visibleFrame.midX - 160, y: visibleFrame.midY - 110)
    }

    @MainActor
    func testWindowHeightResizingOnTabChange() throws {
        let settings = AppSettings()
        // Ensure selectedTab is initially cursor
        settings.selectedTab = .cursor
        
        let controller = WidgetWindowController(settings: settings, rootView: TestView(settings: settings))
        controller.panel.setFrameOrigin(getSafeOrigin())
        
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

    func testAutoCollapsePersistence() throws {
        let suiteName = "test.AIQuotaWidget.AppSettings.AutoCollapse"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        var settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.autoCollapse) // Default should be true
        XCTAssertFalse(settings.isCollapsed) // Default should be false
        
        settings.autoCollapse = false
        
        // Re-init settings to see if it retrieves from defaults
        settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.autoCollapse)
        
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testWindowAdaptiveHeightAndTopRightAnchoring() throws {
        let suiteName = "test.AIQuotaWidget.WindowController.Adaptive"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        let settings = AppSettings(defaults: defaults)
        settings.selectedTab = .cursor
        settings.isCollapsed = false
        
        let service = QuotaService(settings: settings)
        
        let controller = WidgetWindowController(settings: settings, service: service, rootView: ContentView(settings: settings, service: service))
        controller.panel.setFrameOrigin(getSafeOrigin())
        
        // Let's check initial size (no service loaded yet, so height is 220)
        XCTAssertEqual(controller.panel.frame.size.width, 320)
        XCTAssertEqual(controller.panel.frame.size.height, 220)
        
        let initialTopRightX = controller.panel.frame.origin.x + controller.panel.frame.size.width
        let initialTopRightY = controller.panel.frame.origin.y + controller.panel.frame.size.height
        
        // Test collapse state: 80x80
        settings.isCollapsed = true
        
        let expectation1 = self.expectation(description: "Collapse complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(controller.panel.frame.size.width, 120)
            XCTAssertEqual(controller.panel.frame.size.height, 120)
            
            let collapsedTopRightX = controller.panel.frame.origin.x + controller.panel.frame.size.width
            let collapsedTopRightY = controller.panel.frame.origin.y + controller.panel.frame.size.height
            XCTAssertEqual(initialTopRightX, collapsedTopRightX, accuracy: 0.001)
            XCTAssertEqual(initialTopRightY, collapsedTopRightY, accuracy: 0.001)
            
            // Expand again
            settings.isCollapsed = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertEqual(controller.panel.frame.size.width, 320)
                XCTAssertEqual(controller.panel.frame.size.height, 220)
                
                let expandedTopRightX = controller.panel.frame.origin.x + controller.panel.frame.size.width
                let expandedTopRightY = controller.panel.frame.origin.y + controller.panel.frame.size.height
                XCTAssertEqual(initialTopRightX, expandedTopRightX, accuracy: 0.001)
                XCTAssertEqual(initialTopRightY, expandedTopRightY, accuracy: 0.001)
                
                expectation1.fulfill()
            }
        }
        
        waitForExpectations(timeout: 2.0, handler: nil)
        
        // Clean up
        service.stop()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testWindowHeightAdaptsToServiceDataAndAnchorsTopRight() async throws {
        let suiteName = "test.AIQuotaWidget.WindowController.AdaptiveHeight"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        let settings = AppSettings(defaults: defaults)
        settings.selectedTab = .antigravity
        settings.coarseModelGrouping = false
        
        // Cache 5 models
        let models = [
            AntigravityNormalizer.Model(id: "m1", displayName: "Model 1", remainingFraction: 1.0, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m2", displayName: "Model 2", remainingFraction: 0.9, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m3", displayName: "Model 3", remainingFraction: 0.8, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m4", displayName: "Model 4", remainingFraction: 0.7, resetAt: nil, isExhausted: false),
            AntigravityNormalizer.Model(id: "m5", displayName: "Model 5", remainingFraction: 0.6, resetAt: nil, isExhausted: false)
        ]
        let rawData = AntigravityRawData(models: models, defaultModelId: "m1")
        await AntigravityCache.shared.set(rawData)
        
        let service = QuotaService(settings: settings)
        
        let controller = WidgetWindowController(settings: settings, service: service, rootView: ContentView(settings: settings, service: service))
        controller.panel.setFrameOrigin(getSafeOrigin())
        
        let initialTopRightX = controller.panel.frame.origin.x + controller.panel.frame.size.width
        let initialTopRightY = controller.panel.frame.origin.y + controller.panel.frame.size.height
        
        // Start service to trigger refresh
        service.start()
        
        let expectation = self.expectation(description: "Data loaded and window resized")
        var cancellables = Set<AnyCancellable>()
        
        service.$antigravityState
            .sink { state in
                if case .loaded(let snapshot) = state {
                    if let windows = snapshot.secondaryWindows, windows.count == 4 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            XCTAssertEqual(controller.panel.frame.size.width, 320)
                            XCTAssertEqual(controller.panel.frame.size.height, 295)
                            
                            let newTopRightX = controller.panel.frame.origin.x + controller.panel.frame.size.width
                            let newTopRightY = controller.panel.frame.origin.y + controller.panel.frame.size.height
                            
                            XCTAssertEqual(initialTopRightX, newTopRightX, accuracy: 0.001)
                            XCTAssertEqual(initialTopRightY, newTopRightY, accuracy: 0.001)
                            expectation.fulfill()
                        }
                    }
                }
            }
            .store(in: &cancellables)
            
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Clean up
        service.stop()
        await AntigravityCache.shared.clear()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testWindowClampsToScreenBoundaries() throws {
        if let screen = NSScreen.main {
            print("--- DEBUG visibleFrame: \(screen.visibleFrame)")
        }
        let settings = AppSettings()
        let controller = WidgetWindowController(settings: settings, rootView: Text("Test"))
        
        guard let screen = NSScreen.main else {
            return
        }
        let visibleFrame = screen.visibleFrame
        
        // Try to position window way off-screen to the right/top
        let offScreenRect = NSRect(x: visibleFrame.maxX + 100, y: visibleFrame.maxY + 100, width: 320, height: 220)
        controller.panel.setFrame(offScreenRect, display: true)
        
        // It should be clamped to the screen edge
        XCTAssertEqual(controller.panel.frame.size.width, 320)
        XCTAssertEqual(controller.panel.frame.size.height, 220)
        XCTAssertEqual(controller.panel.frame.origin.x, visibleFrame.maxX - 320, accuracy: 0.001)
        XCTAssertEqual(controller.panel.frame.origin.y, visibleFrame.maxY - 220, accuracy: 0.001)
        
        // Try to position window way off-screen to the left/bottom
        let offScreenRect2 = NSRect(x: visibleFrame.minX - 100, y: visibleFrame.minY - 100, width: 320, height: 220)
        controller.panel.setFrame(offScreenRect2, display: true)
        
        XCTAssertEqual(controller.panel.frame.origin.x, visibleFrame.minX, accuracy: 0.001)
        XCTAssertEqual(controller.panel.frame.origin.y, visibleFrame.minY, accuracy: 0.001)
    }

    func testWidgetThemePersistence() throws {
        let suiteName = "test.AIQuotaWidget.AppSettings.WidgetTheme"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }
        
        var settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.widgetTheme, .waterBall) // Default should be waterBall
        
        settings.widgetTheme = .doraemon
        
        // Re-init settings to see if it retrieves from defaults
        settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.widgetTheme, .doraemon)
        
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
