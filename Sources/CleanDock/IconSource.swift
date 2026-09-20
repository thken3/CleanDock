import AppKit
import CleanDockCore
import QuickLookThumbnailing

/// What changed since the last render, so only the affected cache entries have to go.
enum IconChange: Hashable {
    case folder(String)
    case trash
}

/// Maps a Dock tile to a cache key and to the images the renderer draws. Use from the main queue.
final class IconSource {
    /// Called on the main queue when something arrived that changes what tiles look like.
    var onChange: ((Set<IconChange>) -> Void)?

    private var modifiedMemo: [String: (date: Date?, checked: TimeInterval)] = [:]
    private var displayMemo: [String: (setting: StackArrangement?, checked: TimeInterval)] = [:]
    private var listingMemo: [String: (items: [StackItem]?, arrangement: StackArrangement, checked: TimeInterval)] = [:]
    private var iconStyleMemo: (value: String, checked: TimeInterval)?
    private var thumbnails: [URL: NSImage] = [:]
    private var requested: Set<URL> = []
    private var pendingChanges: Set<IconChange> = []
    private var changeScheduled = false
    private var trashFull: Bool?                     // nil: unknown, or Finder automation denied
    private var trashTimer: DispatchSourceTimer?
    private var trashInterval: TimeInterval = 10
    private var trashNilAnswers = 0

    /// Cheap: may be called for every tile on every frame. `nil` leaves the tile uncovered.
    func key(for tile: DockTile) -> (path: String, modified: Date?, variant: String)? {
        switch tile.kind {
        case .app, .file:
            guard let path = tile.url?.path else { return nil }
            return (path, modified(path), iconStyle())
        case .folder:
            guard let url = tile.url else { return nil }
            let setting = displaySetting(of: url)
            if let setting {
                // An unreadable folder must not cache a failure: without this, granting access later
                // would go unnoticed because the nil render stays keyed by the unchanged folder mtime.
                // The listing is memoized, so `images(for:)` reuses this one.
                guard stackListing(of: url, arrangement: setting) != nil else { return nil }
            }
            // Stack ↔ Folder and arrangement changes must miss the cache, but they belong in the
            // variant, not in the path: `AppController` matches a folder's keys on the plain path.
            let display = setting.map { "stack-\($0.rawValue)" } ?? "folder"
            return (url.path, modified(url.path), iconStyle() + "|" + display)
        case .trash:
            guard let trashFull else { return nil }
            return (trashFull ? "trash:full" : "trash:empty", nil, iconStyle())
        }
    }

    /// Front image first. Only called on a cache miss. Empty leaves the tile uncovered.
    func images(for tile: DockTile) -> [NSImage] {
        if tile.kind == .trash {
            return NSImage(named: trashFull == true ? NSImage.trashFullName : NSImage.trashEmptyName).map { [$0] } ?? []
        }
        guard let url = tile.url else { return [] }
        if tile.kind == .folder, let arrangement = displaySetting(of: url) {
            guard let items = stackListing(of: url, arrangement: arrangement) else { return [] }   // not readable: leave the tile to the Dock
            let front = StackOrder.front(items, arrangement: arrangement)
            if !front.isEmpty { return front.map { image(forStackItem: $0.url, in: url) } }
        }
        return [NSWorkspace.shared.icon(forFile: url.path)]
    }

    // MARK: Changes

    /// Collects what changed for a moment before telling the controller: a stack folder's thumbnails
    /// arrive one by one, and each one used to cost a full repaint.
    private func note(_ change: IconChange) {
        pendingChanges.insert(change)
        guard !changeScheduled else { return }
        changeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.changeScheduled = false
            let changes = self.pendingChanges
            self.pendingChanges.removeAll()
            guard !changes.isEmpty else { return }
            self.onChange?(changes)
        }
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

    /// The folder's contents, memoized for two seconds per folder so a repaint — or a thumbnail arriving —
    /// does not enumerate it again. `nil` means the folder could not be read.
    private func stackListing(of folder: URL, arrangement: StackArrangement) -> [StackItem]? {
        let path = folder.path
        let now = ProcessInfo.processInfo.systemUptime
        if let memo = listingMemo[path], memo.arrangement == arrangement, now - memo.checked < 2 { return memo.items }
        let items = stackItems(in: folder, arrangement: arrangement)
        listingMemo[path] = (items, arrangement, now)
        return items
    }

