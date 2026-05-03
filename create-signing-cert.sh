#!/bin/bash
# Self-signed code signing 인증서를 자동 생성해 login.keychain에 등록한다.
# 한 번만 실행하면 됨. 매 빌드 시 build.sh가 이 인증서로 서명한다.
set -euo pipefail

CERT_NAME="${SIGNING_IDENTITY:-RightClickOnUpDev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 이미 있으면 종료 (-v 없이: trust 미설정이어도 codesign에 사용 가능하므로 등록 자체만 확인)
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$CERT_NAME\""; then
    echo "✅ '$CERT_NAME' 인증서가 이미 존재합니다."
    exit 0
fi

echo "🔧 Generating self-signed code signing certificate '$CERT_NAME'…"

TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

# X.509 self-signed cert + key 생성 (codeSigning EKU 포함)
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$TMP/key.pem" \
    -out    "$TMP/cert.pem" \
    -subj   "/CN=$CERT_NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=digitalSignature" \
    2>/dev/null

# PKCS#12 컨테이너로 묶기. macOS security는 빈 비밀번호 처리에 버그가 있어 더미 패스 사용.
# OpenSSL 3 → security 호환을 위해 -legacy 옵션 (있으면) 사용.
DUMMY_PASS="tempPass"
PKCS12_LEGACY_FLAG=""
if openssl pkcs12 -help 2>&1 | grep -q "\-legacy"; then
    PKCS12_LEGACY_FLAG="-legacy"
fi

openssl pkcs12 -export $PKCS12_LEGACY_FLAG \
    -inkey   "$TMP/key.pem" \
    -in      "$TMP/cert.pem" \
    -out     "$TMP/cert.p12" \
    -passout "pass:$DUMMY_PASS" \
    -name    "$CERT_NAME"

# login.keychain에 import. -T /usr/bin/codesign 으로 codesign 도구가 액세스 가능.
security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$DUMMY_PASS" \
    -T /usr/bin/codesign \
    -A

# Best-effort: user keychain trust에 codeSign용으로 추가 (-v 검증도 통과시키려면 필요).
# 실패해도 codesign은 동작하므로 무시.
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || true

echo ""
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$CERT_NAME\""; then
    echo "✅ '$CERT_NAME' 등록 완료. 이제 ./build.sh 가 자동으로 이 인증서를 사용합니다."
    echo "   (첫 빌드 시 Keychain 비밀번호 프롬프트가 한 번 떠도 'Always Allow' 선택하시면 이후엔 안 뜸)"
else
    echo "❌ Import는 됐지만 인증서를 찾을 수 없습니다."
    echo "   Keychain Access에서 'login' 키체인에 '$CERT_NAME'이 있는지 확인."
    exit 1
fi
