#!/usr/bin/env bash
# Builds a Release Chargectl.app and packs it for a GitHub release.
#
#   ./scripts/package.sh [output-dir]    default: dist
#
# Writes Chargectl-<version>.zip and Chargectl-<version>.zip.sha256, where <version> is
# MARKETING_VERSION in project.yml, and prints the zip's path. The app is signed ad hoc
# unless CHARGECTL_SIGN_IDENTITY and CHARGECTL_TEAM are set.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

out="${1:-$CHARGECTL_ROOT/dist}"
version=$("$CHARGECTL_ROOT/scripts/version.sh")

"$CHARGECTL_ROOT/scripts/build.sh" Release >&2
app="$CHARGECTL_DERIVED_DATA/Build/Products/Release/Chargectl.app"
built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ "$built" != "$version" ]]; then
  echo "package.sh: built version $built does not match project.yml ($version)" >&2
  exit 1
fi
codesign --verify --deep --strict "$app"

mkdir -p "$out"
zip="$out/Chargectl-$version.zip"
rm -f "$zip" "$zip.sha256"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "${zip##*/}" > "${zip##*/}.sha256")
echo "$zip"
