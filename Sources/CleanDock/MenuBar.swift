import AppKit
import ServiceManagement

final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        super.init()
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Clean Dock")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch controller.status {
        case .needsPermission:
            menu.addItem(action("Accessibility Permission Needed…", #selector(openAccessibilitySettings)))
        case .disabled: menu.addItem(info("Off"))
        case .noDock: menu.addItem(info("Waiting for the Dock"))
        case .verticalDock: menu.addItem(info("Idle: the Dock is not at the bottom"))
        case .retinaDisplay: menu.addItem(info("Idle: the Dock is on a Retina display"))
        case .active: menu.addItem(info("Active"))
        }
        menu.addItem(.separator())
        let enabled = action("Enabled", #selector(toggleEnabled))
        enabled.state = controller.enabled ? .on : .off
        menu.addItem(enabled)
        let login = action("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clean Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleEnabled() { controller.enabled.toggle() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSSound.beep()      // only works from the bundled app, not from `swift run`
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
