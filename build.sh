#!/bin/bash
# gesture-ex.app 번들 빌드
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="gesture-ex"
APP="$DIR/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

echo "🧹 Cleaning previous build…"
rm -rf "$APP"

echo "📦 Creating app bundle skeleton…"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "🔨 Compiling Swift sources (Sources/**/*.swift)…"
# 모든 *.swift 파일을 한 번에 swiftc에 넘겨야 한 모듈로 컴파일된다.
# null-delimited으로 처리해 공백 포함 경로 안전.
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "$DIR/Sources" -name '*.swift' -print0)
swiftc "${SOURCES[@]}" \
    -o "$BIN" \
    -framework Cocoa \
    -framework ServiceManagement \
    -O

echo "📝 Installing Info.plist…"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"

# 코드 서명 — 자체 서명 인증서가 있으면 사용 (TCC 권한 영속화), 없으면 ad-hoc 폴백
# 사용자가 환경변수로 명시 가능: SIGNING_IDENTITY="My Cert" ./build.sh
SIGNING_IDENTITY="${SIGNING_IDENTITY:-RightClickOnUpDev}"

if security find-identity -p codesigning | grep -q "\"$SIGNING_IDENTITY\""; then
    echo "🔏 Signing with stable identity: $SIGNING_IDENTITY (TCC permissions will persist)"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
else
    echo "🔏 Ad-hoc signing (TCC permissions will reset on every build)"
    echo "   ℹ️  TIP: Create a self-signed code signing cert named '$SIGNING_IDENTITY'"
    echo "       in Keychain Access to keep permissions across rebuilds."
    codesign --force --deep --sign - "$APP"
fi

echo ""
echo "✅ Built: $APP"
echo ""
echo "▶ 실행:    open \"$APP\""
echo "▶ 위치:    $APP"
echo ""
