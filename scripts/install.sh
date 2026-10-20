#!/usr/bin/env bash
# Builds Chargectl, installs it in /Applications with its root control service, and opens it.
# Run it again after any change: it replaces both. Asks for your password once.
#
#   ./scripts/install.sh            Release build
#   ./scripts/install.sh --debug    Debug build
#   ./scripts/install.sh --logs     then follow the service's log
#
# The service is installed by an administrator into /Library/LaunchDaemons, which macOS
# treats as approved: it runs straight away and survives updates. Because builds are signed
# ad hoc, Login Items lists it as "Chargectl Service" with a generic icon; only Developer ID
# signing lets macOS show it under Chargectl's name and icon.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

configuration=Release
follow_logs=0
for argument in "$@"; do
  case "$argument" in
    --debug) configuration=Debug ;;
    --logs) follow_logs=1 ;;
    *) echo 'Usage: install.sh [--debug] [--logs]' >&2; exit 2 ;;
  esac
done

label=com.tyldra.chargectl.daemon
app=/Applications/Chargectl.app
binary="$app/Contents/MacOS/Chargectl"
plist=/Library/LaunchDaemons/$label.plist
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Ask for the password first, then keep sudo alive while the build runs.
sudo -v
while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 30; done 2>/dev/null &
keepalive=$!
trap 'kill "$keepalive" 2>/dev/null' EXIT

echo "Building Chargectl ($configuration)…"
"$CHARGECTL_ROOT/scripts/build.sh" "$configuration"
built="$CHARGECTL_DERIVED_DATA/Build/Products/$configuration/Chargectl.app"

pkill -x Chargectl 2>/dev/null || true
# A service registered by the app's own Install button uses the same label; two copies make
# launchd refuse the second ("Bootstrap failed: 5"). Remove it before installing.
if [[ -x "$binary" ]]; then
  "$binary" --unregister-service || true
fi
# Stopping the service makes it reconnect wall power and restore the macOS charge limit
# before its binary is replaced.
sudo launchctl bootout "system/$label" 2>/dev/null || true
rm -rf "$app"
ditto "$built" "$app"

# Xcode registers every build with Launch Services, which would list a second Chargectl in
# the Apps launcher. Keep only the installed copy.
for product in "$CHARGECTL_DERIVED_DATA"/Build/Products/*/Chargectl.app; do
  "$lsregister" -u "$product" 2>/dev/null || true
done
"$lsregister" -f "$app"

sudo tee "$plist" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>$label</string>
    <key>Program</key><string>$app/Contents/MacOS/Chargectl Service</string>
    <key>AssociatedBundleIdentifiers</key><array><string>com.tyldra.chargectl</string></array>
    <key>MachServices</key><dict><key>$label</key><true/></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
sudo chown root:wheel "$plist"
sudo chmod 644 "$plist"
sudo launchctl bootstrap system "$plist"

kill "$keepalive" 2>/dev/null || true
/usr/bin/open "$app"
echo "Chargectl $configuration installed; the control service is running."
echo "Remove everything with ./scripts/uninstall.sh or Settings > Uninstall Chargectl."
if [[ "$follow_logs" == 1 ]]; then
  exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.tyldra.chargectl"'
fi
