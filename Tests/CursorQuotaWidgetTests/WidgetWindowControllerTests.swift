import XCTest
import SwiftUI
@testable import CursorQuotaWidget

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
}