    private func stackItems(in folder: URL, arrangement: StackArrangement) -> [StackItem]? {
        // Only the one date the arrangement actually sorts by; ordering by name or kind needs none at all.
        let key: URLResourceKey?
        switch arrangement {
        case .dateAdded: key = .addedToDirectoryDateKey
        case .dateModified: key = .contentModificationDateKey
        case .dateCreated: key = .creationDateKey
        case .name, .kind: key = nil
        }
        let keys = key.map { [$0] } ?? []
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles) else { return nil }
        guard let key else { return urls.map { StackItem(url: $0, added: nil, modified: nil, created: nil) } }
        return urls.map { url in
            let date = (try? url.resourceValues(forKeys: [key])).flatMap { values -> Date? in
                switch key {
                case .addedToDirectoryDateKey: return values.addedToDirectoryDate
                case .contentModificationDateKey: return values.contentModificationDate
                default: return values.creationDate
                }
            }
            return StackItem(url: url,
                             added: key == .addedToDirectoryDateKey ? date : nil,
                             modified: key == .contentModificationDateKey ? date : nil,
                             created: key == .creationDateKey ? date : nil)
        }
    }

    /// The file icon now; a QuickLook thumbnail replaces it when it arrives.
    private func image(forStackItem url: URL, in folder: URL) -> NSImage {
        if let thumbnail = thumbnails[url] { return thumbnail }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if !isDirectory, !requested.contains(url) {
            if requested.count > 64 {
                requested.removeAll()
                thumbnails.removeAll()
            }
            requested.insert(url)
            let path = folder.path
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 256), scale: 1, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                guard let image = representation?.nsImage else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.thumbnails[url] = image
                    self.listingMemo.removeValue(forKey: path)      // the stack must be laid out again
                    self.note(.folder(path))
                }
            }
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Icon style

    /// macOS 26+ lets the whole system draw icons Clear or Tinted. That changes what
    /// `NSWorkspace.icon(forFile:)` returns without touching light/dark or any mtime, so it belongs in
    /// the render key. Memoized for two seconds like the other lookups.
    private static let iconStyleKeys = ["AppleIconAppearanceTheme", "AppleIconAppearanceTintColor"]

    private func iconStyle() -> String {
        let now = ProcessInfo.processInfo.systemUptime
        if let memo = iconStyleMemo, now - memo.checked < 2 { return memo.value }
        // Absent on a system left at the default style — then this is empty and the key is unaffected.
        let defaults = UserDefaults.standard
        let value = Self.iconStyleKeys.compactMap { name in
            defaults.object(forKey: name).map { "\(name)=\($0)" }
        }.joined(separator: ",")
        iconStyleMemo = (value, now)
        return value
    }

    // MARK: Trash

    /// Asks Finder whether the Trash has items, but only while the overlay actually draws a Trash tile.
    /// Idempotent. The last known state is kept when polling stops.
    func setTrashPolling(_ on: Bool) {
        guard on != (trashTimer != nil) else { return }
        guard on else {
            trashTimer?.cancel()
            trashTimer = nil
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        // Do not re-ask straight away once Finder has been refusing: the answer will not have changed.
        timer.schedule(deadline: .now() + (trashNilAnswers >= 3 ? trashInterval : 0), repeating: trashInterval)
        timer.setEventHandler { [weak self] in
            let full = Self.askFinderWhetherTrashIsFull()
            DispatchQueue.main.async { self?.trashAnswered(full) }
        }
        timer.resume()
        trashTimer = timer
    }

    private func trashAnswered(_ full: Bool?) {
        if full == nil {
            trashNilAnswers += 1
            // Automation was most likely denied: keep the poll alive but stop paying for it every ten seconds.
            if trashNilAnswers >= 3 { setTrashInterval(300) }
        } else {
            trashNilAnswers = 0
            setTrashInterval(10)
        }
        guard trashFull != full else { return }
        trashFull = full
        note(.trash)
    }

    private func setTrashInterval(_ seconds: TimeInterval) {
        guard trashInterval != seconds else { return }
        trashInterval = seconds
        trashTimer?.schedule(deadline: .now() + seconds, repeating: seconds)
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
