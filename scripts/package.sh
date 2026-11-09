#!/usr/bin/env bash
# Builds a Release Chargectl.app and packs it for a GitHub release.
#
#   ./scripts/package.sh [output-dir]    default: dist
#
# Writes Chargectl-<version>.zip and Chargectl-<version>.zip.sha256, where <version> is
# MARKETING_VERSION in project.yml, and prints the zip's path. The app is signed ad hoc
# unless CHARGECTL_SIGN_IDENTITY and CHARGECTL_TEAM are set, or with Chargectl's release
# certificate when CHARGECTL_RELEASE_CERT holds its SHA-1 (CHARGECTL_KEYCHAIN: the keychain
# it is in, when not the login keychain). See scripts/make-release-certificate.sh.
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
if [[ -n "${CHARGECTL_RELEASE_CERT:-}" && -z "${CHARGECTL_TEAM:-}" ]]; then
  keychain=()
  if [[ -n "${CHARGECTL_KEYCHAIN:-}" ]]; then keychain=(--keychain "$CHARGECTL_KEYCHAIN"); fi
  # The helper and the widgets first, then the app that seals them.
  for code in "$app/Contents/MacOS/Chargectl Service" "$app/Contents/PlugIns/ChargectlWidgets.appex" "$app"; do
    codesign --force --options runtime --preserve-metadata=identifier,entitlements \
      --sign "$CHARGECTL_RELEASE_CERT" ${keychain[@]+"${keychain[@]}"} "$code"
  done
  codesign --verify --strict \
    -R="identifier \"com.tyldra.chargectl\" and certificate leaf = H\"$CHARGECTL_RELEASE_CERT\"" "$app"
  codesign --verify --strict \
    -R="identifier \"com.tyldra.chargectl.daemon\" and certificate leaf = H\"$CHARGECTL_RELEASE_CERT\"" \
    "$app/Contents/MacOS/Chargectl Service"
fi
codesign --verify --deep --strict "$app"

mkdir -p "$out"
zip="$out/Chargectl-$version.zip"
rm -f "$zip" "$zip.sha256"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "${zip##*/}" > "${zip##*/}.sha256")
echo "$zip"
