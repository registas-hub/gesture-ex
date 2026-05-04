# Installation

[← Back to README](../README.md) · Other docs: [Usage](usage.md) · [Architecture](architecture.md) · [Development](development.md)

Three install paths, in order of effort:

1. [Homebrew](#install-with-homebrew) — one command, easiest.
2. [Pre-built release](#download-a-pre-built-release) — manual download from GitHub Releases.
3. [Build from source](#build-from-source) — for contributors and pinned-tip users.

After install, jump to [Grant permissions](#grant-permissions).

## Install with Homebrew

```bash
brew install --cask --no-quarantine registas-hub/tap/gesture-ex
```

`--no-quarantine` skips Gatekeeper because the app is self-signed (not Apple Developer ID). Without it, macOS will block the first launch with the same dialog as a manual download — recover via the steps in [Download a pre-built release](#download-a-pre-built-release).

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
- macOS 11 +
- Swift toolchain (`xcode-select --install`)

### Build & run

```bash
# 1. (One-time) generate self-signed code signing cert.
#    Without this, TCC permissions reset on every rebuild.
./create-signing-cert.sh

# 2. Build
./build.sh

# 3. Launch
open gesture-ex.app
```

## Grant permissions

**System Settings → Privacy & Security**:

| Permission | Action |
|-----------|--------|
| Accessibility | `+` → `gesture-ex.app` → toggle ON |
| Input Monitoring | same |

Then click the menu-bar icon, toggle **Enable right-click on mouse-up** OFF → ON. Status row should read `Status: ON ✓`.

For *why* each permission is needed and the privacy posture, see [Architecture · Permissions](architecture.md#permissions).
