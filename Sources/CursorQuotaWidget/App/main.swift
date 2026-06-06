import AppKit

// Agent/Accessory 应用：不出现在 Dock 与 Cmd+Tab。
// 程序入口运行在主线程，故 assumeIsolated 到 MainActor 后再启动。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
