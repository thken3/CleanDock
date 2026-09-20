# Manual test checklist

Run the bundled app (`make app`) with the Dock at the bottom of a non-Retina display.

## At rest
- [ ] App, file, folder, stack and Trash icons are sharp.
- [ ] A file (not a folder) pinned to the right side of the Dock is sharp.
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
- [ ] Switch a stack to Display as Folder and back, and change its sort order, without changing the folder's contents: the tile updates within about three seconds.

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
