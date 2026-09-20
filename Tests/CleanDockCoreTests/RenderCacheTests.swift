import CoreGraphics
import Foundation
import Testing
@testable import CleanDockCore

private func pixel() -> CGImage {
    CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

private func key(path: String = "/Applications/A.app", modified: Double = 1, side: Int = 17, dark: Bool = false, badge: Int = 0,
                 variant: String = "") -> RenderKey {
    RenderKey(path: path, modified: Date(timeIntervalSince1970: modified), side: side, dark: dark, badgeLength: badge, variant: variant)
}

@Test func secondLookupIsAHit() {
    let cache = RenderCache()
    var made = 0
    let first = cache.image(for: key()) { made += 1; return pixel() }
    let second = cache.image(for: key()) { made += 1; return pixel() }
    #expect(made == 1)
    #expect(first === second)
}

@Test func everyKeyFieldMisses() {
    let cache = RenderCache()
    var made = 0
    for k in [key(), key(path: "/Applications/B.app"), key(modified: 2), key(side: 32), key(dark: true), key(badge: 1),
              key(variant: "stack-2")] {
        _ = cache.image(for: k) { made += 1; return pixel() }
    }
    #expect(made == 7)
    #expect(cache.count == 7)
}

@Test func failuresAreCachedToo() {
    let cache = RenderCache()
    var made = 0
    #expect(cache.image(for: key()) { made += 1; return nil } == nil)
    #expect(cache.image(for: key()) { made += 1; return nil } == nil)
    #expect(made == 1)
}

@Test func removeAllForcesARender() {
    let cache = RenderCache()
    var made = 0
    _ = cache.image(for: key()) { made += 1; return pixel() }
    cache.removeAll()
    _ = cache.image(for: key()) { made += 1; return pixel() }
    #expect(made == 2)
}

@Test func removeWhereDropsOnlyTheMatchingKeys() {
    let cache = RenderCache()
    for k in [key(path: "/Users/me/Downloads"), key(path: "/Users/me/Downloads", variant: "stack-2"),
              key(path: "/Users/me/Documents"), key(path: "trash:full")] {
        _ = cache.image(for: k) { pixel() }
    }
    #expect(cache.count == 4)
    cache.remove { $0.path == "/Users/me/Downloads" }
    #expect(cache.count == 2)
    var made = 0
    _ = cache.image(for: key(path: "/Users/me/Downloads")) { made += 1; return pixel() }
    _ = cache.image(for: key(path: "/Users/me/Documents")) { made += 1; return pixel() }
    #expect(made == 1)                                  // only the removed one was rendered again
    cache.remove { $0.path.hasPrefix("trash:") }
    #expect(cache.count == 2)
}

@Test func peekNeverRendersAndNeverStores() {
    let cache = RenderCache()
    #expect(cache.peek(for: key()) == nil)
    #expect(cache.count == 0)
    let made = cache.image(for: key()) { pixel() }
    #expect(cache.peek(for: key()) === made)
}

@Test func cacheEmptiesItselfAtTheLimit() {
    let cache = RenderCache(limit: 3)
    for side in 1...4 { _ = cache.image(for: key(side: side)) { pixel() } }
    #expect(cache.count == 1)
}
