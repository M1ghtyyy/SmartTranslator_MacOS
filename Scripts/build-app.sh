#!/bin/bash
# Builds SmartTranslator.app into ./build.
#   Scripts/build-app.sh            — build only
#   Scripts/build-app.sh --install  — also copy to ~/Applications, register the Services item and launch
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SmartTranslator"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-SmartTranslator Dev}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP="build/$APP_NAME.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# A stable certificate keeps the Accessibility permission across rebuilds;
# an ad-hoc signature changes every build and macOS asks for permission again.
IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
if grep -qF "\"$SIGN_IDENTITY\"" <<<"$IDENTITIES"; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
    echo "⚠️  Certificate \"${SIGN_IDENTITY}\" not found — signing ad-hoc."
    echo "   macOS will ask for Accessibility access again after every rebuild."
    echo "   To avoid that, run Scripts/create-dev-cert.sh once."
    codesign --force --sign - "$APP"
fi
echo "✅ Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    mkdir -p "$INSTALL_DIR"
    rm -rf "${INSTALL_DIR:?}/$APP_NAME.app"
    cp -R "$APP" "$INSTALL_DIR/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app"
    /System/Library/CoreServices/pbs -update || true
    open "$INSTALL_DIR/$APP_NAME.app"
    echo "✅ Installed and launched: $INSTALL_DIR/$APP_NAME.app"
fi
