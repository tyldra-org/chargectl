#!/usr/bin/env bash
# Builds Chargectl, installs it in /Applications with its root control service, and opens it.
# Run it again after any change: it replaces both.
#
#   ./scripts/install.sh            Release build
#   ./scripts/install.sh --debug    Debug build
#   ./scripts/install.sh --logs     then follow the service's log
#
# How the service is installed depends on the signature (see scripts/signing.sh):
#   Signed with a team (Apple Development or Developer ID): installed by an administrator into
#     /Library/LaunchDaemons. macOS treats that as approved, so it is on straight away, and
#     Login Items lists it under Chargectl's name and icon. Asks for your password once.
#   Ad hoc: registered by the app itself (SMAppService), listed as Chargectl. macOS adds it
#     switched off; turn it on under Login Items & Extensions (the script opens that page).
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

label=com.tyldra.chargectl.daemon
app=/Applications/Chargectl.app
binary="$app/Contents/MacOS/Chargectl"
plist=/Library/LaunchDaemons/$label.plist
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ -n "$CHARGECTL_TEAM" ]]; then
  mode=admin
  echo "Signing with team $CHARGECTL_TEAM."
else
  mode=app
  echo "No signing certificate with a team found; building ad hoc."
fi

# The admin install, and removing one left by an earlier install, need your password.
if [[ "$mode" == admin || -f "$plist" ]]; then
  sudo -v
  while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 30; done 2>/dev/null &
  keepalive=$!
  trap 'kill "$keepalive" 2>/dev/null' EXIT
fi

echo "Building Chargectl ($configuration)…"
"$CHARGECTL_ROOT/scripts/build.sh" "$configuration"
built="$CHARGECTL_DERIVED_DATA/Build/Products/$configuration/Chargectl.app"

# Stop whichever service is running. It reconnects wall power and restores the macOS charge
# limit before exiting. Both kinds use the same label, so only one may exist at a time.
pkill -x Chargectl 2>/dev/null || true
if [[ -x "$binary" ]]; then
  "$binary" --unregister-service || true
fi
if [[ -f "$plist" ]]; then
  sudo launchctl bootout "system/$label" 2>/dev/null || true
  sudo rm -f "$plist"
fi

rm -rf "$app"
ditto "$built" "$app"

# Xcode registers every build with Launch Services, which would list a second Chargectl in
# the Apps launcher. Keep only the installed copy.
for product in "$CHARGECTL_DERIVED_DATA"/Build/Products/*/Chargectl.app; do
  "$lsregister" -u "$product" 2>/dev/null || true
done
"$lsregister" -f "$app"

if [[ "$mode" == admin ]]; then
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
  echo "Chargectl $configuration installed; the control service is running."
else
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
fi

if [[ -n "${keepalive:-}" ]]; then kill "$keepalive" 2>/dev/null || true; fi
/usr/bin/open "$app"
echo "Remove everything with ./scripts/uninstall.sh or Settings > Uninstall Chargectl."
if [[ "$follow_logs" == 1 ]]; then
  exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.tyldra.chargectl"'
fi
