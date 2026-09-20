# Clean Dock — Design

Date: 2026-09-20
Status: approved approach, pending spec review

## Problem

On a 1x (non-Retina) display the macOS Dock draws small icons badly. Measured on
macOS 27 with a 3440×1440 monitor (about 110 ppi) and a Dock tile size of 17:

- The Dock always takes the 128 px representation of an icon and bilinear-downscales
  it to the tile. It never uses the 16 px or 32 px representations. This was the same
  at tile sizes 16, 17, 20, 24, 32, 48 and 64. A 1 px checkerboard in a test icon came
  out as flat grey.
- The Dock places tiles at fractional pixel positions (for example x = −1847.775), so
  the already soft icon is resampled once more.
- Clearing the icon caches, changing the tile size, and macOS 27's redrawn icon
  artwork do not change this. Injecting better small representations cannot work,
  because the Dock never reads them.

On a Retina display the Dock uses the 256 px representation and has twice the pixels,
and the result looks fine.

## Goal

Make Dock icons sharp on 1x displays while the standard Dock stays exactly as it is:
same behaviour, same look, same position. Clean Dock changes nothing except the pixels
of the icons. It is free and open source (MIT).

Non-goals: replacing the Dock, changing anything outside the Dock, changing app
bundles or icon files, improving Retina displays, whole-screen scaling tricks.

## Approach

Clean Dock is a background menu bar app. It reads the position of every Dock tile
through the Accessibility API and draws a sharp version of each icon exactly on top of
the blurry one, in a transparent, click-through window one level above the Dock. All
clicks, drags, menus and animations still belong to the real Dock.

Two throwaway spikes proved the approach on the target machine:

- **Overlay feasibility.** The Accessibility API returns exact tile frames, kinds,
  URLs, badge labels and running state. A borderless window at Dock level + 1 with
  `ignoresMouseEvents` sits over the Dock correctly on the external display.
- **Rendering.** Of seven variants compared on the real Dock, the clear winner was a
  Lanczos downscale from the 1024 px icon to a whole-pixel size, placed on whole
  pixels, with a transparent background. Sharpening and subpixel (ClearType-style)
  rendering looked worse. Variants that painted a background patch behind the icon
  produced a visible box; the transparent variant shows no box and no halo from the
  blurry icon underneath.
- **Live tracking.** During its animations the Dock reports live tile frames through
  the Accessibility API, changing about every 5–10 ms. This covers the slide when
  tiles shift, the grow-in of a new tile (width 3.5 → 19 pt) and the launch bounce
  (tile lifts 8 pt and returns). The overlay can follow the Dock frame by frame, so it
  never needs to hide or fade.

Rejected alternatives: a standalone replacement Dock (cannot be exactly the standard
Dock, thousands of lines), a full-cover overlay that redraws the whole Dock including
glass, dots and badges (three times the code, breaks when macOS restyles the Dock), and
pre-sharpened 128 px icons set as custom icons (low quality ceiling, leaks into Finder,
loses Liquid Glass icon styles on every screen).

## Scope of v1

- Swift and AppKit, Swift Package, macOS 14 or later, developed and tested on macOS 27.
- Runs as a menu bar app with no Dock icon (`LSUIElement`).
- Requires the Accessibility permission. Nothing else is mandatory.
- Active only while the Dock is on a display with a backing scale factor of 1. On a
  Retina display the overlay is empty and the tracking loop does not run.
- Supports the Dock at the bottom of the screen. With the Dock on the left or right the
  overlay stays empty.
- Covered tiles: applications, folders shown as a folder, folders shown as a stack,
  files and documents, and the Trash.
- Not covered: minimized-window tiles (live thumbnails) and any tile kind Clean Dock
  does not recognise. Those show the real Dock icon.

## Components

The package has a library target with the pure, testable logic and an app target with
everything that touches the system.

### CleanDockCore (library)

- **TileGeometry.** Converts a tile frame from Accessibility coordinates (top-left
  origin, points, possibly fractional) into the whole-pixel icon rectangle in screen
  coordinates. Calibrated at tile sizes 16 to 96: the tile frame is 2 pt wider than
  the tile size and 12 pt taller than wide below tile size 48, and 4 pt wider and
  16 pt taller from 48 up. The icon canvas is a square of the tile size, centred in
  the tile frame. The result is rounded to whole pixels, at rest and during motion.
- **BadgeCutout.** Computes the region at the top right of a tile where the real
  notification badge must stay visible, from the tile rectangle and the badge label
  length. The overlay leaves this region transparent.
- **StackOrder.** Sorts the contents of a stack folder by the Dock's own arrangement
  setting for that folder (name, date added, date modified, date created) and returns
  the first three items.
- **IconRenderer.** Takes one or more source images and a whole-pixel size and returns
  a bitmap. A single icon is downscaled from its 1024 px representation with
  `CILanczosScaleTransform`. A stack is drawn as a pile: the front item low and large,
  the two behind it smaller and shifted up by one pixel each.
