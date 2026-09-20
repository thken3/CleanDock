import CoreGraphics
import Foundation

public struct RenderKey: Hashable {
    public let path: String
    public let modified: Date?
    public let side: Int
    public let dark: Bool
    public let badgeLength: Int

    public init(path: String, modified: Date?, side: Int, dark: Bool, badgeLength: Int) {
        self.path = path
        self.modified = modified
        self.side = side
        self.dark = dark
        self.badgeLength = badgeLength
    }
}

/// Rendered icons by key. Not thread-safe: use from one queue.
public final class RenderCache {
    private var store: [RenderKey: CGImage?] = [:]
    private let limit: Int

    public init(limit: Int = 256) { self.limit = limit }

    public var count: Int { store.count }

    public func image(for key: RenderKey, make: () -> CGImage?) -> CGImage? {
        if let cached = store[key] { return cached }
        if store.count >= limit { store.removeAll() }
        let image = make()
        store[key] = .some(image)
        return image
    }

    public func removeAll() { store.removeAll() }
}
