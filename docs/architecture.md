# Architecture

[← Back to README](../README.md) · Other docs: [Installation](installation.md) · [Usage](usage.md) · [Development](development.md)

## Layered overview

```
                ┌──────────────────────────────────┐
                │   gesture-ex.app (LSUIElement)   │
                ├──────────────────────────────────┤
                │  AppDelegate          Menu bar   │
                │  GestureTrailWindow   Overlay    │
                │  SettingsWindow       Prefs UI   │
                │  AddGestureController Modal      │
                ├──────────────────────────────────┤
                │  EventTapController   HID tap    │
                │  PathAnalyzer         Pattern    │
                │  GestureRecognizer    Direction  │
                │  BrowserDetector      Frontmost  │
                │  ActionExecutor       Keystroke  │
                ├──────────────────────────────────┤
                │  GestureMappings                 │
                │  CustomGestureMappings   Codable │
                │  OverlayPreferences      JSON    │
                └──────────────────┬───────────────┘
                                   │
                                   ▼
                       kCGHIDEventTap  (lowest)
```

## Event flow

1. `EventTapController` registers a `CGEventTap` at `kCGHIDEventTap` — earlier than `kCGSessionEventTap`, important for Chromium's stricter input validation.
2. `rightMouseDown` is **swallowed** (callback returns `nil`). macOS's button-state machine never sees the press.
3. `GestureTrailWindow` polls `NSEvent.mouseLocation` at 60 Hz, drawing the trail and recording the path in CGEvent coordinates.
4. On `rightMouseUp`, `PathAnalyzer.analyze()` extracts a `GesturePattern` (array of `GestureDirection`) from the captured path.
5. Mapping lookup: custom multi-segment patterns first → fallback to single-direction `GestureMappings`. A custom-pattern match resolves to a `GestureAction` — a built-in `BrowserAction`, a user-recorded `KeyShortcut`, or a `MouseAction` (scroll / middle-click).
6. `ActionExecutor` synthesizes the corresponding HID-level event: a keyboard shortcut for built-ins and custom shortcuts (`Cmd+[`, `Cmd+R`, recorded `keyCode + CGEventFlags`, …), a `scrollWheelEvent2Source` line event for scroll actions, or `otherMouseDown/Up` at the gesture release position for middle-click. The browser (or any frontmost app) receives it as if the user actually performed the input.

Because everything happens at HID level and the browser only sees a synthetic keyboard shortcut, **no extension conflicts**. Disable any pre-existing CrxMouse / Smartup / Gesturefy.

## Tested browsers

**Chromium engine**: Chrome (stable / beta / canary / dev), Edge (all channels), Brave, Arc, Dia, Whale, Vivaldi, Opera, Opera GX, Yandex, CocCoc, open-source Chromium

**WebKit engine**: Safari, Safari Technology Preview, Orion (Kagi)

Adding a new browser = adding its bundle ID to `BrowserDetector.chromiumBundles` or `webkitBundles` and rebuilding. See [Development · Adding a new browser](development.md#adding-a-new-browser).

## Permissions

| Permission | Why |
|-----------|-----|
| Accessibility | Receive mouse events from HID layer |
| Input Monitoring | Required for HID event taps on macOS 10.15+ |

Both are scoped to the binary path, persisted by the self-signed code-signing identity (`RightClickOnUpDev`). No data leaves the machine; no network calls.

## Notable design decisions

- **Modular `Sources/` tree** — split by responsibility (App / Core / Domain / Storage / UI) so each layer has a single reason to change. `build.sh` compiles the whole tree as one Swift module, no SwiftPM overhead.
- **HID-level event tap** — session-level taps work for Finder but Chromium's renderer rejects synthesized events from session level. HID is necessary.
- **Self-signed certificate over ad-hoc** — ad-hoc signing changes `cdhash` every build, forcing TCC re-authorization. A stable cert keeps the same TCC identity across rebuilds without enrolling in Apple Developer Program.
- **`nonactivatingPanel` for overlays** — prevents the trail/label from stealing focus from the frontmost browser, which would otherwise route synthesized keystrokes back to `gesture-ex` itself.
- **60 Hz `NSEvent.mouseLocation` polling** — cheaper than another full event-tap subscription for `mouseMoved`, and sufficient for visual smoothness at any display refresh rate.
- **`includeIf` git config** — repository lives under `~/IdeaProjects/registas-hub/`, so a personal git identity activates automatically. Not visible in the repo, but documented here for contributors.
