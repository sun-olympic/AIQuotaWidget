import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settings: AppSettings?
    private var service: QuotaService?
    private var windowController: WidgetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let service = QuotaService(settings: settings)
        let root = ContentView(settings: settings, service: service)
        let controller = WidgetWindowController(settings: settings, service: service, rootView: root)

        self.settings = settings
        self.service = service
        self.windowController = controller

        controller.show()
        service.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        service?.stop()
    }
}
