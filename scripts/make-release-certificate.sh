#!/usr/bin/env bash
# Creates Chargectl's release certificate: a self-signed code-signing certificate that releases
# are signed with when there is no Apple team. The helper and the in-app updater then accept only
# code signed with it, so updates replace the root helper without asking for a password, and no
# local process can pose as the app.
#
#   ./scripts/make-release-certificate.sh <folder>
#
# Writes <folder>/chargectl-release.p12 (the private key; keep it out of the repository and
# backed up) and prints its SHA-1 and the commands that store it as the release workflow's
# secrets. Losing the key means the next release cannot update the helper by itself; a leaked key
# lets anyone sign code the helper trusts.
set -euo pipefail
folder="${1:?Usage: make-release-certificate.sh <folder>}"
mkdir -p "$folder"
chmod 700 "$folder"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

openssl req -x509 -newkey rsa:3072 -days 7300 -nodes -subj "/CN=Chargectl Release" \
  -keyout "$work/key" -out "$work/certificate" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" 2>/dev/null
password=$(openssl rand -base64 24)
# Algorithms macOS's security tool can import.
openssl pkcs12 -export -inkey "$work/key" -in "$work/certificate" -name "Chargectl Release" \
  -out "$folder/chargectl-release.p12" -passout "pass:$password" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
chmod 600 "$folder/chargectl-release.p12"
sha1=$(openssl x509 -in "$work/certificate" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')

cat <<EOF
Release certificate: $folder/chargectl-release.p12
SHA-1: $sha1

Store it for the release workflow (run these yourself):
  base64 -i "$folder/chargectl-release.p12" | gh secret set CHARGECTL_RELEASE_CERTIFICATE
  printf '%s' '$password' | gh secret set CHARGECTL_RELEASE_CERTIFICATE_PASSWORD

To sign a local build with it, import it into your login keychain, then build with
CHARGECTL_RELEASE_CERT=$sha1 ./scripts/package.sh
EOF
