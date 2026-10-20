#!/usr/bin/env bash
# Builds Chargectl and installs it in /Applications. Run it again after any change;
# a helper that is already installed restarts into the new version by itself.
#
#   ./scripts/install.sh            Release build
#   ./scripts/install.sh --debug    Debug build
#   ./scripts/install.sh --logs     then follow the helper's log
#
# Open Chargectl from Applications afterwards: its welcome window installs the helper (the root
# service that controls charging) and sets the first limit. See scripts/signing.sh for signing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$CHARGECTL_ROOT/scripts/signing.sh"

configuration=Release
follow_logs=0
for argument in "$@"; do
  case "$argument" in
    --debug) configuration=Debug ;;
    --logs) follow_logs=1 ;;
    *) echo 'Usage: install.sh [--debug] [--logs]' >&2; exit 2 ;;
  esac
done

app=/Applications/Chargectl.app
binary="$app/Contents/MacOS/Chargectl"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ -n "$CHARGECTL_TEAM" ]]; then
  echo "Signing with team $CHARGECTL_TEAM."
fi
echo "Building Chargectl ($configuration)…"
"$CHARGECTL_ROOT/scripts/build.sh" "$configuration"
built="$CHARGECTL_DERIVED_DATA/Build/Products/$configuration/Chargectl.app"

pkill -x Chargectl 2>/dev/null || true
# Earlier versions could register the helper through SMAppService; that copy has the same
# label as the administrator-installed helper and must go.
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

if [[ -f /Library/LaunchDaemons/com.tyldra.chargectl.daemon.plist ]]; then
  echo "Chargectl $configuration installed; the helper restarts into the new version."
else
  echo "Chargectl $configuration installed. Open it from Applications to finish setup."
fi
echo "Remove everything with ./scripts/uninstall.sh or Settings > Uninstall Chargectl."
if [[ "$follow_logs" == 1 ]]; then
  exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.tyldra.chargectl"'
fi
