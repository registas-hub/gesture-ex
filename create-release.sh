#!/bin/bash
# Release 자동화: build → zip(ditto) → SHA256 → git tag → push → GitHub Release
# 사용법:
#   ./create-release.sh v0.1.0
#   GH_TOKEN=<personal_access_token> ./create-release.sh v0.1.0
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

VERSION="${1:-}"
[ -z "$VERSION" ] && { echo "Usage: $0 v0.1.0"; exit 1; }

REPO="registas-hub/gesture-ex"
ZIP="gesture-ex-$VERSION.zip"

echo "[1/5] 빌드"
./build.sh > /dev/null
echo "  ✅ Built"

echo "[2/5] zip 생성 (ditto, Apple 표준)"
rm -f "$ZIP"
ditto -c -k --keepParent gesture-ex.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
SIZE=$(du -h "$ZIP" | awk '{print $1}')
echo "  ✅ $ZIP ($SIZE)"
echo "  SHA256: $SHA"

echo "[3/5] git tag $VERSION"
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "  ℹ️  tag '$VERSION' already exists, skipping"
else
    git tag -a "$VERSION" -m "Release $VERSION"
    git push origin "$VERSION"
    echo "  ✅ tagged & pushed"
fi

echo "[4/5] GitHub Release"
RELEASE_NOTES=$(cat <<RELEOF
First public release of **gesture-ex**.

### Highlights
- 🖱 Right-click on mouse-up (Windows-style) on macOS
- 🎯 4-direction + custom multi-segment mouse gestures for **Chromium** and **WebKit** browsers
- ✨ Live trail overlay with real-time action label
- 🌐 Per-engine on/off toggles (Chromium / WebKit independent)
- 🎨 Customizable trail color, background, opacity, lingering duration
- ⌨️ Global hotkey **⌥⌘G** to toggle on/off
- 🔏 Self-signed cert workflow → TCC permissions persist across rebuilds

### Install (manual)
1. Download \`$ZIP\` below
2. Unzip → drag \`gesture-ex.app\` to \`/Applications\`
3. Grant Accessibility + Input Monitoring permissions
4. Click the menu-bar icon → toggle ON

### Install (Homebrew, after tap setup)
\`\`\`bash
brew tap registas-hub/tap
brew install --cask gesture-ex
\`\`\`

### Build from source
\`\`\`bash
git clone https://github.com/$REPO.git
cd gesture-ex
./create-signing-cert.sh   # one-time TCC stability
./build.sh
open gesture-ex.app
\`\`\`

See [README](https://github.com/$REPO#readme) for full docs.
RELEOF
)

if gh api "repos/$REPO/releases/tags/$VERSION" --silent 2>/dev/null; then
    echo "  ℹ️  Release '$VERSION' already exists — uploading asset (clobber)"
    if gh release upload "$VERSION" "$ZIP" --repo "$REPO" --clobber 2>&1; then
        echo "  ✅ Asset uploaded"
    else
        RELEASE_FAILED=1
    fi
else
    if gh release create "$VERSION" "$ZIP" \
        --repo "$REPO" \
        --title "$VERSION" \
        --notes "$RELEASE_NOTES" 2>&1; then
        echo "  ✅ Release created"
    else
        RELEASE_FAILED=1
    fi
fi

if [ "${RELEASE_FAILED:-0}" = "1" ]; then
    echo ""
    echo "  ⚠️  GitHub Release 생성 실패 (현재 gh 토큰이 $REPO 에 권한 없음)"
    echo ""
    echo "  옵션 A — PAT 발급 후 재실행:"
    echo "    1. https://github.com/settings/tokens/new 에서 'repo' scope 토큰 생성"
    echo "    2. GH_TOKEN=ghp_... $0 $VERSION"
    echo ""
    echo "  옵션 B — GitHub UI에서 수동 생성:"
    echo "    https://github.com/$REPO/releases/new?tag=$VERSION"
    echo "    - 'Attach binaries' 영역에 $ZIP 첨부"
    echo "    - title: $VERSION"
fi

echo ""
echo "[5/5] Cask 작성용 메타데이터"
echo "  version:  ${VERSION#v}"
echo "  url:      https://github.com/$REPO/releases/download/$VERSION/$ZIP"
echo "  sha256:   $SHA"
