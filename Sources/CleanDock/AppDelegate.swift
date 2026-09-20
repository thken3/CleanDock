import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var menuBar: MenuBar?
    private var permissionTimer: Timer?
    private var trusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        menuBar = MenuBar(controller: controller)
        controller.start()
        // Start on its own as soon as the permission is granted, and stop when it is taken away.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = AXIsProcessTrusted()
            if now != self.trusted {
                self.trusted = now
                self.controller.refresh()
            }
        }
    }
}
