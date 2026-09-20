import AppKit
import ApplicationServices
import CleanDockCore

enum Status { case needsPermission, disabled, noDock, verticalDock, retinaDisplay, active }

/// Identifies a tile by what it is, not by its position in the list — the list reorders live during a drag.
private struct TileIdentity: Equatable {
    let kind: TileKind
    let url: URL?
}

/// Wires reader, icons, cache and overlay together. Use from the main queue.
final class AppController {
    private let reader = DockReader()
    private let icons = IconSource()
    private let cache = RenderCache()
    private let overlay = OverlayWindow()
    private var last: DockSnapshot?
    private lazy var tracker = MotionTracker(reader: reader) { [weak self] in self?.apply($0) }
    private var pressed: (identity: TileIdentity, at: CGPoint)?
    private var draggedTile: TileIdentity?
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
            self?.refresh()
        }
        installMouseMonitors()
        icons.startTrashPolling()
        tracker.start()
    }

    /// Repaints immediately from the last snapshot (so a state-only change like `draggedTile` or the cache
    /// is never swallowed by a running burst), then kicks the tracker for a fresh read.
    func refresh() {
        apply(last)
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
            c.pressed = nil                          // a missed mouse-up must not leave this armed
            let p = c.pointer()
            guard let tile = c.last?.tiles.first(where: { $0.frame.contains(p) }) else { return }
            c.pressed = (TileIdentity(kind: tile.kind, url: tile.url), p)
            c.tracker.kick()
        }
        add(.leftMouseDragged) { c in
            let p = c.pointer()
            if let pressed = c.pressed, c.draggedTile == nil, hypot(p.x - pressed.at.x, p.y - pressed.at.y) > 3 {
                c.draggedTile = pressed.identity     // show the real drag image of this tile
                c.apply(c.last)
            }
            // anything dragged near the Dock makes its tiles move apart
            if let frame = c.last?.listFrame, frame.insetBy(dx: -60, dy: -60).contains(p) { c.tracker.kick() }
        }
        add(.leftMouseUp) { c in
            guard c.pressed != nil else { return }
            c.pressed = nil
            c.draggedTile = nil
            c.refresh()
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
        for (tile, iconRect) in zip(snapshot.tiles, iconRects) {
            guard TileIdentity(kind: tile.kind, url: tile.url) != draggedTile,   // the real drag image must be visible
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
