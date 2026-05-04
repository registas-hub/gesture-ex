# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu-bar utility (`LSUIElement`, accessory app) that

1. Converts right-click to fire on **mouse-up** instead of mouse-down at the HID level.
2. Recognizes 4-direction and multi-segment **mouse gestures** in Chromium and WebKit browsers, then synthesizes the mapped keystroke / wheel / middle-click.

Target: macOS 11+. Single Swift module, no SwiftPM, no Xcode project.

## Build / Run / Iterate

```bash
./build.sh                # swiftc compiles every Sources/**/*.swift into one module → gesture-ex.app
open gesture-ex.app

# Iteration loop after editing any source:
pkill -f gesture-ex && ./build.sh && open gesture-ex.app
```

Notes:
- `build.sh` finds every `Sources/**/*.swift` and feeds them to `swiftc -O` in one invocation. Adding a new `.swift` file under `Sources/` is automatic — no manifest to edit.
- Frameworks linked: `Cocoa`, `ServiceManagement`. Carbon is imported via `import Carbon.HIToolbox` for hotkey constants only.
- Version string is injected from `git describe --tags --always --dirty` into `CFBundleShortVersionString` / `CFBundleVersion` at build time.
- Code signing: prefers self-signed identity `RightClickOnUpDev` (keeps TCC permissions across rebuilds), falls back to ad-hoc (TCC re-prompts every build). Override with `SIGNING_IDENTITY="My Cert" ./build.sh`. The cert isn't in the repo — see `docs/installation.md` for the openssl one-liner if missing.

## Tests

There is **no test target, test directory, or test runner** in this repo. Verification is manual: build, launch, exercise the gesture / mouse-up flow in a real browser. Do not invent commands like `swift test` or `xcodebuild test` — they will fail. If a change needs verification beyond compilation, describe the manual reproduction steps instead.

## Architecture

5-layer split under `Sources/` (compiled together as one module — these are organizational, not module boundaries):

| Layer | Role | Notable types |
|---|---|---|
| `App/` | NSApp lifecycle, status-bar menu, global hotkey | `AppDelegate`, `HotkeyManager`, `PermissionChecker` |
| `Core/` | Event-tap pipeline and action dispatch | `EventTapController`, `PathAnalyzer`, `ActionExecutor`, `BrowserDetector` |
| `Domain/` | Pure value types (`Codable` enums, structs) | `GestureDirection`, `GesturePattern`, `GestureAction`, `BrowserAction`, `KeyShortcut`, `MouseAction`, `GestureSkipReason` |
| `Storage/` | `UserDefaults`-backed prefs (no DB, no files) | `GestureMappings`, `CustomGestureMappings`, `OverlayPreferences`, `BrowserPreferences`, `AppFilter`, `GestureAppFilter`, `HotkeyPreferences` |
| `UI/` | AppKit windows / panels (`nonactivatingPanel` for overlays) | `SettingsWindow`, `GestureTrailWindow`, `AddGestureController`, `BrowserActionPopup`, `GestureToast` |

### Event flow (the hot path)

1. `EventTapController.start()` registers a `CGEventTap` at **`kCGHIDEventTap`** (not session level — Chromium rejects synthesized events posted at session level). Mask = `rightMouseDown | rightMouseUp`.
2. `rightMouseDown`: `AppFilter.shouldApply(to: bundleID)` decides whether to convert. If yes, the event is **swallowed** (callback returns `nil`), a copy is stashed in `pendingDown`, and `onRightDown` fires the trail overlay. macOS's button-state machine never sees the press.
3. `GestureTrailWindow` polls `NSEvent.mouseLocation` at 60 Hz, drawing the trail and recording the path in CGEvent coordinates.
4. `rightMouseUp`:
   - Distance < 10 px → re-post the stashed `pendingDown` at the up location → normal context menu.
   - Distance ≥ 10 px ("intentional drag") → run `GestureAppFilter` and engine check (`gesturesEnabledForFrontmost`). Then `PathAnalyzer.analyze(path:)` extracts a multi-segment `GesturePattern`; falls back to single-direction `GestureRecognizer` from down/up only.
   - Match: custom multi-segment first (`CustomGestureMappings`), else single-direction `GestureMappings`. Result is a `GestureAction` (`.builtin(BrowserAction)` / `.shortcut(KeyShortcut)` / `.mouse(MouseAction)`).
   - `ActionExecutor.execute(action)` posts the synthesized event(s) at `cghidEventTap`. `eventSourceUserData = SYNTHETIC_TAG (0x4332_4F55_5055_5000)` flags the synthetic event so the same tap re-passes it on re-entry.
   - Once we're in the "drag" path, the original up is **always swallowed** (no fallback context menu) — even on `.disabled` or unmatched patterns the user gets a silent cancel, which is the deliberate UX policy.

