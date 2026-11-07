#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Boss Remote Dev.app"
SIGN_ID="${BOSS_REMOTE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/Apple Development/ { print $2; exit }')"
fi
if [[ -z "$SIGN_ID" ]]; then
  print -u2 "No Apple Development identity found; set BOSS_REMOTE_SIGN_IDENTITY"
  exit 1
fi

cd "$ROOT"
swift build -c debug --product BossRemote
swift build -c debug --product BossRemoteHCIService
BIN_DIR="$(swift build -c debug --show-bin-path)"

/bin/rm -rf "$APP"
/bin/mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources" \
  "$APP/Contents/Helpers" \
  "$APP/Contents/Frameworks"
/usr/bin/ditto "$BIN_DIR/BossRemote" "$APP/Contents/MacOS/BossRemote"
/usr/bin/ditto "$BIN_DIR/BossRemoteHCIService" \
  "$APP/Contents/Helpers/BossRemoteHCIService"
/usr/bin/ditto "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$ROOT/Resources/AppIcon.icns" \
  "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/ditto "$ROOT/Resources/SupportQR.png" \
  "$APP/Contents/Resources/SupportQR.png"
/usr/bin/ditto "$ROOT/Resources/libopus.0.dylib" \
  "$APP/Contents/Frameworks/libopus.0.dylib"
/bin/chmod 755 \
  "$APP/Contents/MacOS/BossRemote" \
  "$APP/Contents/Helpers/BossRemoteHCIService"
/usr/bin/codesign --force --options runtime --sign "$SIGN_ID" \
  --identifier com.bossremote.hci \
  "$APP/Contents/Helpers/BossRemoteHCIService"
/usr/bin/codesign --force --options runtime --sign "$SIGN_ID" \
  "$APP/Contents/Frameworks/libopus.0.dylib"
/usr/bin/codesign --force --options runtime --sign "$SIGN_ID" "$APP"

echo "Built $APP"
echo "Signed with: $SIGN_ID"
