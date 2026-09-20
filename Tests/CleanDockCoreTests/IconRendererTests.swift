import AppKit
import Testing
@testable import CleanDockCore

/// Opaque or transparent test image; `pixel` returns RGBA for a position, y = 0 is the top row.
private func makeImage(side: Int, pixel: (Int, Int) -> [UInt8]) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    for y in 0..<side {
        for x in 0..<side {
            let p = pixel(x, y)
            for c in 0..<4 { rep.bitmapData![(y * side + x) * 4 + c] = p[c] }
        }
    }
    let image = NSImage(size: NSSize(width: side, height: side))
    image.addRepresentation(rep)
    return image
}

/// RGBA bytes of an image, top row first.
private func bytes(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}

private let red: [UInt8] = [255, 0, 0, 255]
private let green: [UInt8] = [0, 255, 0, 255]

@Test func outputHasExactlyTheRequestedSize() throws {
    let image = try #require(IconRenderer.render([makeImage(side: 1024) { _, _ in red }], side: 17))
    #expect(image.width == 17)
    #expect(image.height == 17)
    let data = bytes(image)
    let centre = (8 * 17 + 8) * 4
    #expect(Array(data[centre..<centre + 4]) == red)
}

@Test func sourceAtTargetSizePassesThroughUnchanged() throws {
    let checker = makeImage(side: 17) { x, y in (x + y) % 2 == 0 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    let data = bytes(try #require(IconRenderer.render([checker], side: 17)))
    for y in 0..<17 {
        for x in 0..<17 {
            #expect(data[(y * 17 + x) * 4] == ((x + y) % 2 == 0 ? 255 : 0))
        }
    }
}

@Test func nothingToDrawGivesNil() {
    #expect(IconRenderer.render([], side: 17) == nil)
    #expect(IconRenderer.render([makeImage(side: 32) { _, _ in red }], side: 0) == nil)
}

@Test func cutoutIsTransparent() throws {
    let cutout = CGRect(x: 8, y: 0, width: 9, height: 8)
    let data = bytes(try #require(IconRenderer.render([makeImage(side: 17) { _, _ in red }], side: 17, cutout: cutout)))
    #expect(data[(0 * 17 + 8) * 4 + 3] == 0)      // top-left corner of the cutout
    #expect(data[(7 * 17 + 16) * 4 + 3] == 0)     // bottom-right corner of the cutout
    #expect(data[(0 * 17 + 7) * 4 + 3] == 255)    // left of the cutout
    #expect(data[(8 * 17 + 16) * 4 + 3] == 255)   // below the cutout
}

@Test func pileLayoutFrontLowAndLargeOthersSmallerAndHigher() {
    #expect(IconRenderer.pileLayout(side: 17, count: 3) == [PileLayer(side: 15, x: 1, top: 2), PileLayer(side: 13, x: 2, top: 1), PileLayer(side: 11, x: 3, top: 0)])
    #expect(IconRenderer.pileLayout(side: 17, count: 2) == [PileLayer(side: 15, x: 1, top: 2), PileLayer(side: 13, x: 2, top: 1)])
    #expect(IconRenderer.pileLayout(side: 17, count: 1) == [PileLayer(side: 17, x: 0, top: 0)])
    #expect(IconRenderer.pileLayout(side: 17, count: 5).count == 3)
}

@Test func pileDrawsTheFrontImageOnTop() throws {
    let images = [makeImage(side: 64) { _, _ in red }, makeImage(side: 64) { _, _ in green }]
    let data = bytes(try #require(IconRenderer.render(images, side: 17)))
    let centre = (9 * 17 + 8) * 4
    #expect(Array(data[centre..<centre + 4]) == red)      // front covers the middle
    // row 1 belongs only to the layer behind (top 1); the front starts at row 2. It is an edge row, so Lanczos leaves it partly transparent.
    let peek = (1 * 17 + 8) * 4
    #expect(data[peek] == 0)
    #expect(data[peek + 1] > 150)
}
