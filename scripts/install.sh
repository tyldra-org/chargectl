#!/usr/bin/env bash
# Builds Chargectl, installs it in /Applications and registers its control service through
# the app itself (SMAppService), so Login Items lists it as Chargectl with the app's icon.
# Run it again after any change: it replaces both.
#
#   ./scripts/install.sh            Release build
#   ./scripts/install.sh --debug    Debug build
#   ./scripts/install.sh --logs     then follow the service's log
#
# macOS adds a new service switched off. The first install (and, while builds are signed ad
# hoc, every update) asks you to turn Chargectl on under System Settings > General >
# Login Items & Extensions; the script opens that page for you.
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
legacy_plist=/Library/LaunchDaemons/$label.plist
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Earlier versions installed the service with a plist in /Library/LaunchDaemons. Removing it
# needs your password once; stopping the service reconnects wall power first.
if [[ -f "$legacy_plist" ]]; then
  echo "Removing the service installed by an earlier version…"
  sudo launchctl bootout "system/$label" 2>/dev/null || true
  sudo rm -f "$legacy_plist"
fi

echo "Building Chargectl ($configuration)…"
"$CHARGECTL_ROOT/scripts/build.sh" "$configuration"
built="$CHARGECTL_DERIVED_DATA/Build/Products/$configuration/Chargectl.app"

pkill -x Chargectl 2>/dev/null || true
# Unregistering stops the running service, which reconnects wall power and restores the
# macOS charge limit before the binary is replaced.
if [[ -x "$binary" ]]; then
  "$binary" --unregister-service || true
fi
rm -rf "$app"
ditto "$built" "$app"

# Xcode registers every build with Launch Services, which would list a second Chargectl in
# the Apps launcher. Keep only the installed copy.
for product in "$CHARGECTL_DERIVED_DATA"/Build/Products/*/Chargectl.app; do
  "$lsregister" -u "$product" 2>/dev/null || true
done
"$lsregister" -f "$app"

status=0
result=$("$binary" --register-service) || status=$?
case "$status" in
  0) echo "Chargectl $configuration installed; the control service is running." ;;
  2)
    echo "Chargectl $configuration installed."
    echo "Turn on Chargectl under System Settings > General > Login Items & Extensions"
    echo "(Allow in the Background) to start the control service."
    /usr/bin/open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    ;;
  *) echo "The control service could not be registered: $result" >&2 ;;
esac

/usr/bin/open "$app"
echo "Remove everything with ./scripts/uninstall.sh or Settings > Uninstall Chargectl."
if [[ "$follow_logs" == 1 ]]; then
  exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.tyldra.chargectl"'
fi
