#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$ROOT/Resources/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$ROOT/Resources/Info.plist")"
APP="$ROOT/dist/Boss Remote.app"
DMG="$ROOT/dist/Boss-Remote-$VERSION-arm64.dmg"

SIGN_ID="${BOSS_REMOTE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_ID" ]]; then
  print -u2 "No signing identity found; set BOSS_REMOTE_SIGN_IDENTITY"
  exit 1
fi

cd "$ROOT"
swift build -c release --product BossRemote
swift build -c release --product BossRemoteHCIService
BIN_DIR="$(swift build -c release --show-bin-path)"

/bin/rm -rf "$APP"
/bin/mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources" \
  "$APP/Contents/Helpers" \
  "$APP/Contents/Frameworks"
/usr/bin/ditto "$BIN_DIR/BossRemote" "$APP/Contents/MacOS/BossRemote"
/usr/bin/ditto "$BIN_DIR/BossRemoteHCIService" \
  "$APP/Contents/Helpers/BossRemoteHCIService"

# Release identity: a distinct bundle id so the shipped build never shares
# permissions or preferences with a local development build.
PLIST="$ROOT/dist/release-Info.plist"
/usr/bin/ditto "$ROOT/Resources/Info.plist" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Boss Remote" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Boss Remote" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.bossremote.app" "$PLIST"
/usr/bin/ditto "$PLIST" "$APP/Contents/Info.plist"
/bin/rm -f "$PLIST"

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

STAGE="$ROOT/dist/dmg-root"
/bin/rm -rf "$STAGE"
/bin/mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/Boss Remote.app"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/rm -f "$DMG"
/usr/bin/hdiutil create \
  -volname "Boss Remote" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  "$DMG" >/dev/null
/bin/rm -rf "$STAGE"

echo "Built $APP"
echo "Version $VERSION ($BUILD)"
echo "Package $DMG"
echo "Signed with: $SIGN_ID"
