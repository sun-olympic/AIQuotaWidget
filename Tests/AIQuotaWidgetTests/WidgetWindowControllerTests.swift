import XCTest
import SwiftUI
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
}
