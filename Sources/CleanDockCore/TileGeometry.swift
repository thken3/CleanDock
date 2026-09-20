import CoreGraphics

public enum TileGeometry {
    /// Icon canvas inside a Dock tile frame, in the same coordinate space as `tile`.
    /// The Dock pads tiles by 2 pt (height − width = 12) below tile size 48 and by 4 pt (height − width = 16) from 48 up.
    public static func iconRect(tile: CGRect) -> CGRect {
        let pad: CGFloat = tile.height - tile.width >= 14 ? 4 : 2
        let side = max(tile.width - pad, 0)
        return CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
    }

    /// A screen's Cocoa frame (bottom-left origin, y up) in Accessibility coordinates (global, top-left origin).
    /// `primaryHeight` is the height of the screen whose Cocoa origin is (0, 0).
    public static func accessibilityFrame(_ screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX, y: primaryHeight - screenFrame.maxY, width: screenFrame.width, height: screenFrame.height)
    }

    /// Accessibility coordinates (global, top-left origin) to coordinates local to a screen (top-left origin).
    /// `screenFrame` is the Cocoa frame of the screen, `primaryHeight` the height of the screen whose Cocoa origin is (0, 0).
    public static func toScreenLocal(_ r: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        let frame = accessibilityFrame(screenFrame, primaryHeight: primaryHeight)
        return CGRect(x: r.minX - frame.minX, y: r.minY - frame.minY, width: r.width, height: r.height)
    }

    /// The screen a point belongs to, given screen frames already in Accessibility coordinates.
    ///
    /// Exact containment decides first, so vertically stacked displays cannot steal each other's Dock.
    /// Only when no screen contains the point — the Dock slid out for auto-hide, or its tiles bounce past
    /// the edge — do we retry with the frames grown by `margin` vertically, and then take the nearest one.
    public static func screenIndex(containing point: CGPoint, screens: [CGRect], margin: CGFloat) -> Int? {
        if let exact = screens.firstIndex(where: { $0.contains(point) }) { return exact }
        var best: (index: Int, distance: CGFloat)?
        for (index, frame) in screens.enumerated() {
            guard frame.insetBy(dx: 0, dy: -margin).contains(point) else { continue }
            let distance = max(0, frame.minY - point.y, point.y - frame.maxY)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// Origin and side rounded to whole pixels. The result is square.
    public static func snapped(_ r: CGRect, scale: CGFloat) -> CGRect {
        let side = (r.width * scale).rounded() / scale
        return CGRect(x: (r.minX * scale).rounded() / scale, y: (r.minY * scale).rounded() / scale, width: side, height: side)
    }

    /// The icon side most tiles have. Tiles that grow in, shrink out or are magnified differ from it.
    public static func restingSide(_ sides: [CGFloat]) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        for side in sides { counts[side.rounded(), default: 0] += 1 }
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
    }
}
