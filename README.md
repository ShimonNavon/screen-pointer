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

## Annotating

- **⌃⌥D** turns the overlay into a drawing surface; the menu's **Tool** picks Arrow, Pen, Highlight
  or Rectangle. Draw over the screen, then **⌃⌥D** again to hand the mouse back to your apps.
- Annotations stay on screen (and in recordings) until "Clear annotations".
- While annotating, clicks go to the overlay, not to the app underneath — that is the point.

## Recording

- **⌃⌥R** starts recording the screen and **⌃⌥R** again stops it (menu bar shows ⏺ while recording).
- There is no length limit: it records until you stop it, bounded only by disk. Expect roughly
  1 GB per hour at 1080p (a 5-second clip is about 1.4 MB).
- Clips land in `~/Movies/Screen Pointer/Screen <date> <time>.mov`; the newest path is also written to
  `last-recording.txt` next to them, so an agent can pick it up without guessing.
- The ring is part of the recording, so pointing at something while recording is visible afterwards.
- The first recording may ask for Screen Recording permission for Screen Pointer.

Frames from a clip, for anyone who reads images rather than video:

```bash
ffmpeg -i "$(cat ~/Movies/'Screen Pointer'/last-recording.txt)" -vf fps=1 /tmp/frames/f%02d.png
```

## Install

```bash
./build.sh          # compiles and installs ~/Applications/Screen Pointer.app
open "$HOME/Applications/Screen Pointer.app"
```

The app lives in the menu bar as ◉ (hollow ○ when off).

## The panel

Click the menu-bar icon for a panel: highlight on/off, "Dim the rest", a drawing surface with
Arrow / Pen / Highlight / Box, colour swatches and a width slider, Undo and Clear, and the recorder
with its elapsed timer plus a shortcut to the last clip. Every setting is remembered between launches.

## Shortcuts

| Shortcut | What it does |
| --- | --- |
| ⌃⌥H | Highlight the cursor |
| ⌃⌥D | Hand the mouse to the overlay for drawing |
| ⌃⌥R | Start / stop a recording |

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
