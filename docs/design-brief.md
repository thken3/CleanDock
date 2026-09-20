# Clean Dock — Design Brief

This brief is for designing the app icon, the menu bar glyph, the first-run window and
the settings window of Clean Dock. The engine of the app already exists; nothing here
changes how it works. The design will be built in native AppKit/SwiftUI.

## What the app does

On a non-Retina (1x) display, the macOS Dock draws small icons badly. It takes a 128 px
image of each icon, shrinks it with a cheap filter and places it between pixels. At
Dock sizes of 16 to 32 px the icons look smeared, and no macOS setting fixes it.

Clean Dock fixes only that. It runs in the background, reads where each Dock icon is,
and draws a properly downscaled, pixel-aligned copy of the icon exactly on top of the
blurry one. The Dock itself is untouched: every click, drag, menu, badge, bounce and
animation is still the real Dock. The sharp icons follow the Dock's animations live, so
there is no flicker.

Facts that shape the design:

- Free and open source (MIT). No account, no network access, no screen capture.
- One required permission: **Accessibility**, used only to read where the Dock's tiles
  are. Two optional permissions: **Automation → Finder** (to know whether the Trash is
  full) and **folder access** for folders kept in the Dock as a stack (for example
  Downloads). Without an optional permission, that one tile keeps the standard icon.
- It works only where it is needed: when the Dock is at the bottom of a non-Retina
  display. On a Retina display, or with the Dock on the left or right, it idles and
  says so.
- The app has no Dock icon of its own. It lives in the menu bar.
- There is nothing to tune about the rendering. One method won a side-by-side test
  clearly, so there is no "sharpness" slider and there should not be one.

Audience: people with an external 1080p, 1440p or ultrawide monitor who notice and are
annoyed by the blur. Technical enough to grant a permission, but they want proof first
that the app does something and that the permission is harmless.

Tone: quiet utility. It should feel like a part of macOS that was missing, not like a
customisation tool. Native controls, system font, light and dark mode, macOS 26/27
Liquid Glass styling where the system provides it.

## What needs to be designed

### 1. App icon

Shown in Finder, in System Settings (Accessibility list, Login Items), in the
permission dialogs and on GitHub. It carries the trust: the user is asked to grant
Accessibility to this icon.

- Idea space: a Dock shape, or a single app-icon squircle, shown half blurry and half
  sharp; or a pixel grid snapping into focus. It must still read at 16 px — which is
  the point of the app, so the 16 px version should be visibly crisp.
- Standard macOS squircle icon grid.
- Deliver: 1024×1024 PNG, and if possible an Icon Composer `.icon` file with layers so
  it gets proper Liquid Glass, dark and tinted variants.

### 2. Menu bar glyph

- Monochrome template image, about 16–18 pt tall, pixel-aligned at 1x (the users of
  this app look at a 1x menu bar — a blurry glyph would be self-defeating).
- Two states: active, and idle/attention (not active here, or a permission is missing).
  The state must be readable without colour, for example a dimmed or slashed variant.
- Deliver: SVG or PDF, single colour, no background.

### 3. First-run window

Appears once, on first launch, and again whenever Accessibility is missing. Small fixed
window, about 560×440 pt, three steps.

1. **What it does.** One sentence and the before/after preview (see section 5), using
   the user's own Dock icons. This is the moment that earns the permission.
2. **Grant Accessibility.** Plain explanation: "Clean Dock reads where your Dock icons
   are. It cannot see your screen, your windows or what you type." A button "Open
   System Settings". The step shows a waiting state and completes by itself within a
   few seconds once the permission is granted — the user does not come back and click
   "Continue".
3. **Done.** "Your Dock is sharp now." A checkbox "Launch at login" (on by default), a
   note that the app lives in the menu bar, and a "Done" button. If the Dock is
   currently on a Retina display or not at the bottom, this step says so instead:
   "Clean Dock switches on by itself when your Dock is on a non-Retina display."

### 4. Settings window

Opened from the menu bar menu ("Settings…", ⌘,). One window, about 600×480 pt. Few
settings exist, so the window is mostly **status and proof**, not controls. Sections,
top to bottom or as tabs — the designer decides:

