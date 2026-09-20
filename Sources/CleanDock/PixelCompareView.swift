import SwiftUI

/// Draws two same-sized bitmaps on whole device pixels, the first left of the divider and the second right
/// of it. SwiftUI centres views on half points, and a sharp bitmap drawn between pixels is resampled —
/// the very thing this app exists to prevent — so the preview draws its pixels itself.
struct PixelCompareView: NSViewRepresentable {
    let standard: CGImage
    let clean: CGImage
    let fraction: Double
    var magnification = 1
    var grid = false

    func makeNSView(context: Context) -> PixelCompareNSView { PixelCompareNSView() }

    func updateNSView(_ view: PixelCompareNSView, context: Context) {
        view.standard = standard
        view.clean = clean
        view.fraction = fraction
        view.magnification = magnification
        view.grid = grid
        view.needsDisplay = true
    }
}

final class PixelCompareNSView: NSView {
    var standard: CGImage?
    var clean: CGImage?
    var fraction = 0.5
    var magnification = 1
    var grid = false

    /// Where the bitmaps land, in this view's coordinates, snapped to device pixels.
    var imageRect: CGRect {
        guard let standard else { return .zero }
        let size = CGSize(width: standard.width * magnification, height: standard.height * magnification)
        let centred = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        return backingAlignedRect(centred, options: .alignAllEdgesNearest)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let standard, let clean else { return }
        let rect = imageRect
        context.interpolationQuality = .none
        context.draw(standard, in: rect)
        context.saveGState()
        context.clip(to: CGRect(x: bounds.width * fraction, y: 0, width: bounds.width * (1 - fraction), height: bounds.height))
        context.clear(rect)
        context.draw(clean, in: rect)
        context.restoreGState()
        guard grid, magnification > 1 else { return }
        context.setStrokeColor(NSColor.gray.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(0.5)
        for k in 1..<standard.width {
            let p = CGFloat(k * magnification)
            context.move(to: CGPoint(x: rect.minX + p, y: rect.minY)); context.addLine(to: CGPoint(x: rect.minX + p, y: rect.maxY))
            context.move(to: CGPoint(x: rect.minX, y: rect.minY + p)); context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + p))
        }
        context.strokePath()
    }
}
