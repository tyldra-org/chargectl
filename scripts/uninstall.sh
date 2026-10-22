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
# A helper that was not running could not reconnect wall power or restore the macOS charge
# limit when it stopped; do it now, before its files go.
helper="$app/Contents/MacOS/Chargectl Service"
if [[ -x "$helper" ]]; then
  sudo "$helper" --restore 2>/dev/null || true
fi
sudo rm -f "/Library/LaunchDaemons/$label.plist"
sudo rm -rf "/Library/Application Support/Chargectl"
sudo sh -c 'rm -f /Library/Logs/DiagnosticReports/Chargectl* /Library/Logs/DiagnosticReports/Retired/Chargectl* /Library/Logs/DiagnosticReports/chargectld* /Library/Logs/DiagnosticReports/Retired/chargectld*'
rm -rf "$app" "$HOME"/.Trash/Chargectl*.app
# The Dock tile and what Homebrew keeps of the cask: the same script Uninstall runs, from
# App/UninstallCleanup.swift, so the two cannot drift.
brew=
for prefix in /opt/homebrew /usr/local; do
  if [[ -x "$prefix/bin/brew" && ( -d "$prefix/Caskroom/chargectl" || -d "$prefix/Library/Taps/tyldra-org/homebrew-tools" ) ]]; then
    brew="$prefix/bin/brew"
  fi
done
cleanup=$(awk '/static let dock = """/{take=1; next} /static let homebrew = """/{take=1; next} take && /^        """/{take=0; next} take { sub(/^        /, ""); gsub(/\\\(bundleIdentifier\)/, "com.tyldra.chargectl"); gsub(/\\\(tap\)/, "tyldra-org/tools"); print }' "$(dirname "$0")/../App/UninstallCleanup.swift")
sh -c "$cleanup" chargectl-cleanup "$brew" >/dev/null 2>&1 || true

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
