# Usage

[← Back to README](../README.md) · Other docs: [Installation](installation.md) · [Architecture](architecture.md) · [Development](development.md)

## Menu-bar overview

The menu-bar icon (`cursorarrow.click`) reveals:

```
Status: ON ✓
Active: Google Chrome — Chromium ✓
─────────
  Browser Gestures
✓   Chromium (Chrome / Edge / Brave / Arc / …)
✓   WebKit (Safari / Safari TP / Orion)
─────────
✓ Enable right-click on mouse-up    ⌥ ⌘ G
─────────
  Open Config…                      ⇧ ⌘ ,
─────────
  Launch at login
─────────
  Open Privacy Settings…
  About
  Quit                              ⌘ Q
```

Browser gestures depend on **Right-click on mouse-up** — when the master toggle is OFF, the Chromium and WebKit rows are grayed out (clickable only when the master is ON). When the master is ON but accessibility permission is missing, the section header reads `Browser Gestures (no permission)`.

The `Active:` line tells you whether the currently-frontmost app is recognized as a Chromium or WebKit browser, and whether its gestures are enabled — invaluable when something doesn't fire as expected.

## Quick examples

| Action | Result |
|--------|--------|
| Right-click + 50 px **left** in Chrome | `← Back` overlay → page goes back |
| Right-click + 80 px **down** in Safari | `↓ Scroll to Bottom` overlay → page scrolls to end |
| Right-click + draw an **L** (`↓→`), if registered | `↓→ Close Tab` (or whatever you mapped) |
| Right-click + tiny shake | normal context menu at release position |
| Right-click + ambiguous diagonal (↗) | silent cancel, no menu |
| Right-click + drag in Slack (non-browser) | normal context menu |

## Customize

Open Settings via `⇧⌘,` or menu → **Open Config…** — a sidebar window with four sections.

### Gesture Mappings

Pick an action for each cardinal direction (←/→/↑/↓).

13 actions are available out of the box:

> Back / Forward / Reload / Hard Reload / New Tab / Close Tab / Reopen Closed Tab / Next Tab / Previous Tab / New Window / Scroll to Top / Scroll to Bottom / Disabled

### Live Overlay

- **Trail color** — system color picker
- **Background color** — color picker for the floating action label
- **Background opacity** — 0–100 % slider
- **Show action label** — toggle (the trail itself stays regardless)
- **Linger duration** — Instant (0.2 s) / Short (0.5 s) / Medium (1 s) / Long (1.5 s) / Very Long (2 s)

### Custom Gestures

1. Click **+ Add Custom Gesture…**
2. Click and drag inside the drawing area to capture a pattern
3. Pattern preview updates live (e.g. `←↑`)
4. Pick an action
5. **Save** — pattern is persisted in `UserDefaults` and recognized next time

Recognized by direction-change detection (segment ≥ 30 px, dominant axis ratio ≥ 1.5).

### Apps for Mouse Gestures (Gesture Apps)

Choose which apps fire mouse gestures. By default gestures run in every supported browser; use this to limit them further.

- **Mode** — All apps (default) / Only listed / Exclude listed
- **Patterns** — same syntax as Mouse-up Apps (one bundle ID per line, `regex:` prefix, `#` comments)
- **Choose App…** — pick a `.app` bundle from `/Applications` and the bundle ID is appended automatically

Combined with the per-engine toggles (**Browser Gestures · Chromium / WebKit** in the menu bar), this filter is the AND-conjunction. A gesture only fires when *the engine is supported* AND *the app passes this filter*. Out-of-scope apps still receive the normal context menu on right-click + drag — gestures simply don't trigger.

This filter is independent of [Apps for Right-click on Mouse-up](#apps-for-right-click-on-mouse-up-mouse-up-apps): you can have the right-click conversion run everywhere while restricting gesture recognition to a few browsers.

### Apps for Right-click on Mouse-up (Mouse-up Apps)

Choose which apps the right-click on mouse-up conversion applies to. By default it runs in every app.

- **Mode** — All apps (default) / Only listed / Exclude listed
- **Patterns** — one bundle ID per line (`com.google.Chrome`); prefix with `regex:` for regex (`regex:^com\.google\..*`); `#` lines are comments
