#!/usr/bin/env bash
# Release workflow only: imports Chargectl's release certificate from the
# CHARGECTL_RELEASE_CERTIFICATE (base64 .p12) and CHARGECTL_RELEASE_CERTIFICATE_PASSWORD secrets
# into a temporary keychain, and exports CHARGECTL_RELEASE_CERT and CHARGECTL_KEYCHAIN for the
# steps after it. Without the secrets the release is signed ad hoc, as before.
set -euo pipefail
if [[ -z "${CERTIFICATE:-}" ]]; then
  echo "::notice::No release certificate; the release is signed ad hoc, and each update asks for the administrator password to update the helper."
  exit 0
fi
keychain="$RUNNER_TEMP/release.keychain-db"
keychain_password=$(openssl rand -base64 24)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
printf '%s' "$CERTIFICATE" | base64 -D > "$RUNNER_TEMP/release.p12"
security import "$RUNNER_TEMP/release.p12" -f pkcs12 -k "$keychain" -P "$PASSWORD" -T /usr/bin/codesign
rm -f "$RUNNER_TEMP/release.p12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
# Self-signed, so not "valid" to find-identity -v; take the first code-signing identity.
sha1=$(security find-identity -p codesigning "$keychain" | awk '/[0-9A-F]{40}/ { print $2; exit }')
if [[ -z "$sha1" ]]; then
  echo "::error::The release certificate has no code-signing identity."
  exit 1
fi
{
  echo "CHARGECTL_RELEASE_CERT=$sha1"
  echo "CHARGECTL_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
echo "Signing with the release certificate $sha1."
