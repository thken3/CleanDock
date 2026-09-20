import AppKit

/// Maps a Dock tile to a cache key and to the images the renderer draws. Use from the main queue.
final class IconSource {
    /// Called on the main queue when something arrived that changes what tiles look like.
    var onChange: (() -> Void)?

    private var modifiedMemo: [String: (date: Date?, checked: TimeInterval)] = [:]

    /// Cheap: may be called for every tile on every frame. `nil` leaves the tile uncovered.
    func key(for tile: DockTile) -> (path: String, modified: Date?)? {
        switch tile.kind {
        case .app, .file, .folder:
            guard let path = tile.url?.path else { return nil }
            return (path, modified(path))
        case .trash:
            return nil
        }
    }

    /// Front image first. Only called on a cache miss.
    func images(for tile: DockTile) -> [NSImage] {
        guard let path = tile.url?.path else { return [] }
        return [NSWorkspace.shared.icon(forFile: path)]
    }

    /// File modification date, looked up at most every two seconds per path.
    private func modified(_ path: String) -> Date? {
        let now = ProcessInfo.processInfo.systemUptime
        if let memo = modifiedMemo[path], now - memo.checked < 2 { return memo.date }
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        modifiedMemo[path] = (date, now)
        return date
    }
}