- **RenderCache.** Caches rendered bitmaps by file path, modification date, pixel size,
  appearance (light or dark) and badge label length. Failed renders are cached too.
- **StabilityDetector.** Tells a tracking burst when the Dock changed and when it has
  been still long enough to stop.

### CleanDock (app)

- **DockReader.** Finds the Dock process, reads the tile list with batched attribute
  reads (`AXUIElementCopyMultipleAttributeValues`), and returns tile snapshots: frame,
  kind, URL, badge label, running state. Re-attaches when the Dock process restarts.
- **IconSource.** Maps a tile to source images. Applications, files and folders use
  `NSWorkspace.icon(forFile:)`. Stacks use QuickLook thumbnails
  (`QLThumbnailGenerator`) of the items chosen by StackOrder, falling back to the file
  icon. The Trash uses the system full or empty Trash image. Stack folder settings
  (`displayas`, `arrangement`) come from the `com.apple.dock` preferences.
- **OverlayWindow.** One transparent, borderless, click-through window that covers the
  Dock's whole screen (so bouncing icons are never clipped), at Dock window level + 1,
  on all Spaces. It holds one layer per covered tile, with
  implicit animations off and nearest-neighbour filtering so bitmaps map 1:1 to
  pixels.
- **MotionTracker.** Keeps the overlay glued to the Dock. While idle it compares a
  cheap outline (Dock frame and tile count) every 0.5 s and a full snapshot every 2 s,
  which catches badge changes. A tracking burst starts on any trigger: an app launch
  or quit notification, a changed outline or snapshot, a mouse-down on a tile, a drag
  near the Dock, a display or Space change. During a burst a loop on a background
  queue reads tile frames as fast as the Dock answers (about 100 times a second) and
  updates the layers on every change: position, size for tiles that grow or shrink,
  added and removed tiles. The burst ends when all frames have been stable for 0.3 s.
- **MenuBar.** Status item with an on/off switch, a launch-at-login toggle
  (`SMAppService`), a line that shows permission problems, and Quit.

## Behaviour details

- **Badges.** The real badge stays visible through the cutout. Clean Dock never draws
  badges.
- **Running dots, separator, Dock background.** Untouched; they lie outside the icon
  rectangles.
- **Drag inside the Dock.** When a drag starts on a tile (the pointer moves more than
  3 pt after mouse-down), the layer of that tile hides until mouse-up, so the real drag
  image is visible. A plain click does not hide anything.
- **Magnification.** If a tile's size differs from the resting tile size because of
  magnification, its layer hides until the size returns. Layers are only drawn at the
  resting size and during grow-in or shrink-out.
- **Auto-hide and full screen.** The overlay follows the reported frames, so it leaves
  the screen with the Dock.
- **Appearance changes.** On a light/dark or icon-style change the cache is dropped and
  all tiles are rendered again.
- **Icon changes.** An app update changes the file modification date, which misses the
  cache and renders the new icon.

## Permissions and failure handling

- **Accessibility missing.** The overlay stays empty. The menu shows the problem and a
  button that opens the right pane in System Settings. Clean Dock rechecks every few
  seconds and starts on its own once permission is granted.
- **Trash state.** Whether the Trash is full is asked from Finder, which needs a
  one-time Automation prompt. If that is denied, the Trash tile is left uncovered.
- **Stack folder not readable** (for example Downloads without permission). The stack
  tile is left uncovered.
- **Any tile that fails to render** is left uncovered. The real Dock icon is always the
  fallback; Clean Dock never draws a placeholder.
- **Dock process restarts.** DockReader re-attaches and a tracking burst starts.
- **No 1x display connected.** Clean Dock idles with no timers beyond the 0.5 s
  snapshot check.

## Testing

Unit tests (CleanDockCore):

- TileGeometry: fractional frames to whole-pixel rectangles, on displays left of,
  right of and above the primary display.
- BadgeCutout: region for one-, two- and three-character labels.
- StackOrder: each arrangement setting, hidden files skipped, fewer than three items.
- IconRenderer: output has exactly the requested pixel size; a source that is already
  the target size passes through unchanged; pile layout offsets.
- RenderCache: hit, miss on changed modification date, miss on size and appearance.

Manual checklist on a 1x display: icons sharp at rest; no box or halo; launch, quit,
bounce, drag-reorder, drag a file onto an app, stack open, Trash full and empty, badge
appears and disappears, auto-hide, full-screen app, Mission Control, Space switch,
Dock moved to the Retina display and back, display unplugged, Dock restarted with
`killall Dock`, light and dark mode.

## Build and release

- `swift build` and `swift test` for development. `make app` assembles
  `CleanDock.app` (Info.plist, ad-hoc signature).
- Releases are zips on GitHub. Without a paid Apple Developer account the app is not
  notarized; the README explains right-click → Open and building from source.
- MIT license. README covers what it does, the permission it needs and why, and the
  known limits above.
