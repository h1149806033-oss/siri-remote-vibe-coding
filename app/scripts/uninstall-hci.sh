#!/bin/zsh
set -euo pipefail

LABEL="com.bossremote.hci"
DESTINATION="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
STATE="/Library/Application Support/BossRemote/HCI"
LOG="/var/log/bossremote_hci.log"

if [[ "$(/usr/bin/id -u)" != "0" ]]; then
  print -u2 "run this script with sudo"
  exit 1
fi

if [[ -x "$DESTINATION" ]]; then
  "$DESTINATION" --restore >/dev/null 2>&1 || true
fi
/bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST" "$DESTINATION" "$LOG"
/bin/rm -rf "$STATE"
print "Uninstalled $LABEL"
