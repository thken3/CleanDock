import AppKit
import ApplicationServices

enum DebugTools {
    static func dump() {
        print("accessibility trusted:", AXIsProcessTrusted())
        guard let snapshot = DockReader().snapshot() else { print("cannot read the Dock"); return }
        let r = snapshot.listFrame.integral
        print("list \(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height)) horizontal=\(snapshot.horizontal)")
        for tile in snapshot.tiles {
            print("\(tile.kind) \(tile.frame) badge=\"\(tile.badge)\" \(tile.url?.path ?? "-")")
        }
        for screen in NSScreen.screens { print("screen \(screen.localizedName) \(screen.frame) scale=\(screen.backingScaleFactor)") }
    }
}
