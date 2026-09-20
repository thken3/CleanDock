import AppKit

final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: AppController
    private let state: AppState
    private let windows: Windows

    init(controller: AppController, state: AppState, windows: Windows) {
        self.controller = controller
        self.state = state
        self.windows = windows
        super.init()
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Clean Dock")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        NotificationCenter.default.addObserver(forName: .showMenuBarIconChanged, object: nil, queue: .main) { [weak self] _ in self?.update() }
        update()
    }

    /// Dimmed while Clean Dock is not drawing, so the state reads without opening the menu.
    func update() {
        item.isVisible = state.showMenuBarIcon
        item.button?.appearsDisabled = controller.status != .active
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        state.reload()
        menu.removeAllItems()
        if controller.status == .needsPermission {
            menu.addItem(action("Needs Accessibility Permission…", #selector(openAccessibilitySettings)))
        } else {
            let line = NSMenuItem(title: state.statusText, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())
        let enabled = action("Enabled", #selector(toggleEnabled))
        enabled.state = controller.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(action("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clean Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() { controller.enabled.toggle() }
    @objc private func openSettings() { windows.showSettings() }
    @objc private func openAccessibilitySettings() { state.openSettingsPane("Privacy_Accessibility") }
}
