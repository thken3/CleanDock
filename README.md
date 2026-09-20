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
