# Installation

[← Back to README](../README.md) · Other docs: [Usage](usage.md) · [Architecture](architecture.md) · [Development](development.md)

Three install paths, in order of effort:

1. [Homebrew](#install-with-homebrew) — one command, easiest.
2. [Pre-built release](#download-a-pre-built-release) — manual download from GitHub Releases.
3. [Build from source](#build-from-source) — for contributors and pinned-tip users.

After install, jump to [Grant permissions](#grant-permissions).

## Install with Homebrew

```bash
brew install --cask registas-hub/tap/gesture-ex
xattr -dr com.apple.quarantine /Applications/gesture-ex.app
```

The app is self-signed (not Apple Developer ID) and not notarized, so macOS quarantines the bundle Homebrew downloads. The second line strips that quarantine flag so the first launch isn't blocked by Gatekeeper. (Older guides used `brew install --cask --no-quarantine` — Homebrew 4.5 removed that switch; the manual `xattr` step replaces it.) GUI fallback: double-click, dismiss the warning, then **System Settings → Privacy & Security → Open Anyway**.

Upgrade with `brew upgrade --cask gesture-ex`. Uninstall with `brew uninstall --cask gesture-ex`. Re-run the `xattr` line after each upgrade — Homebrew re-quarantines the new build.

The cask lives at [registas-hub/homebrew-tap](https://github.com/registas-hub/homebrew-tap). Each release auto-publishes its `version` / `sha256` / `url` to the release notes, and the tap is updated separately.

## Download a pre-built release

1. Grab the latest zip from [Releases](https://github.com/registas-hub/gesture-ex/releases/latest) — `gesture-ex-vX.Y.Z.zip`.
2. Unzip and drag `gesture-ex.app` to `/Applications`.
3. **Bypass Gatekeeper (one-time).** The app is signed with a self-signed certificate (not Apple Developer ID) and not notarized, so macOS blocks the first launch with *“cannot be opened because Apple cannot check it for malicious software.”* Pick one:
   - **GUI** — double-click → dismiss the warning → **System Settings → Privacy & Security**, scroll to *“gesture-ex was blocked…”* → **Open Anyway** → confirm with Touch ID / password → click **Open** in the second prompt.
   - **Terminal (one-liner)** — strips the quarantine flag so Gatekeeper skips the check entirely:
     ```sh
     xattr -dr com.apple.quarantine /Applications/gesture-ex.app
     ```

   After the first bypass, future launches work normally. macOS 15 (Sequoia) blocks the older *right-click → Open* trick, so the two options above are the supported path.
4. [Grant permissions](#grant-permissions).

> Why no Apple-issued signature? This project isn't enrolled in the Apple Developer Program (\$99/year). The release binary is reproducibly signed with a stable self-signed identity (`RightClickOnUpDev`) so TCC permissions persist across rebuilds — see [Notable design decisions](architecture.md#notable-design-decisions).

## Build from source

### Prerequisites
- macOS 14 + (Sonoma — required by ScreenCaptureKit's macOS 14 API used in the Capture module)
- Swift toolchain (`xcode-select --install`)

### Build & run

```bash
# 1. Build
./build.sh

# 2. Launch
open gesture-ex.app
```

> Note: TCC permissions persist across rebuilds only if the build is signed with a stable identity (`RightClickOnUpDev`). The cert isn't checked into the repo — generate one yourself with `openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes -subj "/CN=RightClickOnUpDev" -addext "extendedKeyUsage=codeSigning"` and import it into your login keychain. Without this, `build.sh` falls back to ad-hoc signing and TCC re-prompts on every rebuild.

## Grant permissions

**System Settings → Privacy & Security**:

| Permission | Action |
|-----------|--------|
| Accessibility | `+` → `gesture-ex.app` → toggle ON |
| Input Monitoring | same |

Then click the menu-bar icon, toggle **Enable right-click on mouse-up** OFF → ON. Status row should read `Status: ON ✓`.

For *why* each permission is needed and the privacy posture, see [Architecture · Permissions](architecture.md#permissions).
