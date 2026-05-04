#!/bin/bash
# RightClickOnUpDev cert를 .p12로 export → base64로 인코딩 → GitHub secrets 등록 가이드 출력.
# Phase 2 release workflow가 동일한 cert로 서명하도록 secrets에 적재한다.
#
# 사용법: ./export-signing-cert.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

IDENTITY="${SIGNING_IDENTITY:-RightClickOnUpDev}"
P12="$DIR/$IDENTITY.p12"
B64="$DIR/$IDENTITY.p12.base64"

if ! security find-identity -p codesigning login.keychain-db | grep -q "\"$IDENTITY\""; then
    echo "❌ '$IDENTITY' identity가 login.keychain에 없습니다."
    echo "   먼저 ./create-signing-cert.sh로 생성하세요."
    exit 1
fi

# .p12 export 시 password 보호 필수 (security 명령어 요구사항).
# 사용자가 password를 정해 secret로도 등록한다.
read -s -p "Set .p12 export password (will be saved as SIGNING_CERT_PASSWORD secret): " PW
echo
read -s -p "Confirm: " PW2
echo
[ "$PW" = "$PW2" ] || { echo "❌ password mismatch"; exit 1; }
[ -n "$PW" ] || { echo "❌ password 비어있음"; exit 1; }

echo "[1/3] Exporting $IDENTITY → $P12"
security export -k login.keychain-db -t identities -f pkcs12 -P "$PW" -o "$P12" \
    || { echo "❌ export 실패"; exit 1; }

echo "[2/3] base64 인코딩 → $B64"
base64 -i "$P12" -o "$B64"

echo "[3/3] gh CLI로 secret 등록 (이미 로그인되어 있어야 함)"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh secret set SIGNING_CERT_P12_BASE64 < "$B64"
    printf '%s' "$PW" | gh secret set SIGNING_CERT_PASSWORD
    echo "  ✅ secrets 등록 완료"
else
    echo "  ⚠️  gh CLI 미설치 또는 미로그인 — 수동 등록 필요:"
    echo "    Settings → Secrets and variables → Actions → New repository secret"
    echo "      SIGNING_CERT_P12_BASE64 = (내용: $B64 의 전체 텍스트)"
    echo "      SIGNING_CERT_PASSWORD   = (위에서 입력한 password)"
fi

echo ""
echo "🧹 임시 파일 정리:"
echo "    rm -f \"$P12\" \"$B64\""
echo ""
echo "✅ 다음 'git push --tags' 시 release workflow가 이 cert로 서명합니다."
