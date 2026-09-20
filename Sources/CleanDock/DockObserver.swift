import AppKit
import ApplicationServices

/// Hears from the Dock itself when a tile is created or destroyed: an app launch, a minimized window,
/// a restored window, a file dropped in. The Dock posts these at once, so the tracker starts following
/// the animation without waiting for its next idle check. Use from the main queue.
final class DockObserver {
    private let onChange: () -> Void
    private var observer: AXObserver?
    private var pid: pid_t = 0

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Attaches to the running Dock. Cheap when already attached to that process; call again after the Dock
    /// restarts or once Accessibility permission is granted.
    func attach() {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              dock.processIdentifier != pid || observer == nil else { return }
        detach()
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<DockObserver>.fromOpaque(context).takeUnretainedValue().onChange()
        }
        guard AXObserverCreate(dock.processIdentifier, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let context = Unmanaged.passUnretained(self).toOpaque()
        // The only tile notifications the Dock supports; moved, resized and layout-changed are refused.
        for name in [kAXCreatedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(created, app, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        pid = dock.processIdentifier
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        pid = 0
    }

    deinit { detach() }
}
