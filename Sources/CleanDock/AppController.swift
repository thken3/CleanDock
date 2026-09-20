import AppKit
import ApplicationServices
import CleanDockCore

enum Status { case needsPermission, disabled, noDock, verticalDock, retinaDisplay, active }

/// Wires reader, icons, cache and overlay together. Use from the main queue.
final class AppController {
    private let reader = DockReader()
    private let icons = IconSource()
    private let cache = RenderCache()
    private let overlay = OverlayWindow()
    private var last: DockSnapshot?
    private lazy var tracker = MotionTracker(reader: reader) { [weak self] in self?.apply($0) }
    private var pressed: (index: Int, at: CGPoint)?
    private var draggedIndex: Int?
    private var monitors: [Any] = []

    private(set) var status = Status.noDock

    var enabled: Bool = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "enabled")
            refresh()
        }
    }

    func start() {
        icons.onChange = { [weak self] in
            self?.cache.removeAll()
            self?.refresh()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tracker.kick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tracker.kick()
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.cache.removeAll()
            self?.tracker.kick()
        }
        installMouseMonitors()
        tracker.start()
    }

    /// Redraws from a fresh Dock read. A burst always applies its first read.
    func refresh() {
        tracker.kick()
    }

    /// Pointer position in Accessibility coordinates.
    private func pointer() -> CGPoint {
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? 0
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private func installMouseMonitors() {
        func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (AppController) -> Void) {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                if let self { handler(self) }
            }
            if let monitor { monitors.append(monitor) }
        }
        add(.leftMouseDown) { c in
            let p = c.pointer()
            guard let index = c.last?.tiles.firstIndex(where: { $0.frame.contains(p) }) else { return }
            c.pressed = (index, p)
            c.tracker.kick()
        }
        add(.leftMouseDragged) { c in
            let p = c.pointer()
            if let pressed = c.pressed, c.draggedIndex == nil, hypot(p.x - pressed.at.x, p.y - pressed.at.y) > 3 {
                c.draggedIndex = pressed.index       // show the real drag image of this tile
                c.apply(c.last)
            }
            // anything dragged near the Dock makes its tiles move apart
            if let frame = c.last?.listFrame, frame.insetBy(dx: -60, dy: -60).contains(p) { c.tracker.kick() }
        }
        add(.leftMouseUp) { c in
            guard c.pressed != nil else { return }
            c.pressed = nil
            c.draggedIndex = nil
            c.tracker.kick()
        }
    }

    func apply(_ snapshot: DockSnapshot?) {
        last = snapshot
        guard enabled else { return stop(.disabled) }
        guard AXIsProcessTrusted() else { return stop(.needsPermission) }
        guard let snapshot, !snapshot.tiles.isEmpty else { return stop(.noDock) }
        guard snapshot.horizontal else { return stop(.verticalDock) }
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? 0
        guard let screen = dockScreen(snapshot, primaryHeight: primaryHeight) else { return stop(.noDock) }
        guard screen.backingScaleFactor == 1 else { return stop(.retinaDisplay) }
        status = .active

        let scale = screen.backingScaleFactor
        let iconRects = snapshot.tiles.map { TileGeometry.iconRect(tile: $0.frame) }
        let resting = TileGeometry.restingSide(iconRects.map(\.width))
        let side = Int((resting * scale).rounded())
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        var items: [(rect: CGRect, image: CGImage)] = []
        for (index, (tile, iconRect)) in zip(snapshot.tiles, iconRects).enumerated() {
            guard index != draggedIndex,                      // the real drag image must be visible
                  iconRect.width <= resting + 0.5,            // magnified tiles stay uncovered
                  let source = icons.key(for: tile) else { continue }
            let key = RenderKey(path: source.path, modified: source.modified, side: side, dark: dark, badgeLength: tile.badge.count)
            let image = cache.image(for: key) {
                IconRenderer.render(icons.images(for: tile), side: side, cutout: BadgeCutout.rect(side: side, label: tile.badge))
            }
            guard let image else { continue }
            let local = TileGeometry.toScreenLocal(iconRect, screenFrame: screen.frame, primaryHeight: primaryHeight)
            items.append((TileGeometry.snapped(local, scale: scale), image))
        }
        overlay.show(on: screen)
        overlay.update(items)
    }

    private func stop(_ status: Status) {
        self.status = status
        overlay.clear()
    }

    /// The screen the Dock is on. The vertical margin keeps the screen while tiles bounce or slide out for auto-hide.
    private func dockScreen(_ snapshot: DockSnapshot, primaryHeight: CGFloat) -> NSScreen? {
        let centre = CGPoint(x: snapshot.listFrame.midX, y: snapshot.listFrame.midY)
        return NSScreen.screens.first { screen in
            let f = screen.frame
            return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).insetBy(dx: 0, dy: -150).contains(centre)
        }
    }
}