**Status (top, always visible)**
- A large on/off switch: "Sharpen Dock icons".
- One status line with an icon, exactly one of:
  - Active on *PL3486WQ* (the display's name)
  - Idle — the Dock is on a Retina display
  - Idle — the Dock is not at the bottom of the screen
  - Off
  - Needs Accessibility permission → button "Open System Settings"
  - Waiting for the Dock

**Preview**
- The before/after preview described in section 5.

**General**
- Launch at login (checkbox).
- Show icon in menu bar (checkbox). When this is off, the settings window opens by
  launching the app again; say that in a caption.

**Permissions**
A three-row list. Each row: name, one-line reason, a state (granted / not granted /
not asked yet) and a button that opens the right pane in System Settings.
- Accessibility — required — "Reads where your Dock icons are."
- Finder automation — optional — "Knows whether the Trash is full. Without it the Trash
  keeps its standard icon."
- Folder access — optional — "Draws stacks such as Downloads. Without it that stack
  keeps its standard icon." Lists the stack folders currently in the Dock, each with
  its own state.

**Dock animations (planned, design it but mark as "later")**
- Two switches that set hidden Dock preferences: "Bounce icons when apps launch" and
  "Bounce icons for notifications". Caption: "These change the Dock itself and apply
  to all displays."

**About (footer or last tab)**
- Icon, name, version. "Free and open source — MIT license." Links: GitHub, Report a
  problem. One reassurance line: "Clean Dock never captures your screen and never
  connects to the network."

### 5. The preview (the centrepiece)

The user must see, inside the app, what Clean Dock changes — without trusting a
marketing image. The preview renders the user's **own** Dock icons twice, live in the
app, with no screen capture:

- **Standard Dock:** each icon rendered the way the Dock does it (the 128 px image,
  cheap filter, placed between pixels).
- **Clean Dock:** the same icons rendered the way Clean Dock does it.

Layout to design:

- A **strip at real size** (1:1 pixels), looking like a piece of the Dock: the first
  six to eight icons on a Dock-like background, at the user's current Dock icon size.
- A **magnified view**, about 8× with visible square pixels, of one icon. Clicking an
  icon in the strip selects it for the magnified view.
- A **compare control**: a draggable vertical divider across both views (left of the
  divider = standard Dock, right = Clean Dock), with small labels. Alternative: a
  press-and-hold "Show standard Dock" button. The divider is preferred because both
  states are visible at once.
- Caption under the preview with the facts: "Icon size 17 px · Display PL3486WQ,
  110 ppi, non-Retina".
- Empty/edge states to design: the Dock is on a Retina display ("The Dock looks fine
  on this display — here is what Clean Dock does on a non-Retina display", preview
  still works); Accessibility not granted yet (preview works with a few default system
  icons: Finder, Safari, Mail, Settings, Trash).

Important for the mockup: the magnified pixels must be drawn with hard edges
(nearest-neighbour), and the 1:1 strip must not be scaled by the design tool, or the
preview will misrepresent both states.

### 6. Menu bar menu

Plain system menu, no custom drawing. Items, in order: status line (same wording as
the settings window; when Accessibility is missing the line is clickable and opens
System Settings) · separator · Enabled ✓ · Settings… ⌘, · separator · Quit Clean Dock
⌘Q. Launch at login moves into the settings window.

## Screens to deliver

1. App icon at 1024, 256, 64, 32 and 16 px, on light and dark backgrounds.
2. Menu bar glyph: active and idle, on a light and a dark menu bar, at 1x and 2x.
3. First-run window: steps 1, 2 (waiting) and 3, plus the step 3 variant "not active
   on this display".
4. Settings window: active state, needs-permission state, idle-on-Retina state; light
   and dark.
5. The preview component on its own, with the divider at 50 %, and the magnified view.
6. The menu bar menu: active, and needs-permission.

## Constraints for the build

- Native macOS controls only; everything must be buildable with standard AppKit or
  SwiftUI views plus one custom view (the preview).
- Minimum macOS 14; primary target macOS 26/27.
- All text in English, sentence case, no exclamation marks.
- Windows are fixed-size and not resizable. No onboarding videos or animations beyond
  the divider drag and standard system transitions.
- Accessibility of the UI itself: every state readable without colour, full keyboard
  operation, VoiceOver labels for the preview ("Standard Dock rendering", "Clean Dock
  rendering").
