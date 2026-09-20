import AppKit
import ApplicationServices

enum TileKind: Equatable { case app, folder, file, trash }

struct DockTile: Equatable {
    let frame: CGRect       // Accessibility coordinates: global points, top-left origin
    let kind: TileKind
    let url: URL?
    let badge: String
}

struct DockSnapshot: Equatable {
    let tiles: [DockTile]
    let listFrame: CGRect
    let horizontal: Bool
}

/// Cheap to read; changes whenever a tile is added or removed or the Dock resizes or moves.
struct DockOutline: Equatable {
    let frame: CGRect
    let count: Int
}

/// Not thread-safe: call from one queue.
final class DockReader {
    private static let tileAttributes = [kAXPositionAttribute, kAXSizeAttribute, kAXSubroleAttribute, kAXURLAttribute, "AXStatusLabel"]
    private static let frameAttributes = [kAXPositionAttribute, kAXSizeAttribute]
    // Separators, minimized windows and unknown kinds are left to the real Dock.
    private static let kinds: [String: TileKind] = [
        "AXApplicationDockItem": .app, "AXFolderDockItem": .folder, "AXDocumentDockItem": .file, "AXTrashDockItem": .trash,
    ]

    private var dock: AXUIElement?

    /// The Dock's tile list. Looks the Dock process up again when the cached element stopped answering (Dock restarted).
    private func list() -> AXUIElement? {
        for _ in 0..<2 {
            if dock == nil {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
                dock = AXUIElementCreateApplication(app.processIdentifier)
            }
            if let children: [AXUIElement] = AX.value(dock!, kAXChildrenAttribute), let list = children.first { return list }
            dock = nil
        }
        return nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let v = AX.values(element, Self.frameAttributes), let origin = AX.point(v[0]), let size = AX.size(v[1]) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func outline() -> DockOutline? {
        guard let list = list(), let frame = frame(list), let items: [AXUIElement] = AX.value(list, kAXChildrenAttribute) else { return nil }
        return DockOutline(frame: frame, count: items.count)
    }

    func snapshot() -> DockSnapshot? {
        guard let list = list(), let listFrame = frame(list), let items: [AXUIElement] = AX.value(list, kAXChildrenAttribute) else { return nil }
        let orientation: String = AX.value(list, kAXOrientationAttribute) ?? "AXHorizontalOrientation"
        var tiles: [DockTile] = []
        for item in items {
            guard let v = AX.values(item, Self.tileAttributes), let origin = AX.point(v[0]), let size = AX.size(v[1]),
                  let kind = Self.kinds[v[2] as? String ?? ""] else { continue }
            tiles.append(DockTile(frame: CGRect(origin: origin, size: size), kind: kind, url: v[3] as? URL, badge: v[4] as? String ?? ""))
        }
        return DockSnapshot(tiles: tiles, listFrame: listFrame, horizontal: orientation == "AXHorizontalOrientation")
    }
}
