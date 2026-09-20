import CoreGraphics

public enum BadgeCutout {
    /// Region of a side×side icon bitmap (pixels, top-left origin) that stays transparent so the real badge shows through.
    public static func rect(side: Int, label: String) -> CGRect? {
        guard !label.isEmpty, side > 0 else { return nil }
        let s = Double(side)
        let width = min(Int((s * (0.47 + 0.06 * Double(label.count - 1))).rounded(.up)) + 1, side * 3 / 4)
        let height = Int((s * 0.41).rounded(.up)) + 1
        return CGRect(x: side - width, y: 0, width: width, height: height)
    }
}
