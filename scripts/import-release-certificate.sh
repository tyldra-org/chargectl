#!/usr/bin/env bash
# Release workflow only: imports Chargectl's release certificate from the
# CHARGECTL_RELEASE_CERTIFICATE (base64 .p12) and CHARGECTL_RELEASE_CERTIFICATE_PASSWORD secrets
# into a temporary keychain, and exports CHARGECTL_RELEASE_CERT and CHARGECTL_KEYCHAIN for the
# steps after it.
#
# Installed helpers replace themselves only with a helper signed by this exact certificate, so
# a release signed with anything else makes every user install the helper again. In this
# repository a missing or different certificate therefore fails the release. A fork has no
# secrets and is signed ad hoc.
set -euo pipefail
# SHA-1 of the certificate made with scripts/make-release-certificate.sh. Public; the private
# key exists only in the secrets and the maintainer's backup.
expected=653E52E5F86FE7D3F69BCAC212ABEFFC4DBCF82B
upstream=tyldra-org/chargectl
if [[ -z "${CERTIFICATE:-}" ]]; then
  if [[ "${GITHUB_REPOSITORY:-}" == "$upstream" ]]; then
    echo "::error::The release certificate secrets are missing. A release signed ad hoc would make every user install the helper again."
    exit 1
  fi
  echo "::notice::No release certificate; this build is signed ad hoc."
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
if [[ "${GITHUB_REPOSITORY:-}" == "$upstream" && "$sha1" != "$expected" ]]; then
  echo "::error::The release certificate is $sha1, not $expected. Installed helpers would refuse this release."
  exit 1
fi
{
  echo "CHARGECTL_RELEASE_CERT=$sha1"
  echo "CHARGECTL_KEYCHAIN=$keychain"
} >> "$GITHUB_ENV"
echo "Signing with the release certificate $sha1."
