import CoreGraphics

public enum TileGeometry {
    /// Icon canvas inside a Dock tile frame, in the same coordinate space as `tile`.
    /// The Dock pads tiles by 2 pt (height − width = 12) below tile size 48 and by 4 pt (height − width = 16) from 48 up.
    public static func iconRect(tile: CGRect) -> CGRect {
        let pad: CGFloat = tile.height - tile.width >= 14 ? 4 : 2
        let side = max(tile.width - pad, 0)
        return CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
    }

    /// Accessibility coordinates (global, top-left origin) to coordinates local to a screen (top-left origin).
    /// `screenFrame` is the Cocoa frame of the screen, `primaryHeight` the height of the screen whose Cocoa origin is (0, 0).
    public static func toScreenLocal(_ r: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX - screenFrame.minX, y: r.minY - (primaryHeight - screenFrame.maxY), width: r.width, height: r.height)
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
