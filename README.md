# Screen Pointer

A tiny macOS menu-bar app that puts a ring around your cursor — so someone else (a person on a call, an
agent looking at screenshots) can see exactly what you are pointing at.

Built because screen-drawing overlays like Annotate are deliberately excluded from screen capture: the
person on the other end sees a clean screen no matter what you draw. This one is a normal window, so it
shows up in screenshots and recordings.

## What it does

- **⌃⌥H** toggles the highlight from any app, without taking keyboard focus — you can keep typing while
  the ring is on screen.
- A warm yellow ring follows the cursor on every desktop (Spaces) and every display.
- Optional spotlight: dim everything except a circle around the pointer (menu bar → "Dim the rest").
- Clicks pass straight through the overlay; it is never in the way.
- No accessibility or screen-recording permission needed.

## Install

```bash
./build.sh          # compiles and installs ~/Applications/Screen Pointer.app
open "$HOME/Applications/Screen Pointer.app"
```

The app lives in the menu bar as ◉ (hollow ○ when off).

## Menu

| Item | What it does |
| --- | --- |
| Show highlight | Toggle the overlay (same as ⌃⌥H) |
| Dim the rest (spotlight) | Switch between ring-only and a spotlight that darkens the rest of the screen |
| Quit | Exit |

## How it is built

One Swift file, no dependencies: `Sources/main.swift`.

- A borderless, non-activating `NSWindow` per screen at `.floating` level, `ignoresMouseEvents` so clicks
  land on whatever is underneath.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` so the pointer follows you
  across desktops.
- A 60 Hz timer redraws the ring at `NSEvent.mouseLocation`.
- A Carbon global hotkey (`RegisterEventHotKey`) toggles it from any app.

## Notes

- Kept at `.floating` level on purpose: at `.statusBar` it outranked system UI.
- Avoid `.transient`: it excludes the window from Mission Control, but macOS then also hides it on the
  active space.
