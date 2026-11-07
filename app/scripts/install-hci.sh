#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
LABEL="com.bossremote.hci"
SOURCE="$ROOT/dist/Boss Remote Dev.app/Contents/Helpers/BossRemoteHCIService"
DESTINATION="/Library/PrivilegedHelperTools/$LABEL"
STAGING="/Library/PrivilegedHelperTools/.$LABEL.staging.$$"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
LOG="/var/log/bossremote_hci.log"

if [[ "$(/usr/bin/id -u)" != "0" ]]; then
  print -u2 "run this script with sudo"
  exit 1
fi
[[ -x "$SOURCE" ]] || { print -u2 "missing helper: $SOURCE"; exit 1; }

TEAM="$(/usr/bin/codesign -dvv "$SOURCE" 2>&1 |
  /usr/bin/sed -n 's/^TeamIdentifier=//p')"
if [[ -z "$TEAM" ]]; then
  print -u2 "helper has no Apple team identifier; sign it with an Apple certificate"
  exit 1
fi
REQUIREMENT="identifier \"$LABEL\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\""
if ! /usr/bin/codesign --verify --strict --requirements "$REQUIREMENT" "$SOURCE"; then
  print -u2 "helper signature does not satisfy: $REQUIREMENT"
  exit 1
fi

/bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
/bin/mkdir -p /Library/PrivilegedHelperTools
/bin/rm -rf "$STAGING"
/usr/bin/ditto --norsrc --noextattr --noqtn --noacl "$SOURCE" "$STAGING"
/usr/sbin/chown root:wheel "$STAGING"
/bin/chmod 755 "$STAGING"
/usr/bin/codesign --verify --strict --requirements "$REQUIREMENT" "$STAGING"
/bin/mv -f "$STAGING" "$DESTINATION"
/usr/sbin/chown root:wheel "$DESTINATION"
/bin/chmod 755 "$DESTINATION"
/usr/bin/codesign --verify --strict --requirements "$REQUIREMENT" "$DESTINATION"

/bin/rm -f "$PLIST"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $DESTINATION" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :MachServices dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :MachServices:$LABEL bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ProcessType string Interactive" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $LOG" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $LOG" "$PLIST"
/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"

"$DESTINATION" --restore >/dev/null 2>&1 || true
/bin/launchctl bootstrap system "$PLIST"
/bin/launchctl print "system/$LABEL" >/dev/null
print "Installed and started $LABEL"
