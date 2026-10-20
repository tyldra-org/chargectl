#!/usr/bin/env bash
# Finds a code-signing identity with a team in the login keychain; source this file.
# Sets CHARGECTL_SIGN_IDENTITY (SHA-1) and CHARGECTL_TEAM, or leaves both empty for an
# ad-hoc build. Override with CHARGECTL_SIGN_IDENTITY=<sha1> CHARGECTL_TEAM=<team id>.
#
# A team signature lets macOS list the control service under Chargectl's name and icon in
# Login Items, and lets the service accept only apps signed by the same team. A free
# "Apple Development" certificate (Xcode > Settings > Accounts) is enough on your own Mac.
if [[ -z "${CHARGECTL_SIGN_IDENTITY:-}" ]]; then
  for kind in "Developer ID Application" "Apple Development"; do
    line=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "\"$kind:" || true)
    if [[ -n "$line" ]]; then
      CHARGECTL_SIGN_IDENTITY=$(awk '{print $2}' <<<"$line")
      break
    fi
  done
fi
if [[ -n "${CHARGECTL_SIGN_IDENTITY:-}" && -z "${CHARGECTL_TEAM:-}" ]]; then
  CHARGECTL_TEAM=$(security find-certificate -a -Z -p 2>/dev/null |
    awk -v sha="$CHARGECTL_SIGN_IDENTITY" '
      /^SHA-1 hash:/ { take = ($3 == sha) }
      take { print }
      take && /END CERTIFICATE/ { exit }' |
    openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')
fi
export CHARGECTL_SIGN_IDENTITY="${CHARGECTL_SIGN_IDENTITY:-}" CHARGECTL_TEAM="${CHARGECTL_TEAM:-}"
