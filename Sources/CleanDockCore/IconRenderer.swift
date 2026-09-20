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

    /// Lanczos downscale to a side×side image. Proposes the 1024 px representation, so an icon bundle
    /// hands over its largest one instead of the 32 px default.
    ///
    /// A square source fills the square; a source that already has the target size is returned as is.
    /// A non-square source — a QuickLook thumbnail fits into 256×256 keeping its aspect, so a photo
    /// arrives as e.g. 256×144 — is scaled by its long edge and centred, transparent around it.
    static func downscale(_ image: NSImage, to side: Int) -> CGImage? {
        var proposed = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        guard source.width > 0, source.height > 0 else { return nil }
        if source.width == side && source.height == side { return source }
        if source.width == source.height { return scale(source, width: side, height: side) }

        let long = Double(max(source.width, source.height))
        let width = max(1, Int((Double(side) * Double(source.width) / long).rounded()))
        let height = max(1, Int((Double(side) * Double(source.height) / long).rounded()))
        guard let scaled = scale(source, width: width, height: height),
              let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        canvas.interpolationQuality = .none
        canvas.draw(scaled, in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        return canvas.makeImage()
    }

    /// What the standard Dock makes of the same icon on a 1x display, for the before/after preview.
    /// Fitted against captures of the real Dock: of all candidates (mip-mapped, trilinear, other source sizes)
    /// plain bilinear sampling of the 128 px representation matched best by a wide margin. At 128 → 17 px
    /// that reads only 4 of every ~56 source pixels, so fine detail turns into jagged, uneven pixels.
    public static func renderStandardDock(_ images: [NSImage], side: Int) -> CGImage? {
        guard side > 0, let base = render(images, side: 128) else { return nil }
        let source = pixels(of: base), n = 128
        var out = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side { for x in 0..<side {
            let u = min(max((Double(x) + 0.5) / Double(side) * Double(n) - 0.5, 0), Double(n - 1))
            let v = min(max((Double(y) + 0.5) / Double(side) * Double(n) - 0.5, 0), Double(n - 1))
            let x0 = Int(u), y0 = Int(v), x1 = min(x0 + 1, n - 1), y1 = min(y0 + 1, n - 1)
            let fx = u - Double(x0), fy = v - Double(y0)
            for c in 0..<4 {
                func at(_ px: Int, _ py: Int) -> Double { source[(py * n + px) * 4 + c] }
                let value = (at(x0, y0) * (1 - fx) + at(x1, y0) * fx) * (1 - fy) + (at(x0, y1) * (1 - fx) + at(x1, y1) * fx) * fy
                out[(y * side + x) * 4 + c] = UInt8(min(max(value.rounded(), 0), 255))
            }
        } }
        return out.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// Premultiplied RGBA values of an image, top row first.
    private static func pixels(of image: CGImage) -> [Double] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data.map(Double.init)
    }

    private static func scale(_ source: CGImage, width: Int, height: Int) -> CGImage? {
        // CILanczosScaleTransform scales y by `scale` and x by `scale * aspectRatio`.
        let scaleY = Double(height) / Double(source.height)
        let scaleX = Double(width) / Double(source.width)
        let scaled = CIImage(cgImage: source).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scaleY,
            kCIInputAspectRatioKey: scaleX / scaleY,
        ])
        return context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: width, height: height))
    }
}
