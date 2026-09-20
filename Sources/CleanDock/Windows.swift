import AppKit
import SwiftUI

/// Creates and shows the settings and first-run windows. Both are fixed-size. Use from the main queue.
final class Windows: NSObject, NSWindowDelegate {
    private let state: AppState
    private var settings: NSWindow?
    private var firstRun: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func showSettings() {
        if settings == nil {
            settings = make(title: "Clean Dock", style: [.titled, .closable, .miniaturizable], content: SettingsView(state: state))
        }
        present(settings)
    }

    func showFirstRun() {
        if firstRun == nil {
            firstRun = make(title: "Clean Dock", style: [.titled, .closable],
                            content: FirstRunView(state: state) { [weak self] in self?.firstRun?.close() })
        }
        present(firstRun)
    }

    private func make<Content: View>(title: String, style: NSWindow.StyleMask, content: Content) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        state.setLive(true)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === firstRun { UserDefaults.standard.set(true, forKey: "didFirstRun") }
        let other = closing === settings ? firstRun : settings
        if other?.isVisible != true { state.setLive(false) }     // nothing left to keep fresh
    }
}
