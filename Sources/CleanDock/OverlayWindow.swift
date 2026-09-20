import AppKit

/// Transparent, click-through window over one whole screen, one level above the Dock. One layer per covered tile.
final class OverlayWindow {
    private let window: NSWindow
    private let root = CALayer()
    private var layers: [CALayer] = []

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.layer = root
        view.wantsLayer = true
        window.contentView = view
    }

    func show(on screen: NSScreen) {
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    /// `rect` in points local to the screen, top-left origin, already snapped to whole pixels.
    func update(_ items: [(rect: CGRect, image: CGImage)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while layers.count < items.count {
            let layer = CALayer()
            layer.magnificationFilter = .nearest      // at rest the bitmap maps 1:1 to pixels
            layer.minificationFilter = .trilinear     // smooth while a tile grows in or shrinks out
            layer.contentsGravity = .resize
            root.addSublayer(layer)
            layers.append(layer)
        }
        // AppKit owns the hosting layer's orientation, and it differs between a bare binary and a bundled app,
        // so ask instead of assuming: our rects have a top-left origin.
        let flipped = root.isGeometryFlipped
        let height = window.frame.height
        for (index, layer) in layers.enumerated() {
            if index < items.count {
                let rect = items[index].rect
                layer.frame = flipped ? rect : CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
                layer.contents = items[index].image
                layer.isHidden = false
            } else {
                layer.isHidden = true
                layer.contents = nil
            }
        }
        CATransaction.commit()
    }

    func clear() {
        update([])
        window.orderOut(nil)
    }
}
