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
| Right-click + draw an **L** (`↓→`), if registered | `↓→ Close Tab` — or any custom shortcut you recorded for that pattern |
| Right-click + tiny shake | normal context menu at release position |
| Right-click + ambiguous diagonal (↗) | silent cancel, no menu |
| Right-click + drag in Slack (non-browser) | normal context menu |

## Customize

Open Settings via `⇧⌘,` or menu → **Open Config…** — a sidebar window with four sections.

### Gesture Mappings

Pick an action for each cardinal direction (←/→/↑/↓). Each popup item shows the action name **and the keyboard shortcut that will be synthesized**, so you can predict the result in any app:

| Action | Shortcut | Action | Shortcut |
|---|---|---|---|
| Back | ⌘[ | New Window | ⌘N |
| Forward | ⌘] | Scroll to Top | Home |
| Reload | ⌘R | Scroll to Bottom | End |
| Hard Reload | ⇧⌘R | Find in Page | ⌘F |
| Stop Loading | ⌘. | Zoom In | ⌘= |
| New Tab | ⌘T | Zoom Out | ⌘− |
| Close Tab | ⌘W | Reset Zoom | ⌘0 |
| Reopen Closed Tab | ⇧⌘T | Next Tab | ⌘⌥→ |
| Disabled | (no key) | Previous Tab | ⌘⌥← |

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
4. Pick a **Type** for the action:
   - **Built-in Action** — choose one of the 13 predefined actions from the *Action* popup (same list as the 4-direction mappings).
   - **Custom Shortcut** — click **Record**, then press any key combination (e.g. `⇧⌘A`, `⌥F5`, `⌃Space`). The captured combo appears next to *Shortcut*. Press **Esc** with no modifiers to cancel recording, or click **Re-record** to overwrite.
   - **Mouse Action** — pick from the *Mouse* popup: `Scroll Up` / `Scroll Down` / `Scroll Left` / `Scroll Right` (with a `lines` stepper, 1–50; default 3) or `Middle Click`. Scroll fires line-unit wheel events; Middle Click fires `otherMouseDown/Up` at the gesture release position.
5. **Save** — pattern is persisted in `UserDefaults` and recognized next time

Custom Shortcut entries are listed as `Custom: ⇧⌘A`, mouse actions as `Scroll Down ×3` / `Middle Click`, so you can tell them apart from built-in actions at a glance. When a gesture matches, `ActionExecutor` synthesizes the corresponding HID-level event — keystroke, wheel scroll, or mouse button — so the frontmost app receives it as if you actually performed the input.

Each row in the list has **Edit** and **Remove** buttons. Edit reopens the same modal in *Edit Custom Gesture* mode with the existing pattern, Type, and action prefilled — change just the action, redraw the pattern, or both, then click **Update**. If you redraw into a new pattern, the original entry is replaced; if you keep the pattern, the existing mapping is overwritten in place.

Recognized by direction-change detection (segment ≥ 30 px, dominant axis ratio ≥ 1.5).

### Apps for Mouse Gestures (Gesture Apps)

Choose which apps fire mouse gestures. The mode dropdown decides how the engine check interacts with your list.

| Mode | Behavior |
|---|---|
| **All apps** (default) | Gestures run only in supported browsers (engine check active). Pattern list ignored. Same as the original behavior before Gesture Apps shipped. |
| **Whitelist (Only listed)** | Gestures run **only** in the listed apps — engine check is **bypassed**. Non-browser apps you add will fire gestures too. |
| **Blacklist (Exclude listed)** | Gestures run in every supported browser except the listed ones. Engine check still applies for non-listed apps. |

- **Patterns** — same syntax as Mouse-up Apps (one bundle ID per line, `regex:` prefix, `#` comments)
- **Choose App…** — pick a `.app` bundle from `/Applications` and the bundle ID is appended automatically

> Adding non-browser apps to the whitelist is supported, but be aware: gesture actions are keyboard shortcuts like `⌘[`, `⌘R`, `Home`/`End`. In non-browser apps these may do something different from "Back / Reload / Scroll-to-Top." `Scroll Top/Bottom`, `Close Tab`, and `New Tab` tend to behave consistently; `Back`/`Forward`/`Reload` are app-specific.

This filter is independent of [Apps for Right-click on Mouse-up](#apps-for-right-click-on-mouse-up-mouse-up-apps): you can have the right-click conversion run everywhere while restricting gesture recognition to a hand-picked set of apps (browser or otherwise).

### Apps for Right-click on Mouse-up (Mouse-up Apps)

Choose which apps the right-click on mouse-up conversion applies to. By default it runs in every app.

- **Mode** — All apps (default) / Only listed / Exclude listed
- **Patterns** — one bundle ID per line (`com.google.Chrome`); prefix with `regex:` for regex (`regex:^com\.google\..*`); `#` lines are comments
