#!/usr/bin/env bash
# Removes everything Chargectl added to this Mac. Same result as Settings › Uninstall
# Chargectl…. Stopping the service makes it reconnect wall power before it exits.
# The project folder itself is left alone.
set -euo pipefail
id=com.tyldra.chargectl
label=$id.daemon
app=/Applications/Chargectl.app

sudo -v
pkill -x Chargectl 2>/dev/null || true

# Login Items entries can only be removed by the app itself.
for binary in "$app/Contents/MacOS/Chargectl" "$HOME"/.Trash/Chargectl*.app/Contents/MacOS/Chargectl; do
  [[ -x "$binary" ]] && "$binary" --unregister-services 2>/dev/null || true
done

sudo launchctl bootout "system/$label" 2>/dev/null || true
sudo rm -f "/Library/LaunchDaemons/$label.plist"
sudo rm -rf "/Library/Application Support/Chargectl"
rm -rf "$app" "$HOME"/.Trash/Chargectl*.app

# Per-user cache and temp folders under /private/var/folders, for you and for the root service.
user_dirs() { echo "$(getconf DARWIN_USER_CACHE_DIR)" "$(getconf DARWIN_USER_TEMP_DIR)"; }
for dir in $(user_dirs); do rm -rf "$dir"$id*; done
sudo sh -c 'for dir in "$(getconf DARWIN_USER_CACHE_DIR)" "$(getconf DARWIN_USER_TEMP_DIR)"; do rm -rf "$dir"'"$id"'*; done'

# Through cfprefsd first, so its cached copy cannot write the file back.
defaults delete "$id" 2>/dev/null || true
rm -rf "$HOME/Library/Preferences/$id.plist" \
  "$HOME/Library/Caches/$id" \
  "$HOME/Library/HTTPStorages/$id" "$HOME/Library/HTTPStorages/$id.binarycookies" \
  "$HOME/Library/Saved Application State/$id.savedState" \
  "$HOME/Library/Application Support/$id" \
  "$HOME/Library/WebKit/$id" \
  "$HOME"/Library/Logs/DiagnosticReports/Chargectl* \
  "$HOME"/Library/Logs/DiagnosticReports/chargectld* \
  "${TMPDIR:-/tmp}/Chargectl-DerivedData"

leftovers=$( { find "$HOME/Library" /Library -maxdepth 3 -name "*$id*"; for dir in $(user_dirs); do ls -d "$dir"$id*; done; } 2>/dev/null || true)
if [[ -n "$leftovers" ]]; then
  echo "Still present:"; echo "$leftovers"
else
  echo 'Chargectl removed. Nothing left behind.'
fi
