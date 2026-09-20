import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private lazy var state = AppState(controller: controller)
    private lazy var windows = Windows(state: state)
    private var menuBar: MenuBar?
    private var permissionTimer: Timer?
    private var trusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        trusted = AXIsProcessTrusted()
        menuBar = MenuBar(controller: controller, state: state, windows: windows)
        controller.onChange = { [weak self] in
            self?.state.reload()
            self?.menuBar?.update()
        }
        controller.start()
        // The first-run window explains the permission before macOS asks for it.
        if !trusted || !UserDefaults.standard.bool(forKey: "didFirstRun") { windows.showFirstRun() }
        if CommandLine.arguments.contains("--settings") { windows.showSettings() }        // for development
        if CommandLine.arguments.contains("--first-run") { windows.showFirstRun() }
        // Start on its own as soon as the permission is granted, and stop when it is taken away.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = AXIsProcessTrusted()
            if now != self.trusted {
                self.trusted = now
                self.controller.refresh()
                self.state.reload()
            }
        }
    }

    /// Launching Clean Dock again is how the settings open when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        windows.showSettings()
        return false
    }
}
