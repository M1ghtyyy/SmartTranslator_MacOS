#!/bin/bash
# Creates a self-signed code-signing certificate "SmartTranslator Dev" in the login keychain.
# With it, macOS keeps the Accessibility permission between rebuilds.
set -euo pipefail

NAME="${SIGN_IDENTITY:-SmartTranslator Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate \"${NAME}\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSWORD="smarttranslator-$RANDOM"

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf"
/usr/bin/openssl pkcs12 -export -name "$NAME" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout "pass:$PASSWORD"

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
# Signing and the Accessibility permission don't need the certificate to be trusted.
# TRUST=1 additionally marks it trusted for code signing (macOS asks for your password).
if [[ "${TRUST:-0}" == "1" ]]; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
fi

echo "✅ Created certificate \"${NAME}\". Now run Scripts/build-app.sh --install"
