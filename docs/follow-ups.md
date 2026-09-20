# Follow-ups after v1

Open items from the v1 code reviews. None blocks use.

## Not yet verified at runtime

The app was code-reviewed and unit-tested, but from the tracking work onward it was never
run during development (the development machine's screen was locked). Work through
`docs/manual-test-checklist.md`, and check these first:

1. With Enabled off, or Accessibility revoked, CPU drops to about 0 % (`ps -o %cpu=`).
2. With the Dock on a Retina display, Clean Dock reads the Dock once per change and at most
   every 2 s, and nothing more.
3. Moving the Dock from the Retina display to a non-Retina display brings the sharp icons
   within about 2 s, with no other action.
4. Granting Accessibility while the app runs starts it within about 3 s.
5. Dragging the Dock size slider: icons are the standard ones during the drag and repaint
   once, about 0.25 s after it stops.
6. A photo in a Downloads stack is letterboxed, not squashed.
7. Switching macOS to Clear or Tinted icons re-renders the Dock icons. The preference key for
   the icon style was not present on the development machine, so the render key carries an
   empty style there; the colour-preferences notification is the safety net.
8. A light/dark switch does not flash.
9. Dragging a file from Finder over the Dock: the sharp icons may lag up to 0.5 s while the
   Dock spreads, because global mouse monitors do not fire during another app's drag session.

## Small code follow-ups

- `AppController.refresh()` sets the tracker to `watching` whenever the app is enabled and
  trusted, which briefly downgrades an active tracker. It heals itself through the following
  `kick()`. Guard on the suspended case only.
- A theme switch can drop the cache up to three times (KVO plus two notifications). Rate-limit.
- Trash polling forks `osascript` immediately on an off→on flap; the wait has no timeout.
- `lastSide` is not reset when leaving `.active`, so a Dock resized while Clean Dock idled is
  uncovered for 0.25 s on return.
- `IconSource.key(for:)` lists each stack folder on the main queue once per 2 s.
- `TileGeometry.restingSide` breaks ties toward the larger side; on a Dock with very few
  tiles a magnified tile could win.
- `AppController.pointer()` hand-rolls a y-flip; use a `TileGeometry` helper.
- `MotionTracker.deinit` reads a queue-owned flag (harmless for a process-lifetime object).
- The multi-character badge cutout is backed by one three-digit measurement.
- Commit `8bb1cf9` likely does not build on its own (its app-side changes are in `25652f8`).

## Planned

- App icon, menu bar glyph, first-run window and settings window with a live before/after
  preview: see `docs/design-brief.md`.
- Optional toggles for the Dock's own launch and attention bounce.
