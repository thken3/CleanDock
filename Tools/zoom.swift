// Nearest-neighbor zoom of a PNG, for inspecting small pixel-art-scale screenshots.
//
// Usage: swift Tools/zoom.swift <in.png> <out.png> [factor]
// Default factor is 8.

import CoreGraphics
import ImageIO
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: swift Tools/zoom.swift <in.png> <out.png> [factor]\n".data(using: .utf8)!)
    exit(1)
}

let inputPath = arguments[1]
let outputPath = arguments[2]
let factor: Int
if arguments.count >= 4, let parsed = Int(arguments[3]), parsed > 0 {
    factor = parsed
} else {
    factor = 8
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

let width = image.width * factor
let height = image.height * factor
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("cannot create a context to zoom \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}
context.interpolationQuality = .none
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let zoomed = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outputPath) as CFURL, "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write("cannot write \(outputPath)\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(destination, zoomed, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("cannot write \(outputPath)\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(outputPath) (\(image.width)x\(image.height) at \(factor)x)")
