#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
configuration="${1:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: build.sh [Debug|Release]' >&2; exit 2 ;; esac
"$CHARGECTL_ROOT/scripts/generate.sh"
signing=()
if [[ -n "${CHARGECTL_SIGN_IDENTITY:-}" && -n "${CHARGECTL_TEAM:-}" ]]; then
  signing=(CODE_SIGN_IDENTITY="$CHARGECTL_SIGN_IDENTITY" DEVELOPMENT_TEAM="$CHARGECTL_TEAM" CODE_SIGN_STYLE=Manual)
fi
# Built in so the helper and the updater know which certificate releases are signed with;
# package.sh signs with it.
signing+=(CHARGECTL_RELEASE_CERT="${CHARGECTL_RELEASE_CERT:-}")
# CHARGECTL_COMPILATION_CACHE=0 compiles everything from scratch, as the release workflow does
# for the build it publishes.
if [[ "${CHARGECTL_COMPILATION_CACHE:-1}" == 0 ]]; then signing+=(COMPILATION_CACHE_ENABLE_CACHING=NO); fi
exec xcodebuild -quiet -project "$CHARGECTL_ROOT/Chargectl.xcodeproj" -scheme Chargectl \
  -configuration "$configuration" -destination 'generic/platform=macOS' \
  -derivedDataPath "$CHARGECTL_DERIVED_DATA" ${signing[@]+"${signing[@]}"} build
