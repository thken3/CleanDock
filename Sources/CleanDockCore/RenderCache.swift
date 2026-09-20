import CoreGraphics
import Foundation

public struct RenderKey: Hashable {
    public let path: String
    public let modified: Date?
    public let side: Int
    public let dark: Bool
    public let badgeLength: Int
    /// Everything else that changes what the tile looks like without changing `path` or `modified`:
    /// the Dock's stack/folder display setting and the system icon style.
    public let variant: String

    public init(path: String, modified: Date?, side: Int, dark: Bool, badgeLength: Int, variant: String) {
        self.path = path
        self.modified = modified
        self.side = side
        self.dark = dark
        self.badgeLength = badgeLength
        self.variant = variant
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

    /// The cached render for `key`, without rendering and without storing anything on a miss.
    public func peek(for key: RenderKey) -> CGImage? { store[key] ?? nil }

    /// Drops just the entries whose key matches, so one folder's thumbnails arriving does not
    /// cost a re-render of every other tile.
    public func remove(where matches: (RenderKey) -> Bool) {
        for key in store.keys where matches(key) { store.removeValue(forKey: key) }
    }

    public func removeAll() { store.removeAll() }
}
