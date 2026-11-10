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
# The helper's root-owned copy; 0.2.0 to 0.2.4 named it after the label.
sudo rm -f "/Library/LaunchDaemons/$label.plist" /private/etc/sudoers.d/chargectl \
  "/Library/PrivilegedHelperTools/Chargectl Service" "/Library/PrivilegedHelperTools/Chargectl Service.new" \
  "/Library/PrivilegedHelperTools/$label" "/Library/PrivilegedHelperTools/$label.new"
sudo rm -rf "/Library/Application Support/Chargectl"
sudo sh -c 'rm -f /Library/Logs/DiagnosticReports/Chargectl* /Library/Logs/DiagnosticReports/Retired/Chargectl* /Library/Logs/DiagnosticReports/chargectld* /Library/Logs/DiagnosticReports/Retired/chargectld*'
rm -rf "$app"

# What Homebrew keeps of the cask, when it installed Chargectl.
brew=
for prefix in /opt/homebrew /usr/local; do
  if [[ -x "$prefix/bin/brew" && ( -d "$prefix/Caskroom/chargectl" || -d "$prefix/Library/Taps/tyldra-org/homebrew-tools" ) ]]; then
    brew="$prefix/bin/brew"
  fi
done

# The same cleanup Uninstall runs, read out of Shared/UninstallCleanup.swift so the two cannot
# drift: the Library items, crash reports and /private/var/folders entries, copies in the Trash,
# the Dock tile and Homebrew's record.
section() {
  awk -v name="$1" '$0 ~ "static let " name " = \"\"\"" { take = 1; next } take && /^        """/ { exit } take { sub(/^        /, ""); print }' \
    "$(dirname "$0")/../Shared/UninstallCleanup.swift" |
    sed -e 's/\\(bundleIdentifier)/com.tyldra.chargectl/g' -e 's/\\(widgetsIdentifier)/com.tyldra.chargectl.widgets/g' \
      -e 's/\\(widgetsProcess)/ChargectlWidgets/g' -e 's|\\(tap)|tyldra-org/tools|g'
}
cleanup="$(section files)
$(section trash)
$(section dock)
$(section homebrew)"
if [[ "$cleanup" != *'Containers/$widgets'* ]]; then
  echo 'uninstall.sh: could not read the cleanup from Shared/UninstallCleanup.swift' >&2
  exit 1
fi
sh -c "$cleanup" chargectl-cleanup "$brew" >/dev/null 2>&1 || true

# The root service's cache and temporary folders under /private/var/folders.
sudo sh -c 'for dir in "$(getconf DARWIN_USER_CACHE_DIR)" "$(getconf DARWIN_USER_TEMP_DIR)"; do rm -rf "$dir"'"$id"'*; done'
rm -rf "${TMPDIR:-/tmp}/Chargectl-DerivedData"

user_dirs() { echo "$(getconf DARWIN_USER_CACHE_DIR)" "$(getconf DARWIN_USER_TEMP_DIR)"; }
leftovers=$( { find "$HOME/Library" /Library -maxdepth 3 -name "*$id*" -not -path "*/Caches/Homebrew/*"; for dir in $(user_dirs); do ls -d "$dir"$id*; done; } 2>/dev/null || true)
if [[ -n "$leftovers" ]]; then
  echo "Still present:"; echo "$leftovers"
else
  echo 'Chargectl removed. Nothing left behind.'
fi
