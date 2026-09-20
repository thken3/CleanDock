import AppKit
import CleanDockCore
import QuickLookThumbnailing

/// Maps a Dock tile to a cache key and to the images the renderer draws. Use from the main queue.
final class IconSource {
    /// Called on the main queue when something arrived that changes what tiles look like.
    var onChange: (() -> Void)?

    private var modifiedMemo: [String: (date: Date?, checked: TimeInterval)] = [:]
    private var displayMemo: [String: (setting: StackArrangement?, checked: TimeInterval)] = [:]
    private var thumbnails: [URL: NSImage] = [:]
    private var requested: Set<URL> = []
    private var trashFull: Bool?                     // nil: unknown, or Finder automation denied
    private var trashTimer: DispatchSourceTimer?

    /// Cheap: may be called for every tile on every frame. `nil` leaves the tile uncovered.
    func key(for tile: DockTile) -> (path: String, modified: Date?)? {
        switch tile.kind {
        case .app, .file:
            guard let path = tile.url?.path else { return nil }
            return (path, modified(path))
        case .folder:
            guard let url = tile.url else { return nil }
            let setting = displaySetting(of: url)
            let suffix = setting.map { "|stack-\($0.rawValue)" } ?? "|folder"   // Stack ↔ Folder and arrangement changes must miss the cache
            return (url.path + suffix, modified(url.path))
        case .trash:
            guard let trashFull else { return nil }
            return (trashFull ? "trash:full" : "trash:empty", nil)
        }
    }

    /// Front image first. Only called on a cache miss. Empty leaves the tile uncovered.
    func images(for tile: DockTile) -> [NSImage] {
        if tile.kind == .trash {
            return NSImage(named: trashFull == true ? NSImage.trashFullName : NSImage.trashEmptyName).map { [$0] } ?? []
        }
        guard let url = tile.url else { return [] }
        if tile.kind == .folder, let arrangement = displaySetting(of: url) {
            guard let items = stackItems(in: url) else { return [] }        // not readable: leave the tile to the Dock
            let front = StackOrder.front(items, arrangement: arrangement)
            if !front.isEmpty { return front.map { image(forStackItem: $0.url) } }
        }
        return [NSWorkspace.shared.icon(forFile: url.path)]
    }

    // MARK: Stacks

    /// The Dock's stack/folder display setting for a folder, looked up at most every two seconds per path
    /// so `key(for:)` and `images(for:)` always agree and the render cache notices a changed setting.
    private func displaySetting(of folder: URL) -> StackArrangement? {
        let path = folder.path
        let now = ProcessInfo.processInfo.systemUptime
        if let memo = displayMemo[path], now - memo.checked < 2 { return memo.setting }
        let setting = stackArrangement(of: folder)
        displayMemo[path] = (setting, now)
        return setting
    }

    /// The arrangement when the Dock shows this folder as a stack, `nil` when it shows it as a folder.
    private func stackArrangement(of folder: URL) -> StackArrangement? {
        let others = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-others") as? [[String: Any]] ?? []
        for entry in others {
            guard let data = entry["tile-data"] as? [String: Any],
                  let string = (data["file-data"] as? [String: Any])?["_CFURLString"] as? String,
                  URL(string: string)?.standardizedFileURL.path == folder.standardizedFileURL.path else { continue }
            guard (data["displayas"] as? Int ?? 0) == 0 else { return nil }      // 1 = display as folder
            return StackArrangement(rawValue: data["arrangement"] as? Int ?? 1) ?? .name
        }
        return nil
    }

    private func stackItems(in folder: URL) -> [StackItem]? {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else { return nil }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return StackItem(url: url, added: values?.addedToDirectoryDate, modified: values?.contentModificationDate, created: values?.creationDate)
        }
    }

    /// The file icon now; a QuickLook thumbnail replaces it when it arrives.
    private func image(forStackItem url: URL) -> NSImage {
        if let thumbnail = thumbnails[url] { return thumbnail }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isDirectory, !requested.contains(url) {
            if requested.count > 64 {
                requested.removeAll()
                thumbnails.removeAll()
            }
            requested.insert(url)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 256), scale: 1, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                guard let image = representation?.nsImage else { return }
                DispatchQueue.main.async {
                    self?.thumbnails[url] = image
                    self?.onChange?()
                }
            }
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Trash

    /// Asks Finder every ten seconds whether the Trash has items. The first call triggers the one-time Automation prompt.
    func startTrashPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 10)
        timer.setEventHandler { [weak self] in
            let full = Self.askFinderWhetherTrashIsFull()
            DispatchQueue.main.async {
                guard let self, self.trashFull != full else { return }
                self.trashFull = full
                self.onChange?()
            }
        }
        timer.resume()
        trashTimer = timer
    }

    /// `nil` when Finder did not answer, for example because Automation permission was denied.
    private static func askFinderWhetherTrashIsFull() -> Bool? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to count items of trash"]
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
              let count = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return count > 0
    }

    // MARK: Files

    /// File modification date, looked up at most every two seconds per path.
    private func modified(_ path: String) -> Date? {
        let now = ProcessInfo.processInfo.systemUptime
        if let memo = modifiedMemo[path], now - memo.checked < 2 { return memo.date }
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        modifiedMemo[path] = (date, now)
        return date
    }
}
