import AppKit
import ApplicationServices

enum DebugTools {
    static func dump() {
        print("accessibility trusted:", AXIsProcessTrusted())
        guard let snapshot = DockReader().snapshot() else { print("cannot read the Dock"); return }
        print("list \(snapshot.listFrame) horizontal=\(snapshot.horizontal)")
        for tile in snapshot.tiles {
            print("\(tile.kind) \(tile.frame) badge=\"\(tile.badge)\" \(tile.url?.path ?? "-")")
        }
        for screen in NSScreen.screens { print("screen \(screen.localizedName) \(screen.frame) scale=\(screen.backingScaleFactor)") }
    }

    static func shot(to path: String) {
        guard let snapshot = DockReader().snapshot() else { print("cannot read the Dock"); return }
        let r = snapshot.listFrame.insetBy(dx: -8, dy: -14).integral
        let raw = NSTemporaryDirectory() + "cleandock-shot.png"
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-R\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))", raw]
        try? capture.run()
        capture.waitUntilExit()
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: raw) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("screencapture failed (Screen Recording permission?)"); return }
        let zoom = 8
        guard let context = CGContext(data: nil, width: image.width * zoom, height: image.height * zoom, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * zoom, height: image.height * zoom))
        guard let zoomed = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, zoomed, nil)
        CGImageDestinationFinalize(destination)
        print("wrote \(path) (\(image.width)x\(image.height) at \(zoom)x)")
    }
}
