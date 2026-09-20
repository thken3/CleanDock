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
    private var appearanceObservation: NSKeyValueObservation?

    // F8: while the Dock is being resized, `side` changes every frame and every tile would be
    // re-rendered from 1024 px on the main queue. Wait until it has held still.
    private var lastSide: Int?
    private var sideChangedAt: TimeInterval = 0
    private var sideRefreshScheduled = false

    private(set) var status = Status.noDock

    var enabled: Bool = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "enabled")
            refresh()
        }
    }

    func start() {
        icons.onChange = { [weak self] changes in self?.iconsChanged(changes) }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tracker.kick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tracker.kick()
        }
        // The authoritative signal: it flips exactly when the rendered appearance changes.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.dropCacheAndRefresh() }
        }
        // Belt and braces for style changes the appearance does not cover. These arrive *before*
        // `effectiveAppearance` flips, so hop once through the main queue before reading anything.
        for name in ["AppleInterfaceThemeChangedNotification", "AppleColorPreferencesChangedNotification"] {
            DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.dropCacheAndRefresh() }
            }
        }
        installMouseMonitors()
        tracker.start()
    }

    /// Repaints immediately from the last snapshot (so a state-only change like `draggedTile` or the cache
    /// is never swallowed by a running burst), then kicks the tracker for a fresh read.
    func refresh() {
        // Wake a suspended tracker first: `apply` can only decide the real status from a fresh read,
        // and a suspended tracker ignores `kick()`.
        if enabled, AXIsProcessTrusted() { tracker.setMode(.watching) }
        apply(last)
        tracker.kick()
    }

    private func dropCacheAndRefresh() {
        cache.removeAll()
        refresh()
    }

    private func iconsChanged(_ changes: Set<IconChange>) {
        for change in changes {
            switch change {
            case .folder(let path): cache.remove { $0.path == path }
            case .trash: cache.remove { $0.path.hasPrefix("trash:") }
            }
        }
        refresh()
    }

    /// Height of the primary screen — `NSScreen.screens.first` is the primary by definition.
    /// `nil` only with no screen at all, and then there is nothing to draw on.
    private func primaryHeight() -> CGFloat? { NSScreen.screens.first?.frame.height }

    /// Pointer position in Accessibility coordinates.
    private func pointer() -> CGPoint? {
        guard let primaryHeight = primaryHeight() else { return nil }
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private func installMouseMonitors() {
        func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (AppController) -> Void) {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                guard let self, self.status == .active else { return }   // nothing is drawn, so nothing needs following
                handler(self)
            }
            if let monitor { monitors.append(monitor) }
        }
        add(.leftMouseDown) { c in
            c.pressed = nil                          // a missed mouse-up must not leave this armed
            c.draggedTile = nil
            guard let p = c.pointer() else { return }
            guard let tile = c.last?.tiles.first(where: { $0.frame.contains(p) }) else { return }
            c.pressed = (TileIdentity(kind: tile.kind, url: tile.url), p)
            c.tracker.kick()
        }
        add(.leftMouseDragged) { c in
            guard let p = c.pointer() else { return }
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
        guard let primaryHeight = primaryHeight() else { return stop(.noDock) }
        guard let screen = dockScreen(snapshot, primaryHeight: primaryHeight) else { return stop(.noDock) }
        guard screen.backingScaleFactor == 1 else { return stop(.retinaDisplay) }
        setStatus(.active)

        let scale = screen.backingScaleFactor
        let iconRects = snapshot.tiles.map { TileGeometry.iconRect(tile: $0.frame) }
        let resting = TileGeometry.restingSide(iconRects.map(\.width))
        let side = Int((resting * scale).rounded())
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let now = ProcessInfo.processInfo.systemUptime
        if let lastSide, side != lastSide {
            // The Dock is being resized: leave every tile to the real Dock for this frame and come
            // back once the size has held still. (The first apply of a session is not a change.)
            self.lastSide = side
            sideChangedAt = now
            scheduleSideRefresh()
            overlay.show(on: screen)
            overlay.update([])
            return
        }
        lastSide = side
        let sideSettled = now - sideChangedAt >= 0.2
        if !sideSettled { scheduleSideRefresh() }

        var items: [(rect: CGRect, image: CGImage)] = []
        for (tile, iconRect) in zip(snapshot.tiles, iconRects) {
            guard TileIdentity(kind: tile.kind, url: tile.url) != draggedTile,   // the real drag image must be visible
                  iconRect.width <= resting + 0.5,            // magnified tiles stay uncovered
                  let source = icons.key(for: tile) else { continue }
            let key = RenderKey(path: source.path, modified: source.modified, side: side, dark: dark,
                                badgeLength: tile.badge.count, variant: source.variant)
            // Until the side has held still, a cached render may be shown but nothing new is rendered.
            let image = sideSettled
                ? cache.image(for: key) {
                    IconRenderer.render(icons.images(for: tile), side: side, cutout: BadgeCutout.rect(side: side, label: tile.badge))
                }
                : cache.peek(for: key)
            guard let image else { continue }
            let local = TileGeometry.toScreenLocal(iconRect, screenFrame: screen.frame, primaryHeight: primaryHeight)
            items.append((TileGeometry.snapped(local, scale: scale), image))
        }
        overlay.show(on: screen)
        overlay.update(items)
    }

    /// One pending repaint at a time, so a drag across a dozen Dock sizes costs one extra `apply`.
    private func scheduleSideRefresh() {
        guard !sideRefreshScheduled else { return }
        sideRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.sideRefreshScheduled = false
            self.refresh()
        }
    }

    private func stop(_ status: Status) {
        setStatus(status)
        overlay.clear()
    }

    /// The single place the status changes, so everything that costs time while the overlay is not
    /// drawn is switched off with it.
    private func setStatus(_ new: Status) {
        status = new
        tracker.setMode(Self.mode(for: new))
        let hasTrash = last?.tiles.contains { $0.kind == .trash } ?? false
        icons.setTrashPolling(new == .active && hasTrash)
    }

    private static func mode(for status: Status) -> MotionTracker.Mode {
        switch status {
        case .active: return .tracking
        // Still worth one read now and then: it is what notices the Dock moving back to a 1x display.
        case .noDock, .verticalDock, .retinaDisplay: return .watching
        case .disabled, .needsPermission: return .suspended
        }
    }

    /// The screen the Dock is on, by exact containment first so stacked displays cannot steal each other's
    /// Dock. The vertical margin keeps the screen while tiles bounce or slide out for auto-hide.
    private func dockScreen(_ snapshot: DockSnapshot, primaryHeight: CGFloat) -> NSScreen? {
        let screens = NSScreen.screens
        let frames = screens.map { TileGeometry.accessibilityFrame($0.frame, primaryHeight: primaryHeight) }
        let centre = CGPoint(x: snapshot.listFrame.midX, y: snapshot.listFrame.midY)
        guard let index = TileGeometry.screenIndex(containing: centre, screens: frames, margin: 150) else { return nil }
        return screens[index]
    }
}
