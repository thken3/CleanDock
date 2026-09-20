# Clean Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free, open-source macOS menu bar app that draws sharp icons over the standard Dock's blurry ones on 1x displays, leaving the Dock itself untouched.

**Architecture:** A background app reads every Dock tile's frame through the Accessibility API and draws a Lanczos-downscaled, pixel-snapped copy of each icon in a transparent click-through window one level above the Dock. A high-rate tracking loop follows the Dock's live animated frames so the overlay never hides. Pure logic lives in a tested library target; everything that touches the system lives in the app target.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, Swift Package Manager, AppKit, ApplicationServices (Accessibility), Core Image, QuickLookThumbnailing, ServiceManagement, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-20-clean-dock-design.md` — read it before starting any task.

## Global Constraints

- macOS 14 or later (`platforms: [.macOS(.v14)]`). Developed and tested on macOS 27.
- Swift Package with three targets: `CleanDockCore` (library), `CleanDock` (executable), `CleanDockCoreTests`. `swiftLanguageModes: [.v5]`.
- No third-party dependencies.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- The only mandatory permission is Accessibility. No Screen Recording in the app.
- The overlay is active only when the Dock is at the bottom of a display with backing scale factor 1.
- Clean Dock never draws a placeholder. A tile that cannot be rendered stays uncovered.
- Clean Dock never draws badges, running dots, the separator or the Dock background.
- Renderer: Lanczos downscale (`CILanczosScaleTransform`) from the 1024 px representation to a whole-pixel size, transparent background, placed on whole pixels. No sharpening, no subpixel rendering.
- Bundle identifier `app.cleandock.CleanDock`. License MIT, copyright holder "Clean Dock contributors".
- Measured Dock geometry (macOS 27): tile frame width = tile size + 2 and height = width + 12 for tile sizes below 48; width = tile size + 4 and height = width + 16 from 48 up. The icon canvas is a square of the tile size, centred in the tile frame. Badge (solid red part) at tile size 17 spans x 9.8–16.8, y 0–7 of the icon canvas.
- Accessibility coordinates are global points with the origin at the top left of the primary display, y down. Cocoa screen frames have the origin at the bottom left of the primary display, y up.
- Code that needs Accessibility, Screen Recording or a GUI session cannot run in a sandboxed shell. Run those verification steps in a normal Terminal session.

## File Structure

```
Package.swift
Makefile
LICENSE
README.md
.gitignore
Support/Info.plist
Sources/CleanDockCore/TileGeometry.swift      tile frame → icon rect, screen-local conversion, pixel snapping, resting size
Sources/CleanDockCore/BadgeCutout.swift       region of the icon bitmap to leave transparent for the real badge
Sources/CleanDockCore/StackOrder.swift        which items of a stack folder are drawn, in which order
Sources/CleanDockCore/IconRenderer.swift      Lanczos downscale, pile layout, cutout → CGImage
Sources/CleanDockCore/RenderCache.swift       rendered bitmaps by key, including negative results
Sources/CleanDockCore/StabilityDetector.swift "has the Dock stopped moving" logic for the tracking burst
Sources/CleanDock/main.swift                  entry point, --dump and --shot debug modes
Sources/CleanDock/AX.swift                    thin Accessibility helpers
Sources/CleanDock/DockReader.swift            Dock tiles → DockSnapshot / DockOutline
Sources/CleanDock/DebugTools.swift            --dump and --shot implementations
Sources/CleanDock/IconSource.swift            tile → cache key and source images (apps, files, folders, stacks, Trash)
Sources/CleanDock/OverlayWindow.swift         transparent click-through window with one layer per tile
Sources/CleanDock/MotionTracker.swift         idle checks and tracking bursts
Sources/CleanDock/AppController.swift         wires reader, tracker, icons, cache and overlay; mouse monitors; status
Sources/CleanDock/MenuBar.swift               status item and menu
Sources/CleanDock/AppDelegate.swift           app lifecycle, permission prompt and recheck
Tests/CleanDockCoreTests/*.swift              one test file per Core file
docs/manual-test-checklist.md
```

---

### Task 1: Package scaffold and TileGeometry

**Files:**
- Create: `Package.swift`, `.gitignore`, `LICENSE`
- Create: `Sources/CleanDockCore/TileGeometry.swift`
- Create: `Sources/CleanDock/main.swift`
- Test: `Tests/CleanDockCoreTests/TileGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `TileGeometry.iconRect(tile: CGRect) -> CGRect`
  - `TileGeometry.toScreenLocal(_ r: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect`
  - `TileGeometry.snapped(_ r: CGRect, scale: CGFloat) -> CGRect`
  - `TileGeometry.restingSide(_ sides: [CGFloat]) -> CGFloat`

- [ ] **Step 1: Create the package files**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanDock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CleanDockCore"),
        .executableTarget(name: "CleanDock", dependencies: ["CleanDockCore"]),
        .testTarget(name: "CleanDockCoreTests", dependencies: ["CleanDockCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

`.gitignore`:

```
.build/
build/
.DS_Store
*.xcodeproj
.swiftpm/
.superpowers/
```

`LICENSE`: the standard MIT license text with the line `Copyright (c) 2026 Clean Dock contributors`.

`Sources/CleanDock/main.swift` (replaced in Task 7):

```swift
print("Clean Dock")
```

- [ ] **Step 2: Write the failing tests**

`Tests/CleanDockCoreTests/TileGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CleanDockCore

@Test func iconRectSmallTile() {
    // measured at tile size 17: tile frame 19×31, icon canvas 17×17 at +1, +7
    let r = TileGeometry.iconRect(tile: CGRect(x: -1752.775, y: 1133, width: 19, height: 31))
    #expect(abs(r.minX - -1751.775) < 0.001)
    #expect(r.minY == 1140)
    #expect(r.width == 17)
    #expect(r.height == 17)
}

@Test func iconRectLargeTile() {
    // measured at tile size 48: tile frame 52×68, icon canvas 48×48 at +2, +10
    let r = TileGeometry.iconRect(tile: CGRect(x: 100, y: 1096, width: 52, height: 68))
    #expect(r == CGRect(x: 102, y: 1106, width: 48, height: 48))
}

@Test func iconRectGrowingTile() {
    // measured during grow-in: tile frame 3.53×15.53
    let r = TileGeometry.iconRect(tile: CGRect(x: 0, y: 0, width: 3.53, height: 15.53))
    #expect(abs(r.width - 1.53) < 0.001)
    #expect(abs(r.midX - 1.765) < 0.001)
    #expect(abs(r.midY - 7.765) < 0.001)
}

@Test func screenLocalLeftOfPrimary() {
    // 3440×1440 display left of an 1800×1169 primary, bottoms aligned
    let r = TileGeometry.toScreenLocal(CGRect(x: -1751.775, y: 1140, width: 17, height: 17),
                                       screenFrame: CGRect(x: -3440, y: 0, width: 3440, height: 1440), primaryHeight: 1169)
    #expect(abs(r.minX - 1688.225) < 0.001)
    #expect(r.minY == 1411)
    #expect(r.size == CGSize(width: 17, height: 17))
}

@Test func screenLocalRightOfPrimary() {
    let r = TileGeometry.toScreenLocal(CGRect(x: 2000, y: 1100, width: 17, height: 17),
                                       screenFrame: CGRect(x: 1800, y: 0, width: 2560, height: 1169), primaryHeight: 1169)
    #expect(r.origin == CGPoint(x: 200, y: 1100))
}

@Test func screenLocalAbovePrimary() {
    // display above the primary: its top edge is at y = −1440 in Accessibility coordinates
    let r = TileGeometry.toScreenLocal(CGRect(x: 10, y: -40, width: 17, height: 17),
                                       screenFrame: CGRect(x: 0, y: 1169, width: 2560, height: 1440), primaryHeight: 1169)
    #expect(r.origin == CGPoint(x: 10, y: 1400))
}

@Test func snappedToWholePixels() {
    #expect(TileGeometry.snapped(CGRect(x: 1688.225, y: 1411, width: 17, height: 17), scale: 1) == CGRect(x: 1688, y: 1411, width: 17, height: 17))
    #expect(TileGeometry.snapped(CGRect(x: 10.3, y: 5.26, width: 17, height: 17), scale: 2) == CGRect(x: 10.5, y: 5.5, width: 17, height: 17))
    #expect(TileGeometry.snapped(CGRect(x: 0, y: 0, width: 16.6, height: 16.6), scale: 1).size == CGSize(width: 17, height: 17))
}

@Test func restingSideIsTheMostCommon() {
    #expect(TileGeometry.restingSide([17, 17, 17, 9.2, 17]) == 17)
    #expect(TileGeometry.restingSide([17, 24.3, 31.8, 24.1, 17, 17]) == 17)
    #expect(TileGeometry.restingSide([]) == 0)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test`
Expected: compile error, `cannot find 'TileGeometry' in scope`.

- [ ] **Step 4: Implement TileGeometry**

`Sources/CleanDockCore/TileGeometry.swift`:

```swift
import CoreGraphics

public enum TileGeometry {
    /// Icon canvas inside a Dock tile frame, in the same coordinate space as `tile`.
    /// The Dock pads tiles by 2 pt (height − width = 12) below tile size 48 and by 4 pt (height − width = 16) from 48 up.
    public static func iconRect(tile: CGRect) -> CGRect {
        let pad: CGFloat = tile.height - tile.width >= 14 ? 4 : 2
        let side = max(tile.width - pad, 0)
        return CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
    }

    /// Accessibility coordinates (global, top-left origin) to coordinates local to a screen (top-left origin).
    /// `screenFrame` is the Cocoa frame of the screen, `primaryHeight` the height of the screen whose Cocoa origin is (0, 0).
    public static func toScreenLocal(_ r: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX - screenFrame.minX, y: r.minY - (primaryHeight - screenFrame.maxY), width: r.width, height: r.height)
    }

    /// Origin and side rounded to whole pixels. The result is square.
    public static func snapped(_ r: CGRect, scale: CGFloat) -> CGRect {
        let side = (r.width * scale).rounded() / scale
        return CGRect(x: (r.minX * scale).rounded() / scale, y: (r.minY * scale).rounded() / scale, width: side, height: side)
    }

    /// The icon side most tiles have. Tiles that grow in, shrink out or are magnified differ from it.
    public static func restingSide(_ sides: [CGFloat]) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        for side in sides { counts[side.rounded(), default: 0] += 1 }
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test`
Expected: all 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore LICENSE Sources Tests
git commit -m "feat: package scaffold and tile geometry"
```

---

### Task 2: BadgeCutout

**Files:**
- Create: `Sources/CleanDockCore/BadgeCutout.swift`
- Test: `Tests/CleanDockCoreTests/BadgeCutoutTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `BadgeCutout.rect(side: Int, label: String) -> CGRect?` — pixels inside a `side`×`side` icon bitmap, origin at the top left; `nil` when the label is empty.

- [ ] **Step 1: Write the failing tests**

`Tests/CleanDockCoreTests/BadgeCutoutTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import CleanDockCore

@Test func noBadgeNoCutout() {
    #expect(BadgeCutout.rect(side: 17, label: "") == nil)
    #expect(BadgeCutout.rect(side: 0, label: "1") == nil)
}

@Test func oneCharacterBadge() {
    // measured at side 17: solid red spans x 9.8–16.8, y 0–7; the cutout adds the soft edge
    #expect(BadgeCutout.rect(side: 17, label: "1") == CGRect(x: 8, y: 0, width: 9, height: 8))
}

@Test func widerLabelsCutFurtherLeft() {
    #expect(BadgeCutout.rect(side: 17, label: "42") == CGRect(x: 7, y: 0, width: 10, height: 8))
    #expect(BadgeCutout.rect(side: 17, label: "130") == CGRect(x: 5, y: 0, width: 12, height: 8))
}

@Test func cutoutIsCappedAtThreeQuarters() {
    #expect(BadgeCutout.rect(side: 17, label: "99999") == CGRect(x: 5, y: 0, width: 12, height: 8))
}

@Test func scalesWithTheIcon() {
    #expect(BadgeCutout.rect(side: 64, label: "1") == CGRect(x: 32, y: 0, width: 32, height: 28))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter BadgeCutout`
Expected: compile error, `cannot find 'BadgeCutout' in scope`.

- [ ] **Step 3: Implement BadgeCutout**

`Sources/CleanDockCore/BadgeCutout.swift`:

```swift
import CoreGraphics

public enum BadgeCutout {
    /// Region of a side×side icon bitmap (pixels, top-left origin) that stays transparent so the real badge shows through.
    public static func rect(side: Int, label: String) -> CGRect? {
        guard !label.isEmpty, side > 0 else { return nil }
        let s = Double(side)
        let width = min(Int((s * (0.47 + 0.06 * Double(label.count - 1))).rounded(.up)) + 1, side * 3 / 4)
        let height = Int((s * 0.41).rounded(.up)) + 1
        return CGRect(x: side - width, y: 0, width: width, height: height)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BadgeCutout`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDockCore/BadgeCutout.swift Tests/CleanDockCoreTests/BadgeCutoutTests.swift
git commit -m "feat: badge cutout geometry"
```

---

### Task 3: StackOrder

**Files:**
- Create: `Sources/CleanDockCore/StackOrder.swift`
- Test: `Tests/CleanDockCoreTests/StackOrderTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum StackArrangement: Int { case name = 1, dateAdded, dateModified, dateCreated, kind }` — raw values are the Dock's `arrangement` preference values.
  - `struct StackItem: Equatable { url: URL; added: Date?; modified: Date?; created: Date? }` with a public memberwise `init(url:added:modified:created:)`.
  - `StackOrder.front(_ items: [StackItem], arrangement: StackArrangement, count: Int = 3) -> [StackItem]`

- [ ] **Step 1: Write the failing tests**

`Tests/CleanDockCoreTests/StackOrderTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanDockCore

private func item(_ name: String, added: Double? = nil, modified: Double? = nil, created: Double? = nil) -> StackItem {
    StackItem(url: URL(fileURLWithPath: "/tmp/stack/\(name)"),
              added: added.map(Date.init(timeIntervalSince1970:)),
              modified: modified.map(Date.init(timeIntervalSince1970:)),
              created: created.map(Date.init(timeIntervalSince1970:)))
}

private func names(_ items: [StackItem]) -> [String] { items.map(\.url.lastPathComponent) }

@Test func byNameUsesFinderOrdering() {
    let items = [item("b.txt"), item("File 10"), item("File 2"), item("a.txt")]
    #expect(names(StackOrder.front(items, arrangement: .name)) == ["a.txt", "b.txt", "File 2"])
}

@Test func kindFallsBackToName() {
    #expect(names(StackOrder.front([item("b"), item("a")], arrangement: .kind)) == ["a", "b"])
}

@Test func byDateNewestFirst() {
    let items = [item("old", added: 1, modified: 30, created: 2), item("new", added: 3, modified: 10, created: 1), item("mid", added: 2, modified: 20, created: 3)]
    #expect(names(StackOrder.front(items, arrangement: .dateAdded)) == ["new", "mid", "old"])
    #expect(names(StackOrder.front(items, arrangement: .dateModified)) == ["old", "mid", "new"])
    #expect(names(StackOrder.front(items, arrangement: .dateCreated)) == ["mid", "old", "new"])
}

@Test func missingDatesSortLastThenByName() {
    let items = [item("z"), item("a"), item("dated", added: 5)]
    #expect(names(StackOrder.front(items, arrangement: .dateAdded)) == ["dated", "a", "z"])
}

@Test func hiddenFilesAreSkipped() {
    #expect(names(StackOrder.front([item(".DS_Store"), item(".localized"), item("a")], arrangement: .name)) == ["a"])
}

@Test func atMostCountItems() {
    let items = (1...5).map { item("f\($0)") }
    #expect(StackOrder.front(items, arrangement: .name).count == 3)
    #expect(StackOrder.front(items, arrangement: .name, count: 1).count == 1)
    #expect(StackOrder.front([], arrangement: .name).isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StackOrder`
Expected: compile error, `cannot find 'StackItem' in scope`.

- [ ] **Step 3: Implement StackOrder**

`Sources/CleanDockCore/StackOrder.swift`:

```swift
import Foundation

/// Raw values match the `arrangement` value in the Dock's `persistent-others` preferences.
public enum StackArrangement: Int {
    case name = 1, dateAdded, dateModified, dateCreated, kind
}

public struct StackItem: Equatable {
    public let url: URL
    public let added: Date?
    public let modified: Date?
    public let created: Date?

    public init(url: URL, added: Date?, modified: Date?, created: Date?) {
        self.url = url
        self.added = added
        self.modified = modified
        self.created = created
    }
}

public enum StackOrder {
    /// The items a stack tile shows, front first.
    public static func front(_ items: [StackItem], arrangement: StackArrangement, count: Int = 3) -> [StackItem] {
        let visible = items.filter { !$0.url.lastPathComponent.hasPrefix(".") }
        func byName(_ a: StackItem, _ b: StackItem) -> Bool {
            a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        let date: ((StackItem) -> Date?)?
        switch arrangement {
        case .dateAdded: date = { $0.added }
        case .dateModified: date = { $0.modified }
        case .dateCreated: date = { $0.created }
        case .name, .kind: date = nil
        }
        let sorted = visible.sorted { a, b in
            guard let date else { return byName(a, b) }
            let da = date(a) ?? .distantPast, db = date(b) ?? .distantPast
            return da == db ? byName(a, b) : da > db
        }
        return Array(sorted.prefix(count))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter StackOrder`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDockCore/StackOrder.swift Tests/CleanDockCoreTests/StackOrderTests.swift
git commit -m "feat: stack item ordering"
```

---

### Task 4: IconRenderer

**Files:**
- Create: `Sources/CleanDockCore/IconRenderer.swift`
- Test: `Tests/CleanDockCoreTests/IconRendererTests.swift`

**Interfaces:**
- Consumes: nothing (the cutout is passed in as a plain `CGRect?`, produced by `BadgeCutout.rect` in the app).
- Produces:
  - `struct PileLayer: Equatable { side: Int; x: Int; top: Int }`
  - `IconRenderer.pileLayout(side: Int, count: Int) -> [PileLayer]` — front layer first.
  - `IconRenderer.render(_ images: [NSImage], side: Int, cutout: CGRect? = nil) -> CGImage?` — `images` front first; returns a `side`×`side` sRGB image with premultiplied alpha, or `nil` when `images` is empty or `side <= 0`.

- [ ] **Step 1: Write the failing tests**

`Tests/CleanDockCoreTests/IconRendererTests.swift`:

```swift
import AppKit
import Testing
@testable import CleanDockCore

/// Opaque or transparent test image; `pixel` returns RGBA for a position, y = 0 is the top row.
private func makeImage(side: Int, pixel: (Int, Int) -> [UInt8]) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    for y in 0..<side {
        for x in 0..<side {
            let p = pixel(x, y)
            for c in 0..<4 { rep.bitmapData![(y * side + x) * 4 + c] = p[c] }
        }
    }
    let image = NSImage(size: NSSize(width: side, height: side))
    image.addRepresentation(rep)
    return image
}

/// RGBA bytes of an image, top row first.
private func bytes(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}

private let red: [UInt8] = [255, 0, 0, 255]
private let green: [UInt8] = [0, 255, 0, 255]

@Test func outputHasExactlyTheRequestedSize() throws {
    let image = try #require(IconRenderer.render([makeImage(side: 1024) { _, _ in red }], side: 17))
    #expect(image.width == 17)
    #expect(image.height == 17)
    let data = bytes(image)
    let centre = (8 * 17 + 8) * 4
    #expect(Array(data[centre..<centre + 4]) == red)
}

@Test func sourceAtTargetSizePassesThroughUnchanged() throws {
    let checker = makeImage(side: 17) { x, y in (x + y) % 2 == 0 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
    let data = bytes(try #require(IconRenderer.render([checker], side: 17)))
    for y in 0..<17 {
        for x in 0..<17 {
            #expect(data[(y * 17 + x) * 4] == ((x + y) % 2 == 0 ? 255 : 0))
        }
    }
}

@Test func nothingToDrawGivesNil() {
    #expect(IconRenderer.render([], side: 17) == nil)
    #expect(IconRenderer.render([makeImage(side: 32) { _, _ in red }], side: 0) == nil)
}

@Test func cutoutIsTransparent() throws {
    let cutout = CGRect(x: 8, y: 0, width: 9, height: 8)
    let data = bytes(try #require(IconRenderer.render([makeImage(side: 17) { _, _ in red }], side: 17, cutout: cutout)))
    #expect(data[(0 * 17 + 8) * 4 + 3] == 0)      // top-left corner of the cutout
    #expect(data[(7 * 17 + 16) * 4 + 3] == 0)     // bottom-right corner of the cutout
    #expect(data[(0 * 17 + 7) * 4 + 3] == 255)    // left of the cutout
    #expect(data[(8 * 17 + 16) * 4 + 3] == 255)   // below the cutout
}

@Test func pileLayoutFrontLowAndLargeOthersSmallerAndHigher() {
    #expect(IconRenderer.pileLayout(side: 17, count: 3) == [PileLayer(side: 15, x: 1, top: 2), PileLayer(side: 13, x: 2, top: 1), PileLayer(side: 11, x: 3, top: 0)])
    #expect(IconRenderer.pileLayout(side: 17, count: 2) == [PileLayer(side: 15, x: 1, top: 2), PileLayer(side: 13, x: 2, top: 1)])
    #expect(IconRenderer.pileLayout(side: 17, count: 1) == [PileLayer(side: 17, x: 0, top: 0)])
    #expect(IconRenderer.pileLayout(side: 17, count: 5).count == 3)
}

@Test func pileDrawsTheFrontImageOnTop() throws {
    let images = [makeImage(side: 64) { _, _ in red }, makeImage(side: 64) { _, _ in green }]
    let data = bytes(try #require(IconRenderer.render(images, side: 17)))
    let centre = (9 * 17 + 8) * 4
    #expect(Array(data[centre..<centre + 4]) == red)      // front covers the middle
    // row 1 belongs only to the layer behind (top 1); the front starts at row 2. It is an edge row, so Lanczos leaves it partly transparent.
    let peek = (1 * 17 + 8) * 4
    #expect(data[peek] == 0)
    #expect(data[peek + 1] > 150)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter IconRenderer`
Expected: compile error, `cannot find 'IconRenderer' in scope`.

- [ ] **Step 3: Implement IconRenderer**

`Sources/CleanDockCore/IconRenderer.swift`:

```swift
import AppKit
import CoreImage

public struct PileLayer: Equatable {
    public let side: Int
    public let x: Int
    public let top: Int

    public init(side: Int, x: Int, top: Int) {
        self.side = side
        self.x = x
        self.top = top
    }
}

public enum IconRenderer {
    private static let context = CIContext()

    /// Layers of a tile, front first. One image fills the canvas. A pile puts the front image low and large
    /// and each image behind it two pixels smaller and one pixel higher.
    public static func pileLayout(side: Int, count: Int) -> [PileLayer] {
        guard count > 1 else { return [PileLayer(side: side, x: 0, top: 0)] }
        return (0..<min(count, 3)).map { PileLayer(side: side - 2 - 2 * $0, x: 1 + $0, top: 2 - $0) }
    }

    /// `images` front first. The result is side×side pixels, sRGB, premultiplied alpha, transparent background.
    public static func render(_ images: [NSImage], side: Int, cutout: CGRect? = nil) -> CGImage? {
        guard !images.isEmpty, side > 0,
              let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        canvas.interpolationQuality = .none
        let layers = pileLayout(side: side, count: images.count)
        for (image, layer) in zip(images, layers).reversed() where layer.side > 0 {
            guard let scaled = downscale(image, to: layer.side) else { continue }
            canvas.draw(scaled, in: CGRect(x: layer.x, y: side - layer.top - layer.side, width: layer.side, height: layer.side))
        }
        if let cutout {
            canvas.clear(CGRect(x: cutout.minX, y: CGFloat(side) - cutout.maxY, width: cutout.width, height: cutout.height))
        }
        return canvas.makeImage()
    }

    /// Lanczos downscale from the largest representation. A source that already has the target size is returned as is.
    static func downscale(_ image: NSImage, to side: Int) -> CGImage? {
        var proposed = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        if source.width == side && source.height == side { return source }
        let scaled = CIImage(cgImage: source).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: Double(side) / Double(source.height),
            kCIInputAspectRatioKey: Double(source.height) / Double(source.width),
        ])
        return context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: side, height: side))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IconRenderer`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDockCore/IconRenderer.swift Tests/CleanDockCoreTests/IconRendererTests.swift
git commit -m "feat: Lanczos icon renderer with pile layout and badge cutout"
```

---

### Task 5: RenderCache

**Files:**
- Create: `Sources/CleanDockCore/RenderCache.swift`
- Test: `Tests/CleanDockCoreTests/RenderCacheTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct RenderKey: Hashable { path: String; modified: Date?; side: Int; dark: Bool; badgeLength: Int }` with a public memberwise init.
  - `final class RenderCache { init(limit: Int = 256); func image(for key: RenderKey, make: () -> CGImage?) -> CGImage?; func removeAll(); var count: Int }` — a `nil` result from `make` is cached too, so a tile that cannot render does not retry every frame.

- [ ] **Step 1: Write the failing tests**

`Tests/CleanDockCoreTests/RenderCacheTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import CleanDockCore

private func pixel() -> CGImage {
    CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

private func key(path: String = "/Applications/A.app", modified: Double = 1, side: Int = 17, dark: Bool = false, badge: Int = 0) -> RenderKey {
    RenderKey(path: path, modified: Date(timeIntervalSince1970: modified), side: side, dark: dark, badgeLength: badge)
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
    for k in [key(), key(path: "/Applications/B.app"), key(modified: 2), key(side: 32), key(dark: true), key(badge: 1)] {
        _ = cache.image(for: k) { made += 1; return pixel() }
    }
    #expect(made == 6)
    #expect(cache.count == 6)
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

@Test func cacheEmptiesItselfAtTheLimit() {
    let cache = RenderCache(limit: 3)
    for side in 1...4 { _ = cache.image(for: key(side: side)) { pixel() } }
    #expect(cache.count == 1)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RenderCache`
Expected: compile error, `cannot find 'RenderCache' in scope`.

- [ ] **Step 3: Implement RenderCache**

`Sources/CleanDockCore/RenderCache.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RenderCache`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDockCore/RenderCache.swift Tests/CleanDockCoreTests/RenderCacheTests.swift
git commit -m "feat: render cache"
```

---

### Task 6: StabilityDetector

**Files:**
- Create: `Sources/CleanDockCore/StabilityDetector.swift`
- Test: `Tests/CleanDockCoreTests/StabilityDetectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct StabilityDetector<State: Equatable> { init(quietPeriod: TimeInterval); mutating func observe(_ state: State, at time: TimeInterval) -> (changed: Bool, settled: Bool) }` — `changed` is true for the first observation and whenever the state differs from the previous one; `settled` is true once the state has not changed for longer than `quietPeriod`.

- [ ] **Step 1: Write the failing tests**

`Tests/CleanDockCoreTests/StabilityDetectorTests.swift`:

```swift
import Testing
@testable import CleanDockCore

@Test func firstObservationIsAChange() {
    var detector = StabilityDetector<Int>(quietPeriod: 0.3)
    let r = detector.observe(1, at: 10)
    #expect(r.changed)
    #expect(!r.settled)
}

@Test func settlesAfterTheQuietPeriod() {
    var detector = StabilityDetector<Int>(quietPeriod: 0.3)
    _ = detector.observe(1, at: 10)
    #expect(detector.observe(1, at: 10.1) == (false, false))
    #expect(detector.observe(1, at: 10.25) == (false, false))
    #expect(detector.observe(1, at: 10.31) == (false, true))
}

@Test func aChangeRestartsTheQuietPeriod() {
    var detector = StabilityDetector<Int>(quietPeriod: 0.3)
    _ = detector.observe(1, at: 10)
    #expect(detector.observe(2, at: 10.25) == (true, false))
    #expect(detector.observe(2, at: 10.5) == (false, false))
    #expect(detector.observe(2, at: 10.56) == (false, true))
}

@Test func optionalStatesCompareByValue() {
    var detector = StabilityDetector<Int?>(quietPeriod: 0.3)
    #expect(detector.observe(nil, at: 0).changed)
    #expect(!detector.observe(nil, at: 0.1).changed)
    #expect(detector.observe(5, at: 0.2).changed)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter StabilityDetector`
Expected: compile error, `cannot find 'StabilityDetector' in scope`.

- [ ] **Step 3: Implement StabilityDetector**

`Sources/CleanDockCore/StabilityDetector.swift`:

```swift
import Foundation

/// Tells a tracking burst when the observed state changed and when it has been quiet long enough to stop.
public struct StabilityDetector<State: Equatable> {
    private let quietPeriod: TimeInterval
    private var last: State?
    private var hasValue = false
    private var changedAt: TimeInterval = 0

    public init(quietPeriod: TimeInterval) { self.quietPeriod = quietPeriod }

    public mutating func observe(_ state: State, at time: TimeInterval) -> (changed: Bool, settled: Bool) {
        let changed = !hasValue || last != state
        if changed {
            last = state
            hasValue = true
            changedAt = time
        }
        return (changed, time - changedAt > quietPeriod)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: all tests of Tasks 1–6 pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDockCore/StabilityDetector.swift Tests/CleanDockCoreTests/StabilityDetectorTests.swift
git commit -m "feat: stability detector for tracking bursts"
```

---

### Task 7: DockReader and debug tools

Reads the Dock through the Accessibility API. There is no unit test: the deliverable is verified by running `--dump` against the real Dock.

**Files:**
- Create: `Sources/CleanDock/AX.swift`
- Create: `Sources/CleanDock/DockReader.swift`
- Create: `Sources/CleanDock/DebugTools.swift`
- Modify: `Sources/CleanDock/main.swift` (replace the whole file)

**Interfaces:**
- Consumes: nothing from Core.
- Produces:
  - `enum TileKind: Equatable { case app, folder, file, trash }`
  - `struct DockTile: Equatable { frame: CGRect; kind: TileKind; url: URL?; badge: String }` — `frame` in Accessibility coordinates.
  - `struct DockSnapshot: Equatable { tiles: [DockTile]; listFrame: CGRect; horizontal: Bool }`
  - `struct DockOutline: Equatable { frame: CGRect; count: Int }`
  - `final class DockReader { func snapshot() -> DockSnapshot?; func outline() -> DockOutline? }` — both return `nil` when the Dock cannot be read (not running, or no Accessibility permission). Not thread-safe: call from one queue.
  - `DebugTools.dump()` and `DebugTools.shot(to path: String)`.

- [ ] **Step 1: Write the Accessibility helpers**

`Sources/CleanDock/AX.swift`:

```swift
import ApplicationServices

enum AX {
    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Several attributes in one round trip. Missing attributes come back as error placeholders, never as a shorter array.
    static func values(_ element: AXUIElement, _ names: [String]) -> [Any]? {
        var out: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &out) == .success,
              let list = out as? [Any], list.count == names.count else { return nil }
        return list
    }

    static func point(_ value: Any) -> CGPoint? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ value: Any) -> CGSize? {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
```

- [ ] **Step 2: Write DockReader**

`Sources/CleanDock/DockReader.swift`:

```swift
import AppKit
import ApplicationServices

enum TileKind: Equatable { case app, folder, file, trash }

struct DockTile: Equatable {
    let frame: CGRect       // Accessibility coordinates: global points, top-left origin
    let kind: TileKind
    let url: URL?
    let badge: String
}

struct DockSnapshot: Equatable {
    let tiles: [DockTile]
    let listFrame: CGRect
    let horizontal: Bool
}

/// Cheap to read; changes whenever a tile is added or removed or the Dock resizes or moves.
struct DockOutline: Equatable {
    let frame: CGRect
    let count: Int
}

/// Not thread-safe: call from one queue.
final class DockReader {
    private static let tileAttributes = [kAXPositionAttribute, kAXSizeAttribute, kAXSubroleAttribute, kAXURLAttribute, "AXStatusLabel"]
    private static let frameAttributes = [kAXPositionAttribute, kAXSizeAttribute]
    // Separators, minimized windows and unknown kinds are left to the real Dock.
    private static let kinds: [String: TileKind] = [
        "AXApplicationDockItem": .app, "AXFolderDockItem": .folder, "AXDocumentDockItem": .file, "AXTrashDockItem": .trash,
    ]

    private var dock: AXUIElement?

    /// The Dock's tile list. Looks the Dock process up again when the cached element stopped answering (Dock restarted).
    private func list() -> AXUIElement? {
        for _ in 0..<2 {
            if dock == nil {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
                dock = AXUIElementCreateApplication(app.processIdentifier)
            }
            if let children: [AXUIElement] = AX.value(dock!, kAXChildrenAttribute), let list = children.first { return list }
            dock = nil
        }
        return nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let v = AX.values(element, Self.frameAttributes), let origin = AX.point(v[0]), let size = AX.size(v[1]) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func outline() -> DockOutline? {
        guard let list = list(), let frame = frame(list), let items: [AXUIElement] = AX.value(list, kAXChildrenAttribute) else { return nil }
        return DockOutline(frame: frame, count: items.count)
    }

    func snapshot() -> DockSnapshot? {
        guard let list = list(), let listFrame = frame(list), let items: [AXUIElement] = AX.value(list, kAXChildrenAttribute) else { return nil }
        let orientation: String = AX.value(list, kAXOrientationAttribute) ?? "AXHorizontalOrientation"
        var tiles: [DockTile] = []
        for item in items {
            guard let v = AX.values(item, Self.tileAttributes), let origin = AX.point(v[0]), let size = AX.size(v[1]),
                  let kind = Self.kinds[v[2] as? String ?? ""] else { continue }
            tiles.append(DockTile(frame: CGRect(origin: origin, size: size), kind: kind, url: v[3] as? URL, badge: v[4] as? String ?? ""))
        }
        return DockSnapshot(tiles: tiles, listFrame: listFrame, horizontal: orientation == "AXHorizontalOrientation")
    }
}
```

- [ ] **Step 3: Write the debug tools**

`--dump` prints what DockReader sees. `--shot <path>` saves an 8× nearest-neighbour zoom of the Dock strip, so a person or an agent can judge sharpness. `--shot` uses `/usr/sbin/screencapture` and therefore needs the Screen Recording permission for the terminal; the app itself never captures the screen.

`Sources/CleanDock/DebugTools.swift`:

```swift
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
```

- [ ] **Step 4: Replace main.swift**

`Sources/CleanDock/main.swift`:

```swift
import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--dump") {
    DebugTools.dump()
    exit(0)
}
if let index = arguments.firstIndex(of: "--shot"), index + 1 < arguments.count {
    DebugTools.shot(to: arguments[index + 1])
    exit(0)
}
print("Clean Dock")
```

- [ ] **Step 5: Verify against the real Dock**

Run (normal Terminal with Accessibility permission, not a sandboxed shell): `swift run CleanDock --dump`

Expected:
- `accessibility trusted: true`
- a `list` line with a frame about as wide as the Dock,
- one line per app, folder, file and Trash tile; no separator line,
- app tile frames 2 pt wider than the Dock's tile size (for example 19×31 at tile size 17),
- badge labels for apps that show a badge,
- `screen` lines with `scale=1.0` for a non-Retina display.

If it prints `accessibility trusted: false`, grant the terminal Accessibility permission in System Settings → Privacy & Security → Accessibility and run again.

Run: `swift run CleanDock --shot build/before.png` and open the PNG. Expected: an 8× zoom of the Dock strip with blurry icons. Keep this file for comparison in Task 8.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanDock
git commit -m "feat: read Dock tiles through the Accessibility API"
```

---

### Task 8: Static overlay for apps, files and folders

After this task `swift run CleanDock` shows sharp icons over the Dock at rest. It does not follow animations yet (Task 9), does not draw stacks or the Trash (Task 10) and has no menu (Task 11). Stop it with Ctrl-C.

**Files:**
- Create: `Sources/CleanDock/IconSource.swift`
- Create: `Sources/CleanDock/OverlayWindow.swift`
- Create: `Sources/CleanDock/AppController.swift`
- Create: `Sources/CleanDock/AppDelegate.swift`
- Modify: `Sources/CleanDock/main.swift` (replace the last line)

**Interfaces:**
- Consumes: `DockReader`, `DockSnapshot`, `DockTile`, `TileKind` (Task 7); `TileGeometry`, `BadgeCutout`, `IconRenderer`, `RenderCache`, `RenderKey` (Core).
- Produces:
  - `final class IconSource { var onChange: (() -> Void)?; func key(for tile: DockTile) -> (path: String, modified: Date?)?; func images(for tile: DockTile) -> [NSImage] }` — `key` is cheap and may be called every frame; `images` is only called on a cache miss. `key` returns `nil` for tiles that must stay uncovered.
  - `final class OverlayWindow { func show(on screen: NSScreen); func update(_ items: [(rect: CGRect, image: CGImage)]); func clear() }` — `rect` in points local to the screen, top-left origin.
  - `enum Status { case needsPermission, disabled, noDock, verticalDock, retinaDisplay, active }`
  - `final class AppController { var enabled: Bool; private(set) var status: Status; func start(); func apply(_ snapshot: DockSnapshot?); func refresh() }`
  - `final class AppDelegate: NSObject, NSApplicationDelegate`

- [ ] **Step 1: Write IconSource**

`Sources/CleanDock/IconSource.swift`:

```swift
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
```

- [ ] **Step 2: Write OverlayWindow**

`Sources/CleanDock/OverlayWindow.swift`:

```swift
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
        root.isGeometryFlipped = true        // layer coordinates: top-left origin, like the rects we get
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
        for (index, layer) in layers.enumerated() {
            if index < items.count {
                layer.frame = items[index].rect
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
```

- [ ] **Step 3: Write AppController**

`Sources/CleanDock/AppController.swift`:

```swift
import AppKit
import ApplicationServices
import CleanDockCore

enum Status { case needsPermission, disabled, noDock, verticalDock, retinaDisplay, active }

/// Wires reader, icons, cache and overlay together. Use from the main queue.
final class AppController {
    private let reader = DockReader()
    private let icons = IconSource()
    private let cache = RenderCache()
    private let overlay = OverlayWindow()
    private var last: DockSnapshot?

    private(set) var status = Status.noDock

    var enabled: Bool = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "enabled")
            refresh()
        }
    }

    func start() {
        icons.onChange = { [weak self] in
            self?.cache.removeAll()
            self?.refresh()
        }
        refresh()
    }

    /// Reads the Dock once and draws. Task 9 replaces the direct read with the tracker.
    func refresh() {
        apply(reader.snapshot())
    }

    func apply(_ snapshot: DockSnapshot?) {
        last = snapshot
        guard enabled else { return stop(.disabled) }
        guard AXIsProcessTrusted() else { return stop(.needsPermission) }
        guard let snapshot, !snapshot.tiles.isEmpty else { return stop(.noDock) }
        guard snapshot.horizontal else { return stop(.verticalDock) }
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? 0
        guard let screen = dockScreen(snapshot, primaryHeight: primaryHeight) else { return stop(.noDock) }
        guard screen.backingScaleFactor == 1 else { return stop(.retinaDisplay) }
        status = .active

        let scale = screen.backingScaleFactor
        let iconRects = snapshot.tiles.map { TileGeometry.iconRect(tile: $0.frame) }
        let resting = TileGeometry.restingSide(iconRects.map(\.width))
        let side = Int((resting * scale).rounded())
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        var items: [(rect: CGRect, image: CGImage)] = []
        for (tile, iconRect) in zip(snapshot.tiles, iconRects) {
            guard iconRect.width <= resting + 0.5,            // magnified tiles stay uncovered
                  let source = icons.key(for: tile) else { continue }
            let key = RenderKey(path: source.path, modified: source.modified, side: side, dark: dark, badgeLength: tile.badge.count)
            let image = cache.image(for: key) {
                IconRenderer.render(icons.images(for: tile), side: side, cutout: BadgeCutout.rect(side: side, label: tile.badge))
            }
            guard let image else { continue }
            let local = TileGeometry.toScreenLocal(iconRect, screenFrame: screen.frame, primaryHeight: primaryHeight)
            items.append((TileGeometry.snapped(local, scale: scale), image))
        }
        overlay.show(on: screen)
        overlay.update(items)
    }

    private func stop(_ status: Status) {
        self.status = status
        overlay.clear()
    }

    /// The screen the Dock is on. The vertical margin keeps the screen while tiles bounce or slide out for auto-hide.
    private func dockScreen(_ snapshot: DockSnapshot, primaryHeight: CGFloat) -> NSScreen? {
        let centre = CGPoint(x: snapshot.listFrame.midX, y: snapshot.listFrame.midY)
        return NSScreen.screens.first { screen in
            let f = screen.frame
            return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).insetBy(dx: 0, dy: -150).contains(centre)
        }
    }
}
```

- [ ] **Step 4: Write AppDelegate and finish main.swift**

`Sources/CleanDock/AppDelegate.swift`:

```swift
import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        controller.start()
    }
}
```

In `Sources/CleanDock/main.swift` replace the last line `print("Clean Dock")` with:

```swift
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Verify on the 1x display**

Preconditions: the Dock is on the non-Retina display (move the pointer to the bottom edge of that display and push down until the Dock moves there).

Run in one Terminal tab: `swift run CleanDock`
Run in a second tab: `swift run CleanDock --shot build/after.png`

Expected, comparing `build/before.png` (Task 7) with `build/after.png`:
- app, file and folder-as-folder icons are visibly sharper: clean squircle edges, readable glyphs,
- no box and no halo around any icon,
- badges are fully visible, with no sharp-icon pixels over them,
- stack folders and the Trash still show the blurry real icon,
- clicking a Dock icon still works (the overlay is click-through).

Move the Dock to the Retina display, stop and start `swift run CleanDock` again: the overlay must stay empty there.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanDock
git commit -m "feat: draw sharp icons over the Dock at rest"
```

---

### Task 9: MotionTracker — follow the Dock live

The Dock reports live animated tile frames through the Accessibility API about every 5–10 ms (slide, grow-in from 3.5 pt to full width, launch bounce of about 8 pt at tile size 17). The tracker reads them at a high rate during a burst and the overlay follows, so it never hides.

**Files:**
- Create: `Sources/CleanDock/MotionTracker.swift`
- Modify: `Sources/CleanDock/AppController.swift`

**Interfaces:**
- Consumes: `DockReader`, `DockSnapshot`, `DockOutline` (Task 7); `StabilityDetector` (Core); `AppController.apply(_:)` (Task 8).
- Produces:
  - `final class MotionTracker { init(reader: DockReader, apply: @escaping (DockSnapshot?) -> Void); func start(); func kick() }` — `apply` is called on the main queue. `kick()` is thread-safe, cheap, and starts or extends a burst.
  - `AppController.refresh()` now kicks the tracker instead of reading the Dock itself.
  - `AppController` gains mouse monitors and a private `draggedIndex: Int?`.

- [ ] **Step 1: Write MotionTracker**

`Sources/CleanDock/MotionTracker.swift`:

```swift
import CleanDockCore
import Foundation

/// Owns all Dock reads. Idle: a cheap outline check every 0.5 s and a full comparison every 2 s (catches badge changes).
/// Burst: reads the Dock as fast as it answers and forwards every change, until it has been stable for 0.3 s.
final class MotionTracker {
    private let reader: DockReader
    private let apply: (DockSnapshot?) -> Void
    private let queue = DispatchQueue(label: "app.cleandock.tracker", qos: .userInteractive)
    private let lock = NSLock()
    private var bursting = false
    private var kickedAt: TimeInterval = 0
    private var timer: DispatchSourceTimer?

    // Only touched on `queue`.
    private var lastOutline: DockOutline?
    private var lastSnapshot: DockSnapshot?
    private var ticks = 0

    init(reader: DockReader, apply: @escaping (DockSnapshot?) -> Void) {
        self.reader = reader
        self.apply = apply
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.idleTick() }
        timer.resume()
        self.timer = timer
        kick()
    }

    /// Starts a burst, or keeps the running one alive for at least another 0.3 s. Safe from any thread.
    func kick() {
        lock.lock()
        kickedAt = ProcessInfo.processInfo.systemUptime
        let start = !bursting
        bursting = true
        lock.unlock()
        if start { queue.async { [weak self] in self?.burst() } }
    }

    private func burst() {
        var detector = StabilityDetector<DockSnapshot?>(quietPeriod: 0.3)
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            let snapshot = reader.snapshot()
            let result = detector.observe(snapshot, at: now)
            if result.changed {
                lastSnapshot = snapshot
                DispatchQueue.main.async { [apply] in apply(snapshot) }
            }
            lock.lock()
            let done = result.settled && now - kickedAt > 0.3
            if done { bursting = false }
            lock.unlock()
            if done { break }
            usleep(4000)
        }
        lastOutline = reader.outline()
    }

    private func idleTick() {
        lock.lock()
        let busy = bursting
        lock.unlock()
        if busy { return }
        ticks += 1
        if ticks % 4 == 0 {
            if reader.snapshot() != lastSnapshot { kick() }
        } else if reader.outline() != lastOutline {
            kick()
        }
    }
}
```

- [ ] **Step 2: Route AppController through the tracker and add the triggers**

In `Sources/CleanDock/AppController.swift`:

Add these properties below `private var last: DockSnapshot?`:

```swift
    private lazy var tracker = MotionTracker(reader: reader) { [weak self] in self?.apply($0) }
    private var pressed: (index: Int, at: CGPoint)?
    private var draggedIndex: Int?
    private var monitors: [Any] = []
```

Replace `start()` and `refresh()` with:

```swift
    func start() {
        icons.onChange = { [weak self] in
            self?.cache.removeAll()
            self?.refresh()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tracker.kick() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tracker.kick()
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            self?.cache.removeAll()
            self?.tracker.kick()
        }
        installMouseMonitors()
        tracker.start()
    }

    /// Redraws from a fresh Dock read. A burst always applies its first read.
    func refresh() {
        tracker.kick()
    }

    /// Pointer position in Accessibility coordinates.
    private func pointer() -> CGPoint {
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height ?? 0
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private func installMouseMonitors() {
        func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (AppController) -> Void) {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                if let self { handler(self) }
            }
            if let monitor { monitors.append(monitor) }
        }
        add(.leftMouseDown) { c in
            let p = c.pointer()
            guard let index = c.last?.tiles.firstIndex(where: { $0.frame.contains(p) }) else { return }
            c.pressed = (index, p)
            c.tracker.kick()
        }
        add(.leftMouseDragged) { c in
            let p = c.pointer()
            if let pressed = c.pressed, c.draggedIndex == nil, hypot(p.x - pressed.at.x, p.y - pressed.at.y) > 3 {
                c.draggedIndex = pressed.index       // show the real drag image of this tile
                c.apply(c.last)
            }
            // anything dragged near the Dock makes its tiles move apart
            if let frame = c.last?.listFrame, frame.insetBy(dx: -60, dy: -60).contains(p) { c.tracker.kick() }
        }
        add(.leftMouseUp) { c in
            guard c.pressed != nil else { return }
            c.pressed = nil
            c.draggedIndex = nil
            c.tracker.kick()
        }
    }
```

In `apply(_:)`, change the loop header and its first guard from:

```swift
        for (tile, iconRect) in zip(snapshot.tiles, iconRects) {
            guard iconRect.width <= resting + 0.5,            // magnified tiles stay uncovered
                  let source = icons.key(for: tile) else { continue }
```

to:

```swift
        for (index, (tile, iconRect)) in zip(snapshot.tiles, iconRects).enumerated() {
            guard index != draggedIndex,                      // the real drag image must be visible
                  iconRect.width <= resting + 0.5,            // magnified tiles stay uncovered
                  let source = icons.key(for: tile) else { continue }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds without errors.

- [ ] **Step 4: Verify tracking on the 1x display**

Run: `swift run CleanDock`, then check each of these by eye on the non-Retina display:

1. Launch Calculator (not pinned): the other icons slide aside and stay sharp the whole time; the new icon grows in sharp; it bounces sharp. No flicker, no moment where icons go blurry.
2. Quit Calculator: its icon shrinks away and the others slide back, sharp all the time.
3. Drag a Dock icon sideways to reorder it: the real drag image is visible while dragging, the other icons stay sharp, and after the drop the moved icon becomes sharp again.
4. Drag a file from Finder over the Dock: tiles move apart and stay sharp.
5. Enable magnification in System Settings → Desktop & Dock, hover the Dock: magnified icons show the real Dock icon, icons at resting size stay sharp; after the pointer leaves, all icons are sharp again. Disable magnification again.
6. Run `killall Dock`: within about a second the sharp icons are back.
7. With the Dock idle, check CPU in Activity Monitor: Clean Dock stays below 1 %.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDock
git commit -m "feat: follow the Dock's live animations"
```

---

### Task 10: Stacks and the Trash

**Files:**
- Modify: `Sources/CleanDock/IconSource.swift` (replace the whole file)
- Modify: `Sources/CleanDock/AppController.swift` (one line in `start()`)

**Interfaces:**
- Consumes: `StackOrder`, `StackItem`, `StackArrangement` (Core); `DockTile`, `TileKind` (Task 7).
- Produces: same `IconSource` interface as Task 8, plus `func startTrashPolling()`. Behaviour added:
  - a folder tile whose Dock setting is "Display as Stack" renders the first three items as a pile, using QuickLook thumbnails for files when they arrive,
  - the Trash renders as the system full or empty Trash image; while the state is unknown or Finder automation is denied, `key` returns `nil` and the tile stays uncovered,
  - a stack folder that cannot be listed yields no images, so the tile stays uncovered.

- [ ] **Step 1: Replace IconSource**

`Sources/CleanDock/IconSource.swift`:

```swift
import AppKit
import CleanDockCore
import QuickLookThumbnailing

/// Maps a Dock tile to a cache key and to the images the renderer draws. Use from the main queue.
final class IconSource {
    /// Called on the main queue when something arrived that changes what tiles look like.
    var onChange: (() -> Void)?

    private var modifiedMemo: [String: (date: Date?, checked: TimeInterval)] = [:]
    private var thumbnails: [URL: NSImage] = [:]
    private var requested: Set<URL> = []
    private var trashFull: Bool?                     // nil: unknown, or Finder automation denied
    private var trashTimer: DispatchSourceTimer?

    /// Cheap: may be called for every tile on every frame. `nil` leaves the tile uncovered.
    func key(for tile: DockTile) -> (path: String, modified: Date?)? {
        switch tile.kind {
        case .app, .file, .folder:
            guard let path = tile.url?.path else { return nil }
            return (path, modified(path))
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
        if tile.kind == .folder, let arrangement = stackArrangement(of: url) {
            guard let items = stackItems(in: url) else { return [] }        // not readable: leave the tile to the Dock
            let front = StackOrder.front(items, arrangement: arrangement)
            if !front.isEmpty { return front.map { image(forStackItem: $0.url) } }
        }
        return [NSWorkspace.shared.icon(forFile: url.path)]
    }

    // MARK: Stacks

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
```

- [ ] **Step 2: Start the Trash polling**

In `Sources/CleanDock/AppController.swift`, in `start()`, add this line directly before `tracker.start()`:

```swift
        icons.startTrashPolling()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds without errors.

- [ ] **Step 4: Verify stacks and the Trash**

Run `swift run CleanDock` on the 1x display. When macOS asks whether the terminal may control Finder, allow it. When it asks for access to the Downloads folder, allow it.

1. A folder tile set to "Display as Stack" (right-click the tile → Display as → Stack) shows a sharp pile; the front item matches the real Dock's front item. Check one stack sorted by name and one sorted by date added.
2. For a stack with images or PDFs, the pile switches from file icons to previews within a second or two.
3. Right-click the tile → Display as → Folder: within two seconds the tile shows the sharp folder icon.
4. The Trash is sharp. Move a file to the Trash, wait up to ten seconds: the full Trash is shown. Empty the Trash: within ten seconds the empty Trash is shown.
5. Run `swift run CleanDock --shot build/stacks.png` in a second tab and inspect the three right-most tiles in the PNG: no box, no halo, sharp edges.
6. Deny case: run `tccutil reset AppleEvents`, start again and click "Don't Allow" on the Finder prompt: the Trash tile shows the real (blurry) Dock icon, everything else is sharp. Afterwards run `tccutil reset AppleEvents` again and allow it.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDock
git commit -m "feat: sharp stacks and Trash"
```

---

### Task 11: Menu bar, permissions and launch at login

**Files:**
- Create: `Sources/CleanDock/MenuBar.swift`
- Modify: `Sources/CleanDock/AppDelegate.swift` (replace the whole file)

**Interfaces:**
- Consumes: `AppController.enabled`, `AppController.status`, `AppController.refresh()`, `Status` (Task 8).
- Produces: `final class MenuBar: NSObject, NSMenuDelegate { init(controller: AppController) }`.

- [ ] **Step 1: Write MenuBar**

`Sources/CleanDock/MenuBar.swift`:

```swift
import AppKit
import ServiceManagement

final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
        super.init()
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Clean Dock")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch controller.status {
        case .needsPermission:
            menu.addItem(action("Accessibility Permission Needed…", #selector(openAccessibilitySettings)))
        case .disabled: menu.addItem(info("Off"))
        case .noDock: menu.addItem(info("Waiting for the Dock"))
        case .verticalDock: menu.addItem(info("Idle: the Dock is not at the bottom"))
        case .retinaDisplay: menu.addItem(info("Idle: the Dock is on a Retina display"))
        case .active: menu.addItem(info("Active"))
        }
        menu.addItem(.separator())
        let enabled = action("Enabled", #selector(toggleEnabled))
        enabled.state = controller.enabled ? .on : .off
        menu.addItem(enabled)
        let login = action("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clean Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleEnabled() { controller.enabled.toggle() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSSound.beep()      // only works from the bundled app, not from `swift run`
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
```

- [ ] **Step 2: Replace AppDelegate**

`Sources/CleanDock/AppDelegate.swift`:

```swift
import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var menuBar: MenuBar?
    private var permissionTimer: Timer?
    private var trusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        menuBar = MenuBar(controller: controller)
        controller.start()
        // Start on its own as soon as the permission is granted, and stop when it is taken away.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = AXIsProcessTrusted()
            if now != self.trusted {
                self.trusted = now
                self.controller.refresh()
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds without errors.

- [ ] **Step 4: Verify the menu**

Run `swift run CleanDock`:

1. A Dock-shaped icon appears in the menu bar. The first menu line says "Active" while the Dock is on the 1x display and "Idle: the Dock is on a Retina display" after moving the Dock to the built-in display.
2. Untick "Enabled": the sharp icons disappear at once and the first line says "Off". Tick it again: they are back within half a second. Quit and start again: the setting was remembered.
3. "Quit Clean Dock" ends the process and the overlay disappears.
4. "Launch at Login" beeps under `swift run`; that is expected and is verified with the bundled app in Task 12.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanDock
git commit -m "feat: menu bar, permission recheck and launch at login"
```

---

### Task 12: App bundle, README and manual checklist

**Files:**
- Create: `Support/Info.plist`
- Create: `Makefile`
- Create: `README.md`
- Create: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: the finished executable.
- Produces: `make app` → `build/CleanDock.app`; `make zip` → `build/CleanDock.zip`.

- [ ] **Step 1: Write Info.plist**

`Support/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>app.cleandock.CleanDock</string>
    <key>CFBundleName</key><string>Clean Dock</string>
    <key>CFBundleDisplayName</key><string>Clean Dock</string>
    <key>CFBundleExecutable</key><string>CleanDock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Clean Dock asks Finder whether the Trash is empty, so it can draw the right Trash icon.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Clean Dock reads which files are in this folder to draw its Dock stack.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Clean Dock reads which files are in this folder to draw its Dock stack.</string>
    <key>NSDesktopFolderUsageDescription</key><string>Clean Dock reads which files are in this folder to draw its Dock stack.</string>
</dict>
</plist>
```

- [ ] **Step 2: Write the Makefile**

`Makefile` (recipe lines start with a tab):

```make
APP = build/CleanDock.app

.PHONY: app zip test clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/CleanDock $(APP)/Contents/MacOS/CleanDock
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

zip: app
	cd build && rm -f CleanDock.zip && ditto -c -k --keepParent CleanDock.app CleanDock.zip

test:
	swift test

clean:
	rm -rf .build build
```

- [ ] **Step 3: Build and run the bundle**

Run: `make app && open build/CleanDock.app`

Expected:
- macOS asks for Accessibility permission for "Clean Dock". Grant it in System Settings; within three seconds the sharp icons appear without restarting the app.
- No Dock icon for Clean Dock itself; the menu bar icon is present.
- macOS asks once whether Clean Dock may control Finder, and once for a stack folder such as Downloads.
- Tick "Launch at Login": it stays ticked when the menu is opened again, and Clean Dock appears under System Settings → General → Login Items.

- [ ] **Step 4: Write the README**

`README.md`:

````markdown
# Clean Dock

Sharp Dock icons on non-Retina displays. Free and open source.

On a 1x display the macOS Dock draws small icons by downscaling a 128 px image with a
cheap filter, at fractional pixel positions. The result is blurry, and no setting fixes
it. Clean Dock draws a properly downscaled, pixel-aligned copy of every icon exactly on
top of the blurry one. The Dock itself is untouched: every click, drag, menu and
animation is still the real Dock.

## Install

Download `CleanDock.zip` from the releases page, unzip it and move `CleanDock.app` to
Applications. The app is not notarized, so the first time right-click it and choose
Open. Or build it yourself:

```
git clone <repository url>
cd CleanDock
make app
open build/CleanDock.app
```

## Permissions

- **Accessibility (required).** Clean Dock reads where the Dock's tiles are. It does not
  read or control anything else.
- **Automation → Finder (optional).** Used to ask whether the Trash is empty. Without it
  the Trash keeps the standard icon.
- **Folder access (optional).** Asked for folders you keep in the Dock as a stack, such as
  Downloads. Without it that stack keeps the standard icon.

Clean Dock never captures the screen and never connects to the network.

## How it behaves

- Active only while the Dock is at the bottom of a non-Retina display. Elsewhere it idles.
- Follows the Dock's animations live: launching, quitting, bouncing, reordering.
- Leaves to the real Dock: notification badges, running dots, minimized windows, magnified
  icons, and an icon while you drag it.
- The menu bar icon has an on/off switch, Launch at Login, and Quit.

## Development

```
swift test          # unit tests for the pure logic in CleanDockCore
swift run CleanDock # run from the terminal (the terminal needs Accessibility permission)
swift run CleanDock --dump           # print what Clean Dock reads from the Dock
swift run CleanDock --shot out.png   # 8x zoom of the Dock strip (terminal needs Screen Recording)
make app            # build/CleanDock.app, ad-hoc signed
```

Every `make app` produces a new ad-hoc signature, and macOS then treats the app as a new
one. After rebuilding, remove Clean Dock from System Settings → Privacy & Security →
Accessibility and grant it again, or run `tccutil reset Accessibility app.cleandock.CleanDock`.

`docs/manual-test-checklist.md` lists what to check by eye before a release.

## License

MIT
````

- [ ] **Step 5: Write the manual checklist**

`docs/manual-test-checklist.md`:

```markdown
# Manual test checklist

Run the bundled app (`make app`) with the Dock at the bottom of a non-Retina display.

## At rest
- [ ] App, file, folder, stack and Trash icons are sharp.
- [ ] No box and no halo around any icon.
- [ ] Badges are fully visible; a badge that appears or disappears is right within two seconds.
- [ ] Running dots and the separator look unchanged.
- [ ] Light mode and dark mode.

## Motion
- [ ] Launch an app that is not pinned: slide, grow-in and bounce stay sharp, no flicker.
- [ ] Quit it: shrink and slide back stay sharp.
- [ ] An app that bounces for attention stays sharp while bouncing.
- [ ] Drag a Dock icon to reorder it: the real drag image shows, the rest stays sharp.
- [ ] Drag a file from Finder onto an app in the Dock.
- [ ] Open a stack, close it again.
- [ ] Change the Dock size in System Settings: icons are sharp at the new size.
- [ ] Magnification on: magnified icons are the real ones, the rest stays sharp.

## Trash and stacks
- [ ] Trash full and empty, each within ten seconds.
- [ ] Stack sorted by name, stack sorted by date added; front item matches the real Dock.
- [ ] Folder shown as folder.

## Environment
- [ ] Auto-hide on: the sharp icons slide in and out with the Dock.
- [ ] Full-screen app: no sharp icons float on screen while the Dock is hidden.
- [ ] Mission Control and switching Spaces: the sharp icons stay on the Dock.
- [ ] Move the Dock to the Retina display and back.
- [ ] Unplug and replug the external display.
- [ ] Dock on the left: the overlay is empty and the menu says so.
- [ ] `killall Dock`: sharp icons are back within about a second.

## App
- [ ] Without Accessibility permission the menu offers to open System Settings; after granting, icons appear within three seconds.
- [ ] Enabled off and on; the setting survives a restart of the app.
- [ ] Launch at Login survives a logout.
- [ ] Idle CPU below 1 % in Activity Monitor.
```

- [ ] **Step 6: Run everything once more**

Run: `make test && make zip`
Expected: all tests pass; `build/CleanDock.zip` exists.

Work through `docs/manual-test-checklist.md`. Every item that fails is a bug to fix before this task is done; if a fix is not possible, record the item under a "Known limits" heading in `README.md`.

- [ ] **Step 7: Commit**

```bash
git add Support Makefile README.md docs/manual-test-checklist.md
git commit -m "feat: app bundle, README and manual test checklist"
```
