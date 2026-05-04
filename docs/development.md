# Development

[← Back to README](../README.md) · Other docs: [Installation](installation.md) · [Usage](usage.md) · [Architecture](architecture.md)

## Project layout

```
gesture-ex/
├── Sources/
│   ├── main.swift             # entry point — NSApp boot
│   ├── App/                   # AppDelegate, HotkeyManager
│   ├── Core/                  # EventTapController, PathAnalyzer, ActionExecutor, BrowserDetector
│   ├── Domain/                # GestureDirection, GesturePattern, GestureAction, BrowserAction, KeyShortcut, MouseAction, ...
│   ├── Storage/               # GestureMappings, CustomGestureMappings, OverlayPreferences, AppFilter
│   └── UI/                    # SettingsWindow, GestureTrailWindow, AddGestureController, ...
├── Resources/
│   └── AppIcon.icns           # bundle icon — copied into the .app at build time
├── scripts/
│   └── generate-icon.sh       # one-shot regenerator for AppIcon.icns
├── docs/                      # this directory
├── Info.plist                 # Bundle metadata (CFBundleIconFile = AppIcon)
├── build.sh                   # swiftc + codesign + bundle
├── README.md
└── .gitignore
```

## Iterate

```bash
# After editing any source file:
pkill -f gesture-ex
./build.sh
open gesture-ex.app
```

Stable code-signing identity means the rebuilt binary has the same code-signing authority — TCC keeps the previously granted permissions. **No re-authorization on rebuild.** See [Architecture · Notable design decisions](architecture.md#notable-design-decisions) for the rationale.

## Pull request workflow

`main` is protected by a repository ruleset that requires **1 approving review** before merge. The maintainer's `OrganizationAdmin` role is registered as a bypass actor, so solo merges go through with the admin flag:

```bash
gh pr merge <#> --squash --admin
```

This consumes the pre-configured bypass — no rule weakening involved. External contributor PRs are unaffected and still require a review. `--delete-branch` is redundant: `delete_branch_on_merge` is enabled at the repo level. Squash is the only allowed merge method (`allow_merge_commit = false`, `allow_rebase_merge = false`), so omitting `--squash` will fail.

## Adding a new action

1. Add a `case` to `BrowserAction` (`Sources/Domain/BrowserAction.swift`)
2. Provide `keyCode`, `flags`, `label` for the new case
3. Rebuild — the new action automatically appears in:
   - 4-direction mapping `popup`s
   - Custom-gesture action picker (under **Type → Built-in Action**)

For shortcuts you don't want to enshrine in `BrowserAction`, use the **Custom Shortcut** path in the *Add Custom Gesture* modal instead — `KeyShortcut` (`Sources/Domain/KeyShortcut.swift`) records an arbitrary `keyCode + CGEventFlags` pair from `NSEvent.keyDown`, and `GestureAction.shortcut(_:)` wraps it so `ActionExecutor.execute(_:)` synthesizes the keystroke the same way as built-ins. No code changes needed for one-off shortcuts.

For non-keyboard input — wheel scrolling and middle-click — use the **Mouse Action** path. `MouseAction` (`Sources/Domain/MouseAction.swift`) is a small enum (`scroll(direction, lines)` / `middleClick`) wrapped by `GestureAction.mouse(_:)`. `ActionExecutor` lowers it to `CGEvent(scrollWheelEvent2Source:units:.line:wheelCount:wheel1:wheel2:wheel3:)` for scrolling (vertical via `wheel1`, horizontal via `wheel2`) and to `otherMouseDown/Up` at the cursor position for middle-click.

## Adding a new browser

Append the bundle ID to `BrowserDetector.chromiumBundles` or `webkitBundles` in `Sources/Core/BrowserDetector.swift`.

## Regenerating the app icon

```bash
./scripts/generate-icon.sh   # rewrites Resources/AppIcon.icns
./build.sh                   # picks up the new icon
```

`scripts/generate-icon.sh` compiles a tiny inline Swift renderer that draws a Big Sur squircle background with the SF Symbol `cursorarrow.click.2` on top, emits all 10 standard `iconset` sizes, and packs them with `iconutil`. Edit colors, symbol, or weights inside the script and rerun.

## Releasing

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
