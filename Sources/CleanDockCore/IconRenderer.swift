import AppKit
import CoreImage

public struct PileLayer: Equatable {
    public let side: Int
    public let x: Int
    public let top: Int

    public init(side: Int, x: Int, top: Int) {
        self.side = side
        self.x = x
        self.top = top
    }
}

public enum IconRenderer {
    private static let context = CIContext()

    /// Layers of a tile, front first. One image fills the canvas. A pile puts the front image low and large
    /// and each image behind it two pixels smaller and one pixel higher.
    public static func pileLayout(side: Int, count: Int) -> [PileLayer] {
        guard count > 1 else { return [PileLayer(side: side, x: 0, top: 0)] }
        return (0..<min(count, 3)).map { PileLayer(side: side - 2 - 2 * $0, x: 1 + $0, top: 2 - $0) }
    }

    /// `images` front first. The result is side×side pixels, sRGB, premultiplied alpha, transparent background.
    public static func render(_ images: [NSImage], side: Int, cutout: CGRect? = nil) -> CGImage? {
        guard !images.isEmpty, side > 0,
              let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        canvas.interpolationQuality = .none
        let layers = pileLayout(side: side, count: images.count)
        for (image, layer) in zip(images, layers).reversed() where layer.side > 0 {
            guard let scaled = downscale(image, to: layer.side) else { continue }
            canvas.draw(scaled, in: CGRect(x: layer.x, y: side - layer.top - layer.side, width: layer.side, height: layer.side))
        }
        if let cutout {
            canvas.clear(CGRect(x: cutout.minX, y: CGFloat(side) - cutout.maxY, width: cutout.width, height: cutout.height))
        }
        return canvas.makeImage()
    }

    /// Lanczos downscale from the largest representation. A source that already has the target size is returned as is.
    static func downscale(_ image: NSImage, to side: Int) -> CGImage? {
        var proposed = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        if source.width == side && source.height == side { return source }
        let scaled = CIImage(cgImage: source).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: Double(side) / Double(source.height),
            kCIInputAspectRatioKey: Double(source.height) / Double(source.width),
        ])
        return context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: side, height: side))
    }
}
