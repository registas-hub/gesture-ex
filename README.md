# gesture-ex

> macOS menu-bar utility that brings **Windows-style right-click on mouse-up** behavior and **mouse gestures** to Chromium- and WebKit-based browsers.

[Features](#features) · [Install](#install) · [Usage](#usage) · [Customize](#customize) · [Architecture](#architecture)

---

## Why

On Windows / Linux, right-click triggers the context menu when the button is **released** — so you can press → drag → preview → release. macOS triggers on press, which:

1. Forces you to commit before seeing the context.
2. Breaks mouse-gesture extensions (CrxMouse, Smartup, Gesturefy) because the menu appears before any drag is detected.

`gesture-ex` shifts the trigger to mouse-up at the HID layer and adds native mouse gestures that don't rely on any browser extension.

## Features

### Right-click on mouse-up
Hold the right mouse button as long as you want, drag to a different spot, release — context menu appears at the release position. Or release in place for normal behavior.

### 4-direction mouse gestures
Drag with right-button held in a supported browser, release to fire an action.

| Default | Action            | Shortcut |
|---------|-------------------|----------|
| ←       | Back              | ⌘ [      |
| →       | Forward           | ⌘ ]      |
| ↑       | Scroll to Top     | Home     |
| ↓       | Scroll to Bottom  | End      |

13 actions are available out of the box: Back / Forward / Reload / Hard Reload / New Tab / Close Tab / Reopen Closed Tab / Next Tab / Previous Tab / New Window / Scroll to Top / Scroll to Bottom / Disabled.

### User-drawn custom gestures
Draw multi-segment patterns (`←↑`, `↓→`, `↑↓`, …) in the **Add Custom Gesture** modal and map each to any action. Recognized by direction-change detection (segment ≥ 30 px, dominant axis ratio ≥ 1.5).

### Live trail overlay
While dragging, a smooth blue trail follows the cursor with a floating label that **shows the action that will fire when you release**. The label updates in real time as the gesture direction changes.

### Per-engine toggles
Enable gestures independently for **Chromium** browsers and **WebKit** browsers — useful if you want gestures only in Chrome but not Safari, or vice versa.

### Adaptive fallback
- **Short click** (< 10 px) → context menu at release
- **Drag in non-browser app** → context menu at release
- **Drag with no recognizable direction** → silent cancel (no menu)
- **Drag matching a `Disabled` mapping** → context menu at release (intentional)
- **Drag matching a registered gesture** → action fires, menu suppressed

## Install

### Download a pre-built release (recommended)

1. Grab the latest zip from [Releases](https://github.com/registas-hub/gesture-ex/releases/latest) — `gesture-ex-vX.Y.Z.zip`.
2. Unzip and drag `gesture-ex.app` to `/Applications`.
3. **Bypass Gatekeeper (one-time).** The app is signed with a self-signed certificate (not Apple Developer ID) and not notarized, so macOS blocks the first launch with *“cannot be opened because Apple cannot check it for malicious software.”* Pick one:
   - **GUI** — double-click → dismiss the warning → **System Settings → Privacy & Security**, scroll to *“gesture-ex was blocked…”* → **Open Anyway** → confirm with Touch ID / password → click **Open** in the second prompt.
   - **Terminal (one-liner)** — strips the quarantine flag so Gatekeeper skips the check entirely:
     ```sh
     xattr -dr com.apple.quarantine /Applications/gesture-ex.app
     ```

   After the first bypass, future launches work normally. macOS 15 (Sequoia) blocks the older *right-click → Open* trick, so the two options above are the supported path.
4. Grant permissions (see [below](#grant-permissions)).

> Why no Apple-issued signature? This project isn't enrolled in the Apple Developer Program (\$99/year). The release binary is reproducibly signed with a stable self-signed identity (`RightClickOnUpDev`) so TCC permissions persist across rebuilds — see [Notable design decisions](#notable-design-decisions).

### Install with Homebrew

```bash
brew install --cask --no-quarantine registas-hub/tap/gesture-ex
```

`--no-quarantine` skips Gatekeeper because the app is self-signed (not Apple Developer ID). Without it, macOS will block the first launch with the same dialog as a manual download — recover via the steps in [Download a pre-built release](#download-a-pre-built-release-recommended).

Upgrade with `brew upgrade --cask gesture-ex`. Uninstall with `brew uninstall --cask gesture-ex`.

> **Tap status**: the `registas-hub/homebrew-tap` repository hosting the cask is on the roadmap. Until it ships, every release embeds a `Cask metadata` block in the release notes — drop the three fields into the template below as `gesture-ex.rb`, then `brew install --cask --no-quarantine ./gesture-ex.rb`:
> ```ruby
> cask "gesture-ex" do
>   version "X.Y.Z"          # paste from release notes
>   sha256 "<64-char-hex>"   # paste from release notes
>   url "https://github.com/registas-hub/gesture-ex/releases/download/v#{version}/gesture-ex-v#{version}.zip"
>   name "gesture-ex"
>   desc "Right-click on mouse-up + mouse gestures for macOS browsers"
>   homepage "https://github.com/registas-hub/gesture-ex"
>   app "gesture-ex.app"
> end
> ```

### Build from source

#### Prerequisites
- macOS 11 +
- Swift toolchain (`xcode-select --install`)

#### Build & run

```bash
# 1. (One-time) generate self-signed code signing cert.
#    Without this, TCC permissions reset on every rebuild.
./create-signing-cert.sh

# 2. Build
./build.sh

# 3. Launch
open gesture-ex.app
```

### Grant permissions

**System Settings → Privacy & Security**:

| Permission | Action |
|-----------|--------|
| Accessibility | `+` → `gesture-ex.app` → toggle ON |
| Input Monitoring | same |

Then click the menu-bar icon, toggle **Enable right-click on mouse-up** OFF → ON. Status row should read `Status: ON ✓`.

## Usage

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

### Quick examples

| Action | Result |
|--------|--------|
| Right-click + 50 px **left** in Chrome | `← Back` overlay → page goes back |
| Right-click + 80 px **down** in Safari | `↓ Scroll to Bottom` overlay → page scrolls to end |
| Right-click + draw an **L** (`↓→`), if registered | `↓→ Close Tab` (or whatever you mapped) |
| Right-click + tiny shake | normal context menu at release position |
| Right-click + ambiguous diagonal (↗) | silent cancel, no menu |
| Right-click + drag in Slack (non-browser) | normal context menu |

## Customize

Open via `⇧⌘,` or menu → **Open Config…** — a sidebar window with four sections.

### Gesture Mappings
Pick an action for each cardinal direction (←/→/↑/↓).

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

### Apps for Right-click on Mouse-up
Choose which apps the right-click on mouse-up conversion applies to. By default it runs in every app.
- **Mode** — All apps (default) / Only listed / Exclude listed
- **Patterns** — one bundle ID per line (`com.google.Chrome`); prefix with `regex:` for regex (`regex:^com\.google\..*`); `#` lines are comments

## Architecture

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

### Event flow

1. `EventTapController` registers a `CGEventTap` at `kCGHIDEventTap` — earlier than `kCGSessionEventTap`, important for Chromium's stricter input validation.
2. `rightMouseDown` is **swallowed** (callback returns `nil`). macOS's button-state machine never sees the press.
3. `GestureTrailWindow` polls `NSEvent.mouseLocation` at 60 Hz, drawing the trail and recording the path in CGEvent coordinates.
4. On `rightMouseUp`, `PathAnalyzer.analyze()` extracts a `GesturePattern` (array of `GestureDirection`) from the captured path.
5. Mapping lookup: custom multi-segment patterns first → fallback to single-direction `GestureMappings`.
6. `ActionExecutor` synthesizes a keyboard shortcut at HID level (`Cmd+[`, `Cmd+R`, …). The browser receives it as if the user pressed those keys.

Because everything happens at HID level and the browser only sees a synthetic keyboard shortcut, **no extension conflicts**. Disable any pre-existing CrxMouse / Smartup / Gesturefy.

## Tested browsers

**Chromium engine**: Chrome (stable / beta / canary / dev), Edge (all channels), Brave, Arc, Dia, Whale, Vivaldi, Opera, Opera GX, Yandex, CocCoc, open-source Chromium

**WebKit engine**: Safari, Safari Technology Preview, Orion (Kagi)

Adding a new browser = adding its bundle ID to `BrowserDetector.chromiumBundles` or `webkitBundles` and rebuilding.

## Permissions

| Permission | Why |
|-----------|-----|
| Accessibility | Receive mouse events from HID layer |
| Input Monitoring | Required for HID event taps on macOS 10.15+ |

Both are scoped to the binary path, persisted by the self-signed code-signing identity (`RightClickOnUpDev`) created by `create-signing-cert.sh`. No data leaves the machine; no network calls.

## Development

### Project layout

```
gesture-ex/
├── Sources/
│   ├── main.swift             # entry point — NSApp boot
│   ├── App/                   # AppDelegate, HotkeyManager
│   ├── Core/                  # EventTapController, PathAnalyzer, ActionExecutor, BrowserDetector
│   ├── Domain/                # GestureDirection, GesturePattern, BrowserAction, ...
│   ├── Storage/               # GestureMappings, CustomGestureMappings, OverlayPreferences, AppFilter
│   └── UI/                    # SettingsWindow, GestureTrailWindow, AddGestureController, ...
├── Resources/
│   └── AppIcon.icns           # bundle icon — copied into the .app at build time
├── scripts/
│   └── generate-icon.sh       # one-shot regenerator for AppIcon.icns
├── Info.plist                 # Bundle metadata (CFBundleIconFile = AppIcon)
├── build.sh                   # swiftc + codesign + bundle
├── create-signing-cert.sh     # one-time cert setup
├── export-signing-cert.sh     # one-time secret registration for the release workflow
├── README.md
└── .gitignore
```

### Iterate

```bash
# After editing any source file:
pkill -f gesture-ex
./build.sh
open gesture-ex.app
```

Stable code-signing identity means the rebuilt binary has the same code-signing authority — TCC keeps the previously granted permissions. **No re-authorization on rebuild.**

### Notable design decisions

- **Modular `Sources/` tree** — split by responsibility (App / Core / Domain / Storage / UI) so each layer has a single reason to change. `build.sh` compiles the whole tree as one Swift module, no SwiftPM overhead.
- **HID-level event tap** — session-level taps work for Finder but Chromium's renderer rejects synthesized events from session level. HID is necessary.
- **Self-signed certificate over ad-hoc** — ad-hoc signing changes `cdhash` every build, forcing TCC re-authorization. A stable cert keeps the same TCC identity across rebuilds without enrolling in Apple Developer Program.
- **`nonactivatingPanel` for overlays** — prevents the trail/label from stealing focus from the frontmost browser, which would otherwise route synthesized keystrokes back to `gesture-ex` itself.
- **60 Hz `NSEvent.mouseLocation` polling** — cheaper than another full event-tap subscription for `mouseMoved`, and sufficient for visual smoothness at any display refresh rate.
- **`includeIf` git config** — repository lives under `~/IdeaProjects/registas-hub/`, so a personal git identity activates automatically. Not visible in the repo, but documented here for contributors.

### Adding a new action

1. Add a `case` to `BrowserAction` (`Sources/Domain/BrowserAction.swift`)
2. Provide `keyCode`, `flags`, `label` for the new case
3. Rebuild — the new action automatically appears in:
   - 4-direction mapping `popup`s
   - Custom-gesture action picker

### Adding a new browser

Append the bundle ID to `BrowserDetector.chromiumBundles` or `webkitBundles` in `Sources/Core/BrowserDetector.swift`.

### Regenerating the app icon

```bash
./scripts/generate-icon.sh   # rewrites Resources/AppIcon.icns
./build.sh                   # picks up the new icon
```

`scripts/generate-icon.sh` compiles a tiny inline Swift renderer that draws a Big Sur squircle background with the SF Symbol `cursorarrow.click.2` on top, emits all 10 standard `iconset` sizes, and packs them with `iconutil`. Edit colors, symbol, or weights inside the script and rerun.

### Releasing

Releases are built and published by **GitHub Actions** on tag push (`.github/workflows/release.yml`).

**One-time setup** — register the signing cert as a repo secret so CI builds match local `cdhash`:

```bash
./create-signing-cert.sh         # if you don't have RightClickOnUpDev yet
./export-signing-cert.sh         # exports → base64 → registers SIGNING_CERT_P12_BASE64 + SIGNING_CERT_PASSWORD via gh CLI
rm -f RightClickOnUpDev.p12 RightClickOnUpDev.p12.base64   # cleanup local artifacts
```

If `gh` is not logged in, the script prints manual instructions for **Settings → Secrets and variables → Actions**.

**Cut a release**:

```bash
git tag -a v0.3.0 -m "Release v0.3.0"
git push origin v0.3.0
# → workflow runs on macos-14, signs with RightClickOnUpDev (or ad-hoc fallback if secrets missing),
#    zips with ditto, computes SHA256, and publishes the GitHub Release with auto-generated notes.
```

All releases go through the Actions workflow — there is no local-only release path.

## License

[MIT](./LICENSE) © Registas

## Author

[Registas](https://github.com/Registas) — repo at [registas-hub/gesture-ex](https://github.com/registas-hub/gesture-ex)
