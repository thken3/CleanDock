import AppKit
import ApplicationServices
import CleanDockCore
import ServiceManagement

enum PermissionState { case granted, notGranted, notAsked }

/// One icon of the preview, rendered both ways at the Dock's own icon size.
struct PreviewIcon: Identifiable {
    let id: Int
    let name: String
    let standard: CGImage
    let clean: CGImage
}

enum PreviewMode { case normal, retina, noPermission }

/// What the windows show. Refreshed from the controller; use from the main queue.
final class AppState: ObservableObject {
    static let repository = URL(string: "https://github.com/thken3/CleanDock")!

    private let controller: AppController
    private var timer: Timer?
    private var previewKey = ""
    private var seenPreviewKey = ""
    private var foldersCheckedAt: TimeInterval = 0

    @Published var status = Status.noDock
    @Published var displayName = ""
    @Published var accessibility = false
    @Published var finder = PermissionState.notAsked
    @Published var folders: [(name: String, granted: Bool)] = []
    @Published var icons: [PreviewIcon] = []
    @Published var strip: (standard: CGImage, clean: CGImage)?
    @Published var side = 17
    @Published var caption = ""
    @Published var launchAtLogin = false
    @Published var showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true

    init(controller: AppController) {
        self.controller = controller
        reload()
    }

    var enabled: Bool {
        get { controller.enabled }
        set {
            objectWillChange.send()
            controller.enabled = newValue
        }
    }

    var previewMode: PreviewMode {
        if !accessibility { return .noPermission }
        return status == .retinaDisplay ? .retina : .normal
    }

    var statusText: String {
        switch status {
        case .active: return displayName.isEmpty ? "Active" : "Active on \(displayName)"
        case .needsPermission: return "Needs Accessibility permission"
        case .retinaDisplay: return "Idle — the Dock is on a Retina display"
        case .verticalDock: return "Idle — the Dock is not at the bottom of the screen"
        case .noDock: return "Waiting for the Dock"
        case .disabled: return "Off"
        }
    }

    /// Keeps the permission rows and the status fresh while a window is open.
    func setLive(_ live: Bool) {
        timer?.invalidate()
        timer = live ? Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reload() } : nil
        guard live else { return }
        previewKey = ""         // a window opening always gets a fresh preview, at once
        reload()
    }

    func reload() {
        status = controller.status
        accessibility = AXIsProcessTrusted()
        let info = controller.dockInfo
        displayName = info?.displayName ?? ""
        guard timer != nil else { return }      // the rest is only seen in a window
        launchAtLogin = SMAppService.mainApp.status == .enabled
        reloadPreview(info)
        reloadPermissions(info)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()      // only works from the bundled app
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setShowMenuBarIcon(_ on: Bool) {
        showMenuBarIcon = on
        UserDefaults.standard.set(on, forKey: "showMenuBarIcon")
        NotificationCenter.default.post(name: .showMenuBarIconChanged, object: nil)
    }

    func openSettingsPane(_ anchor: String) {
        if anchor == "Privacy_Accessibility" {
            // Adds Clean Dock to the list, so the user only has to switch it on.
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    // MARK: Preview

    private static let fallbackApps = ["/System/Library/CoreServices/Finder.app", "/System/Cryptexes/App/System/Applications/Safari.app",
                                       "/System/Applications/Mail.app", "/System/Applications/Messages.app", "/System/Applications/Notes.app",
                                       "/System/Applications/Music.app", "/System/Applications/System Settings.app"]

    private func reloadPreview(_ info: DockInfo?) {
        let dockSize = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 0
        let side = info?.side ?? (dockSize >= 16 ? Int(dockSize.rounded()) : 17)
        let count = max(3, min(8, (520 + 7) / (side + 7)))
        // Rendering is only redone when the Dock's size or its first icons change.
        let shown = accessibility ? Array((info?.tiles ?? []).prefix(count)) : []
        let key = "\(side)|" + shown.map { $0.url?.path ?? "trash" }.joined(separator: "|")
        // A Dock resize changes the key on every step, and each render starts from 1024 px on the main
        // queue: after the first one, render only a key that held for two reloads in a row.
        let held = previewKey.isEmpty || key == seenPreviewKey
        seenPreviewKey = key
        if key != previewKey, held {
            previewKey = key
            func name(_ path: String) -> String { FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "") }
            var sources: [(name: String, images: [NSImage])] = []
            for tile in shown {
                let images = controller.images(for: tile)
                let name = tile.kind == .trash ? "Trash" : (tile.url.map { name($0.path) } ?? "Icon")
                if !images.isEmpty { sources.append((name, images)) }
            }
            if sources.isEmpty {
                for path in Self.fallbackApps.prefix(count) where FileManager.default.fileExists(atPath: path) {
                    sources.append((name(path), [NSWorkspace.shared.icon(forFile: path)]))
                }
            }
            self.side = side
            icons = sources.enumerated().compactMap { index, source in
                guard let standard = IconRenderer.renderStandardDock(source.images, side: side),
                      let clean = IconRenderer.render(source.images, side: side) else { return nil }
                return PreviewIcon(id: index, name: source.name, standard: standard, clean: clean)
            }
            if let standard = Self.row(icons.map(\.standard), side: side), let clean = Self.row(icons.map(\.clean), side: side) {
                strip = (standard, clean)
            } else {
                strip = nil
            }
        }
        var parts = ["Icon size \(side) px"]
        if let info {
            let density = info.pixelsPerInch.map { ", \($0) ppi" } ?? ""
            parts.append("Display \(info.displayName)\(density), \(status == .retinaDisplay ? "Retina" : "non-Retina")")
        }
        caption = parts.joined(separator: " · ")
    }

    static let stripGap = 7     // pixels between the strip's icons; `PreviewView` hit-tests with the same number

    /// The icons side by side in one bitmap, so the strip is placed on the pixel grid as a whole.
    private static func row(_ images: [CGImage], side: Int) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let width = images.count * side + (images.count - 1) * stripGap
        guard let context = IconRenderer.bitmap(width: width, height: side) else { return nil }
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: index * (side + stripGap), y: 0, width: side, height: side))
        }
        return context.makeImage()
    }

    // MARK: Permissions

    private func reloadPermissions(_ info: DockInfo?) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let state = Self.finderAutomation()
            DispatchQueue.main.async { if self?.finder != state { self?.finder = state } }
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - foldersCheckedAt > 5 else { return }
        foldersCheckedAt = now
        folders = (info?.tiles ?? []).filter { $0.kind == .folder }.compactMap(\.url).map { url in
            (FileManager.default.displayName(atPath: url.path), (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil)
        }
    }

    /// Whether this app may send Apple events to Finder, without ever prompting.
    private static func finderAutomation() -> PermissionState {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .notGranted
        default: return .notAsked           // −1744: would ask; −600: Finder not running
        }
    }
}

extension Notification.Name {
    static let showMenuBarIconChanged = Notification.Name("CleanDockShowMenuBarIconChanged")
}