`onGestureSkipped` carries a `GestureSkipReason` to the UI for diagnostic overlays — keep it populated when adding new short-circuit branches in `EventTapController.handle(...)`.

### Persistence

Everything is in `UserDefaults.standard`. There is no SQLite, no file-backed prefs, no migrations system. When adding a new pref:

- Default values must be returned via `UserDefaults.object(forKey:) == nil` check (not `.bool(forKey:)`, which can't distinguish "unset" from `false`). See `EventTapController.chromiumGesturesEnabled` for the canonical pattern.
- Codable values (`KeyShortcut`, custom gesture lists) are `JSONEncoder`/`JSONDecoder` round-tripped to `Data`. Encode failures must drop the write *before* posting the change notification (see `HotkeyPreferences.binding.set` for the rationale comment).
- Observers wire up via `NotificationCenter` (`.toggleHotkeyChanged`, etc.) — no Combine, no `@Observable`.

### Permissions

`PermissionChecker` exposes `accessibility` and `inputMonitoring` `PermissionStatus` values (`granted` / `denied` / `notDetermined`). Both are required for the HID tap. `AppDelegate` shows a startup alert (suppressible via `permissionAlert.suppressedAtLaunch`) and an explicit alert when toggle attempts fail. `Open Privacy Settings…` deep-links via `x-apple.systempreferences:` URLs.

### Adding things

- **New built-in action**: add a `case` to `BrowserAction` (`Sources/Domain/BrowserAction.swift`) with `keyCode` / `flags` / `label`. It auto-appears in the 4-direction popups and Custom Gesture *Built-in Action* picker.
- **One-off shortcut a user wants**: don't add to `BrowserAction` — use the *Custom Shortcut* path in the Add Custom Gesture modal, which records `keyCode + CGEventFlags` into a `KeyShortcut` at runtime.
- **New browser**: append the bundle ID to `BrowserDetector.chromiumBundles` or `webkitBundles` (`Sources/Core/BrowserDetector.swift`).
- **New non-keyboard action**: extend `MouseAction` and the corresponding branch in `ActionExecutor.postMouse(_:)`.

## Release

Tag-driven: pushing `vX.Y.Z` triggers `.github/workflows/release.yml` on `macos-14` (pinned — `macos-latest` has codesigning issues post-2026-04). It re-runs `build.sh` with the imported `RightClickOnUpDev` cert (from `SIGNING_CERT_P12_BASE64` / `SIGNING_CERT_PASSWORD` secrets), `ditto`-zips, computes SHA256, and creates the release. There is no local-only release path. `workflow_dispatch` with `dry_run=true` validates build/sign/zip without publishing.

## Repo workflow

- `main` is protected and requires 1 approving review. Maintainer's `OrganizationAdmin` is the bypass actor — solo merges go through with `gh pr merge <#> --squash --admin`.
- Squash is the only allowed merge method (`allow_merge_commit = false`, `allow_rebase_merge = false`). Omitting `--squash` will fail.
- `--delete-branch` is redundant — repo-level `delete_branch_on_merge` handles it.

## Documentation map

End-user / contributor docs live in `docs/` and are kept rich. Prefer reading them before implementing user-visible changes:

- `docs/architecture.md` — layered diagram, event flow, design decisions (HID vs session tap, self-signed vs ad-hoc, `nonactivatingPanel`).
- `docs/usage.md` — menu layout, Settings sections (Gestures / Overlay / Gesture Apps / Browsers / Right-click Apps), the `AppFilter` vs `GestureAppFilter` distinction.
- `docs/development.md` — iteration loop, adding actions/browsers, releasing.
- `docs/installation.md` — Homebrew / pre-built / from-source install paths and the `xattr -dr com.apple.quarantine` / Gatekeeper context.
